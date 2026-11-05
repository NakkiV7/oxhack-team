import Foundation

public struct WorkoutStep: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let exerciseID: String
    public let number: Int
    public let totalSets: Int
    public let target: Int
    public let unit: ExerciseEntry.Unit
    public let restSeconds: Int
    public var entry: ExerciseEntry { ExerciseCatalog.find(exerciseID)! }
    init(id: UUID = UUID(), exerciseID: String, number: Int, totalSets: Int, target: Int, unit: ExerciseEntry.Unit, restSeconds: Int) {
        self.id = id; self.exerciseID = exerciseID; self.number = number; self.totalSets = totalSets
        self.target = target; self.unit = unit; self.restSeconds = restSeconds
    }
}

public struct ConfigurableSession: Sendable {
    public enum Invalid: Error { case plan }
    public let id = UUID()
    public let date = Date()
    public private(set) var steps: [WorkoutStep]
    public private(set) var generation = UUID()
    public private(set) var phase: SessionPhase = .idle
    public private(set) var index = 0
    public private(set) var completed: [LoggedSet] = []
    public private(set) var skippedSets: [SkippedSet] = []
    public private(set) var hasStarted = false
    public private(set) var manualReps: Int?
    public private(set) var stoppedForDiscomfort = false
    public private(set) var telemetry: [WatchTelemetry] = []
    public private(set) var source: InputSource = .manual
    public private(set) var holdCounter: PoseHoldCounter?
    public private(set) var counter: RepCounter?
    public private(set) var cue: Cue = .ready
    public private(set) var repDurations: [Double] = []
    private var activeStarted: Double?
    private var accumulated = 0.0
    private var includesManualReps = false
    private var manualSeconds = 0.0
    private var manualStarted: Double?
    private var includesCameraReps = false
    private var restStarted: Double?
    private var restBefore: Double?
    public var current: WorkoutStep { steps[index] }
    public var trackingExercise: Exercise? { current.entry.tracking }
    public var actualReps: Int? { source == .camera ? counter?.reps : manualReps }
    public var record: SessionRecord { .init(id: id, date: date, sets: [], telemetry: telemetry, loggedSets: completed, skippedSets: skippedSets) }

    public init(plan: CoachSavedPlan, availableSupport: Set<String>) throws {
        guard (1...12).contains(plan.items.count), plan.approvedAt.timeIntervalSince1970.isFinite,
              Set(plan.items.map(\.exerciseID)).count == plan.items.count else { throw Invalid.plan }
        for item in plan.items {
            guard let entry = ExerciseCatalog.find(item.exerciseID), entry.unit == item.unit,
                  (1...10).contains(item.sets), (1...(item.unit == .reps ? 200 : 600)).contains(item.target),
                  (0...600).contains(item.restSeconds),
                  entry.support.map({ availableSupport.contains($0) }) ?? true else { throw Invalid.plan }
        }
        guard plan.items.reduce(0, { $0 + $1.sets }) <= 120 else { throw Invalid.plan }
        steps = plan.items.flatMap { item in
            (1...item.sets).map { WorkoutStep(exerciseID: item.exerciseID, number: $0, totalSets: item.sets,
                target: item.target, unit: item.unit, restSeconds: item.restSeconds) }
        }
    }

    public func elapsed(at time: Double) -> Double {
        accumulated + max(0, time - (activeStarted ?? time))
    }
    public func measuredSeconds(at time: Double) -> Double {
        (holdCounter?.observedSeconds ?? 0) + manualSeconds + max(0, time - (manualStarted ?? time))
    }
    public func quantityOrigin(at time: Double) -> LoggedSet.QuantityOrigin? {
        let manual = current.unit == .seconds ? manualSeconds + max(0, time - (manualStarted ?? time)) > 0 : includesManualReps
        let camera = current.unit == .seconds ? (holdCounter?.observedSeconds ?? 0) > 0 : includesCameraReps
        if manual && camera { return .mixed }
        return current.unit == .seconds ? (camera ? .cameraObserved : .activeTimer) : (manual ? .selfReport : nil)
    }
    public func quantitySourcePresentation(at time: Double) -> (title: String, symbol: String) {
        let hasQuantity = current.unit == .seconds ? measuredSeconds(at: time) > 0 : (actualReps ?? 0) > 0
        if hasQuantity {
            switch quantityOrigin(at: time) {
            case .mixed: return ("Camera + manual quantity", "camera")
            case .activeTimer: return ("Manual hold, active timer", "hand.tap")
            case .selfReport: return ("Manual self-report", "hand.tap")
            case .cameraObserved, nil: return ("Camera observation", "camera")
            }
        }
        // Before any work is earned, describe the selected input.
        return source == .camera ? ("Camera observation", "camera") : (current.unit == .seconds ? "Manual hold, active timer" : "Manual self-report", "hand.tap")
    }
    public func restElapsed(at time: Double) -> Double? {
        guard phase == .rest, time.isFinite, let restStarted else { return nil }
        return max(0, time - restStarted)
    }
    public func canEndSet(at time: Double) -> Bool {
        guard hasStarted, phase == .active || phase == .paused, time.isFinite else { return false }
        return current.unit == .reps ? (actualReps ?? 0) > 0 : measuredSeconds(at: time) >= 1
    }
    public mutating func start(at time: Double) {
        guard phase == .idle, time.isFinite else { return }
        phase = .active
    }
    public mutating func beginSet(at time: Double) {
        guard phase == .active, !hasStarted, time.isFinite else { return }
        if let restStarted { restBefore = max(0, time - restStarted) }
        restStarted = nil
        hasStarted = true; activeStarted = time; generation = UUID()
        if current.unit == .seconds && source == .manual { manualStarted = time }
    }
    @discardableResult public mutating func resetSet(source: InputSource, at time: Double) -> Bool {
        guard time.isFinite, phase == .active || phase == .paused, !stoppedForDiscomfort,
              source == .manual || (source == .camera && trackingExercise != nil) else { return false }
        self.source = source
        counter = source == .camera && current.unit == .reps ? trackingExercise.map { RepCounter(exercise: $0) } : nil
        holdCounter = source == .camera && current.unit == .seconds ? trackingExercise.map { PoseHoldCounter(exercise: $0) } : nil
        hasStarted = false; manualReps = nil; activeStarted = nil; accumulated = 0
        manualSeconds = 0; manualStarted = nil; includesManualReps = false; includesCameraReps = false
        repDurations = []; cue = .ready; phase = .active; generation = UUID()
        return true
    }
    @discardableResult public mutating func switchInput(source: InputSource, at time: Double) -> Bool {
        guard time.isFinite, phase == .active || phase == .paused, !stoppedForDiscomfort,
              source == .manual || (source == .camera && trackingExercise != nil) else { return false }
        guard hasStarted else { return resetSet(source: source, at: time) }
        let count = actualReps ?? 0
        if let manualStarted { manualSeconds += max(0, time - manualStarted) }
        manualStarted = current.unit == .seconds && source == .manual && phase == .active ? time : nil
        holdCounter?.resetContinuity()
        if current.unit == .seconds && holdCounter == nil, let exercise = trackingExercise, source == .camera { holdCounter = PoseHoldCounter(exercise: exercise) }
        self.source = source
        counter = source == .camera && current.unit == .reps ? trackingExercise.map { RepCounter(exercise: $0, initialReps: count) } : nil
        manualReps = source == .manual && count > 0 ? count : nil
        generation = UUID(); cue = phase == .paused ? .paused : .ready
        return true
    }
    public mutating func consume(_ sample: MovementSample, generation: UUID) {
        guard source == .camera, phase == .active, hasStarted, generation == self.generation else { return }
        if current.unit == .seconds {
            cue = holdCounter?.consume(sample) ?? .tracking
            return
        }
        guard var counter else { return }
        let previous = counter.reps
        let movementCue = counter.consume(sample)
        if counter.reps > previous { includesCameraReps = true }
        if counter.reps > previous, let duration = counter.lastRepDuration { repDurations.append(duration) }
        cue = movementCue != .tracking && sample.bodyLine == .adjust ? .alignment : movementCue
        self.counter = counter
    }
    public mutating func setReps(_ value: Int?) {
        guard source == .manual, current.unit == .reps, phase == .active || phase == .paused else { return }
        if let value, value == manualReps { return }
        manualReps = value.flatMap { (1...200).contains($0) ? $0 : nil }
        if manualReps != nil { includesManualReps = true }
    }
    public mutating func pause(at time: Double) {
        guard phase == .active, hasStarted, time.isFinite else { return }
        if let manualStarted { manualSeconds += max(0, time - manualStarted) }
        manualStarted = nil
        accumulated = elapsed(at: time); activeStarted = nil; phase = .paused; generation = UUID()
        counter?.resetMovement(); holdCounter?.resetContinuity(); cue = .paused
    }
    public mutating func resume(at time: Double) {
        guard phase == .paused, time.isFinite else { return }
        activeStarted = time; phase = .active; generation = UUID(); cue = .ready
        if current.unit == .seconds && source == .manual { manualStarted = time }
    }
    @discardableResult public mutating func endSet(at time: Double, reason: StopReason = .voluntary) -> Bool {
        guard canEndSet(at: time) else { return false }
        let seconds = elapsed(at: time)
        let manualQuantity = current.unit == .seconds ? manualSeconds + max(0, time - (manualStarted ?? time)) > 0 : includesManualReps
        let cameraQuantity = current.unit == .seconds ? (holdCounter?.observedSeconds ?? 0) > 0 : includesCameraReps
        let origin = quantityOrigin(at: time)
        completed.append(.init(id: UUID(), exerciseID: current.exerciseID,
            reps: current.unit == .reps ? (actualReps ?? 0) : 0,
            seconds: current.unit == .seconds ? measuredSeconds(at: time) : 0, source: manualQuantity ? .manual : (cameraQuantity ? .camera : source), reason: reason,
            number: current.number, target: current.target, activeSeconds: seconds,
            restSecondsBefore: restBefore, quantityOrigin: origin,
            repDurations: current.unit == .reps && cameraQuantity && !manualQuantity ? repDurations : nil))
        if reason == .discomfort { stoppedForDiscomfort = true }
        restStarted = time; activeStarted = nil; manualStarted = nil; accumulated = 0; phase = .rest; generation = UUID()
        return true
    }
    public var currentWasSkipped: Bool {
        phase == .rest && skippedSets.last?.exerciseID == current.exerciseID && skippedSets.last?.number == current.number
    }
    public func canSkipSet(at time: Double) -> Bool {
        guard time.isFinite, phase == .active || phase == .paused, !stoppedForDiscomfort else { return false }
        return current.unit == .reps ? (actualReps ?? 0) == 0 : !hasStarted || measuredSeconds(at: time) == 0
    }
    @discardableResult public mutating func skipSet(at time: Double) -> Bool {
        guard canSkipSet(at: time) else { return false }
        skippedSets.append(.init(id: UUID(), exerciseID: current.exerciseID, number: current.number,
                                target: current.target, unit: current.unit, source: source, reason: .userChoice))
        if hasStarted { restStarted = time }
        activeStarted = nil; accumulated = 0; hasStarted = false; phase = .rest; generation = UUID()
        return true
    }
    public var canReduceRemainingRepTargets: Bool {
        guard phase == .rest, !stoppedForDiscomfort, !currentWasSkipped, current.unit == .reps,
              let last = completed.last, last.exerciseID == current.exerciseID, last.number == current.number,
              last.reps == 1, last.seconds == 0 else { return false }
        return steps.dropFirst(index + 1).contains { $0.exerciseID == current.exerciseID && $0.unit == .reps && $0.target > 1 }
    }
    @discardableResult public mutating func reduceRemainingRepTargetsToOne() -> Bool {
        guard canReduceRemainingRepTargets else { return false }
        steps = steps.enumerated().map { offset, step in
            guard offset > index, step.exerciseID == current.exerciseID, step.unit == .reps else { return step }
            return WorkoutStep(id: step.id, exerciseID: step.exerciseID, number: step.number,
                               totalSets: step.totalSets, target: 1, unit: step.unit, restSeconds: step.restSeconds)
        }
        generation = UUID()
        return true
    }
    public mutating func nextSet(at time: Double) {
        guard phase == .rest, time.isFinite, !stoppedForDiscomfort else { return }
        guard index + 1 < steps.count else { phase = .finished; generation = UUID(); return }
        index += 1; hasStarted = false; manualReps = nil; phase = .active; generation = UUID()
        source = .manual; counter = nil; holdCounter = nil; manualSeconds = 0; manualStarted = nil; includesCameraReps = false; cue = .ready; repDurations = []; restBefore = nil; includesManualReps = false
    }
    public mutating func feedback(reserve: Int?, reason: StopReason) {
        guard phase == .rest, !completed.isEmpty,
              completed.last?.exerciseID == current.exerciseID, completed.last?.number == current.number else { return }
        if reason == .discomfort { stoppedForDiscomfort = true }
        completed[completed.count - 1].reason = stoppedForDiscomfort ? .discomfort : reason
        completed[completed.count - 1].reserve = reserve.flatMap { (0...3).contains($0) ? $0 : nil }
    }
    public mutating func stopForDiscomfort(at time: Double) {
        guard time.isFinite, phase == .active || phase == .paused else { return }
        if canEndSet(at: time) { endSet(at: time, reason: .discomfort); return }
        stoppedForDiscomfort = true; activeStarted = nil; accumulated = 0; restStarted = nil
        phase = .rest; generation = UUID()
    }
    public mutating func finish(at time: Double) {
        guard time.isFinite, phase != .idle, phase != .finished else { return }
        activeStarted = nil; phase = .finished; generation = UUID()
    }
    public mutating func receiveArchivedTelemetry(_ samples: [WatchTelemetry], now: Date = Date()) throws {
        guard [.active, .paused, .rest].contains(phase) else { throw WatchTelemetryImportError.lifetime }
        telemetry = try WatchTelemetryImporter.merge(samples, into: record, through: now, allowsOpenSession: true).telemetry
    }
    public mutating func receiveTelemetry(_ sample: WatchTelemetry, now: Date = Date()) {
        guard [.active, .paused, .rest].contains(phase), sample.sessionID == id else { return }
        let age = now.timeIntervalSince(sample.sentAt)
        guard age >= -2, age <= 12, sample.sentAt > (telemetry.last?.sentAt ?? .distantPast) else { return }
        let readings = [sample.heartRate, sample.accelerationG, sample.rotationRadiansPerSecond].compactMap { $0 }
        guard readings.allSatisfy({ $0.value.isFinite && $0.value >= 0 && $0.date.timeIntervalSince1970.isFinite }) else { return }
        guard sample.activeEnergy.map({ $0.isValid(at: sample.sentAt) && $0.isValid(at: now) && $0.asOf >= date.addingTimeInterval(-2) }) ?? true else { return }
        telemetry = Array((telemetry + [sample]).suffix(7200))
    }
}

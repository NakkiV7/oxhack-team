import Foundation

public enum SessionPhase: String, Codable, Sendable { case idle, active, paused, rest, finished }
public enum InputSource: String, Codable, Sendable { case camera, video, manual }
public enum StopReason: String, Codable, CaseIterable, Sendable {
    case target, voluntary, form, failure, discomfort
    public var title: String {
        switch self {
        case .target: return "Reached my target"
        case .voluntary: return "Chose to stop"
        case .form: return "Form was slipping"
        case .failure: return "Couldn’t complete another rep"
        case .discomfort: return "Pain or discomfort"
        }
    }
}

public struct SetRecord: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let exercise: Exercise
    public let number: Int
    public let reps: Int
    public let target: Int
    public let activeSeconds: Double
    public let source: InputSource
    public var reserve: Int?
    public var reason: StopReason
    public var repDurations: [Double]? = nil
    public var restSecondsBefore: Double? = nil
}

public struct SessionRecord: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let date: Date
    public let sets: [SetRecord]
    public let telemetry: [WatchTelemetry]
    public let loggedSets: [LoggedSet]
    public init(id: UUID, date: Date, sets: [SetRecord], telemetry: [WatchTelemetry] = [], loggedSets: [LoggedSet] = []) {
        self.id = id; self.date = date; self.sets = sets; self.telemetry = telemetry; self.loggedSets = loggedSets
    }
    private enum CodingKeys: String, CodingKey { case id, date, sets, telemetry, loggedSets }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        date = try values.decode(Date.self, forKey: .date)
        sets = try values.decode([SetRecord].self, forKey: .sets)
        telemetry = try values.decodeIfPresent([WatchTelemetry].self, forKey: .telemetry) ?? []
        loggedSets = try values.decodeIfPresent([LoggedSet].self, forKey: .loggedSets) ?? []
    }
    public var setCount: Int { sets.count + loggedSets.count }
    public var reps: Int { sets.reduce(0) { $0 + $1.reps } + loggedSets.reduce(0) { $0 + $1.reps } }
    public var activeSeconds: Double { sets.reduce(0) { $0 + $1.activeSeconds } + loggedSets.reduce(0) { $0 + ($1.activeSeconds ?? $1.seconds) } }
}

public struct TrainingSession: Sendable {
    public let id = UUID()
    public let date = Date()
    public private(set) var generation = UUID()
    public private(set) var phase: SessionPhase = .idle
    public private(set) var sets: [SetRecord] = []
    public private(set) var telemetry: [WatchTelemetry] = []
    public private(set) var counter = RepCounter(exercise: .squat)
    public private(set) var manualReps: Int?
    public var actualReps: Int? { source == .manual ? manualReps : counter.reps }
    public var exercise: Exercise { counter.exercise }
    public var setNumber: Int { sets.count % 3 + 1 }
    public var cue: Cue = .ready
    private var activeStarted: Double?
    private var accumulated = 0.0
    public private(set) var source: InputSource = .camera
    private var repDurations: [Double] = []
    private var currentRestBefore: Double?
    private var restStartedAt: Double?
    private let firstExercise: Exercise
    public init(firstExercise: Exercise = .squat) {
        self.firstExercise = firstExercise
        counter = RepCounter(exercise: firstExercise)
    }
    public var record: SessionRecord { .init(id: id, date: date, sets: sets, telemetry: telemetry) }
    public mutating func receiveTelemetry(_ sample: WatchTelemetry, now: Date = Date()) {
        guard [.active, .paused, .rest].contains(phase), sample.sessionID == id else { return }
        let age = now.timeIntervalSince(sample.sentAt)
        guard age >= -2, age <= 12, sample.sentAt > (telemetry.last?.sentAt ?? .distantPast) else { return }
        let readings = [sample.heartRate, sample.accelerationG, sample.rotationRadiansPerSecond].compactMap { $0 }
        guard readings.allSatisfy({ $0.value.isFinite && $0.value >= 0 && $0.date.timeIntervalSince1970.isFinite }) else { return }
        telemetry = Array((telemetry + [sample]).suffix(7200))
    }
    public mutating func feedback(reserve: Int?, reason: StopReason) {
        guard phase == .rest, !sets.isEmpty else { return }
        sets[sets.count - 1].reserve = reserve.flatMap { (0...3).contains($0) ? $0 : nil }
        sets[sets.count - 1].reason = reason
    }
    public mutating func nextSet(at time: Double) {
        guard phase == .rest, time.isFinite else { return }
        guard sets.count < 6, sets.last?.reason != .discomfort else { phase = .finished; return }
        currentRestBefore = restStartedAt.map { max(0, time - $0) }
        restStartedAt = nil
        counter = RepCounter(exercise: sets.count < 3 ? firstExercise : (firstExercise == .squat ? .pushup : .squat))
        accumulated = 0; activeStarted = time; phase = .active; generation = UUID(); cue = .ready
        source = .camera; repDurations = []; manualReps = nil
    }
    public mutating func finish(at time: Double) {
        if phase == .active || phase == .paused { endSet(at: time) }
        phase = .finished; generation = UUID(); activeStarted = nil
    }
    public mutating func restartSet(source: InputSource, at time: Double) {
        guard phase == .active || phase == .paused else { return }
        self.source = source; counter = RepCounter(exercise: exercise); repDurations = []; manualReps = nil
        accumulated = 0; activeStarted = time; phase = .active; generation = UUID(); cue = .ready
    }
    public func elapsed(at time: Double) -> Double { accumulated + max(0, time - (activeStarted ?? time)) }
    public mutating func start(at time: Double) {
        guard phase == .idle else { return }
        phase = .active; activeStarted = time
    }
    public mutating func setManualReps(_ value: Int?) {
        guard source == .manual, phase == .active || phase == .paused else { return }
        manualReps = value.flatMap { (1...200).contains($0) ? $0 : nil }
    }
    public mutating func consume(_ sample: MovementSample, generation: UUID) {
        guard source != .manual, phase == .active, generation == self.generation else { return }
        let previousReps = counter.reps
        let movementCue = counter.consume(sample)
        if counter.reps > previousReps, let duration = counter.lastRepDuration { repDurations.append(duration) }
        cue = movementCue != .tracking && sample.bodyLine == .adjust ? .alignment : movementCue
    }
    public mutating func pause(at time: Double) {
        guard phase == .active else { return }
        accumulated = elapsed(at: time); activeStarted = nil
        phase = .paused; generation = UUID(); counter.resetMovement(); cue = .paused
    }
    public mutating func resume(at time: Double) {
        guard phase == .paused else { return }
        phase = .active; activeStarted = time; generation = UUID(); cue = .ready
    }
    public mutating func endSet(at time: Double, reason: StopReason = .voluntary) {
        guard time.isFinite, phase == .active || phase == .paused, let reps = actualReps else { return }
        sets.append(.init(id: UUID(), exercise: exercise, number: setNumber, reps: reps,
                          target: exercise.target, activeSeconds: elapsed(at: time), source: source, reason: reason,
                          repDurations: source == .manual ? nil : repDurations, restSecondsBefore: currentRestBefore))
        restStartedAt = time
        phase = .rest; activeStarted = nil; accumulated = 0; generation = UUID(); cue = .ready
    }
}

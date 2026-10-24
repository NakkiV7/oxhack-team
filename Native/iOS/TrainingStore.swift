import SwiftUI

struct CoachingEvent: Identifiable, Equatable {
    let id = UUID()
    let sessionID: UUID
    let generation: UUID
    let decision: CoachingDecision
    let issuedAt: Double
    let expiresAt: Double?
}

@MainActor @Observable
final class TrainingStore {
    var session = TrainingSession()
    private(set) var configured: ConfigurableSession?
    var sessionPhase: SessionPhase { configured?.phase ?? session.phase }
    var presented = false
    var history: [SessionRecord] = []
    var error: String?
    var visionState: VisionState = .idle
    var frame: PoseFrame?
    var image: UIImage?
    var source: InputSource = .camera
    var hasInput = false
    var selectedExercise: Exercise = .squat
    let vision = VisionWorker()
    let secondaryVision: SecondaryCameraVisionWorker
    private(set) var usingSecondaryCamera = false
    private let secondaryCameraClient: @MainActor () throws -> SecondaryCameraClient
    let companion = CompanionLink()
    var watchReachable = false
    private(set) var reportedDiscomfort = false
    private let historyStore: HistoryStore
    private var preferredSide: Int?
    private var coachingPolicy = CoachingPolicy()
    private var activeCoachingEvent: CoachingEvent?
    private var restGeneration: UUID?
    private var restStartedAt: Double?

    var coachingEvent: CoachingEvent? {
        guard let event = activeCoachingEvent,
              event.sessionID == session.id, event.generation == session.generation,
              session.phase == .active || session.phase == .rest else { return nil }
        return event
    }

    func cancelCoaching() { activeCoachingEvent = nil }

    func actualRestElapsed(at time: Double? = nil) -> Double? {
        let time = time ?? now
        guard time.isFinite, session.phase == .rest, restGeneration == session.generation,
              let restStartedAt else { return nil }
        return max(0, time - restStartedAt)
    }

    func coachingTick(at time: Double? = nil, wallTime: Date = Date()) {
        guard configured == nil else { return }
        let time = time ?? now
        guard time.isFinite else { return }
        if coachingEvent == nil || activeCoachingEvent?.expiresAt.map({ time >= $0 }) == true {
            activeCoachingEvent = nil
        }
        if let event = coachingEvent, event.decision.priority == .form,
           (event.decision.reason == .alignment && session.cue != .alignment)
            || (event.decision.reason == .tracking && session.cue != .tracking) {
            activeCoachingEvent = nil
        }
        guard let decision = coachingPolicy.evaluate(.init(
            sessionID: session.id, generation: session.generation, phase: session.phase,
            now: time, exercise: session.exercise, repCount: session.counter.reps,
            lastRepDuration: session.counter.lastRepDuration, cue: session.cue,
            heartRate: recentHeartRate(at: wallTime), wallTime: wallTime,
            restElapsed: actualRestElapsed(at: time),
            target: session.exercise.target, stopReason: session.phase == .rest ? session.sets.last?.reason : nil, source: source
        )) else { return }
        activeCoachingEvent = CoachingEvent(sessionID: session.id, generation: session.generation,
                                           decision: decision, issuedAt: time,
                                           expiresAt: decision.priority == .stop ? nil : time + 6)
    }

    private func recentHeartRate(at date: Date) -> [SensorReading] {
        let readings = session.telemetry.suffix(120).compactMap(\.heartRate).filter {
            let age = date.timeIntervalSince($0.date)
            return $0.value.isFinite && (1...300).contains($0.value) && age >= -2 && age <= 30
        }
        let distinct = readings.reduce(into: [Date: SensorReading]()) { $0[$1.date] = $1 }
        return Array(distinct.values.sorted { $0.date < $1.date }.suffix(60))
    }

    init(historyURL: URL? = nil, secondaryVision: SecondaryCameraVisionWorker? = nil,
         secondaryCameraClient: @escaping @MainActor () throws -> SecondaryCameraClient = { try SecondaryCameraSettings.client() }) {
        self.secondaryVision = secondaryVision ?? SecondaryCameraVisionWorker()
        self.secondaryCameraClient = secondaryCameraClient
        let root = URL.applicationSupportDirectory.appendingPathComponent("Spottr")
        let namespace = ProcessInfo.processInfo.environment["SPOTTR_DATA_NAMESPACE"].flatMap(UUID.init(uuidString:))
        let folder = namespace.map { root.appendingPathComponent($0.uuidString) } ?? root
        historyStore = HistoryStore(url: historyURL ?? folder.appendingPathComponent("history.json"))
        do { history = try historyStore.load().reversed() }
        catch { self.error = "Couldn’t read your saved sessions." }
        vision.onFrame = { [weak self] frame, image, generation in
            Task { @MainActor in
                guard let self, !self.usingSecondaryCamera else { return }
                self.receive(frame, image: image, generation: generation)
            }
        }
        vision.onState = { [weak self] state, generation in
            Task { @MainActor in
                guard let self, !self.usingSecondaryCamera, self.configured == nil, self.session.generation == generation, self.session.phase == .active else { return }
                self.visionState = state
                if case .finished = state { self.pause() }
                if case .failed = state { self.pause() }
            }
        }
        self.secondaryVision.onFrame = { [weak self] frame, image, generation in
            guard let self, self.usingSecondaryCamera else { return }
            self.receive(frame, image: image, generation: generation)
        }
        self.secondaryVision.onState = { [weak self] state, generation in
            guard let self, self.usingSecondaryCamera, self.configured == nil,
                  self.session.generation == generation, self.session.phase == .active else { return }
            switch state {
            case .idle: break
            case .starting: self.visionState = .idle
            case .tracking: self.visionState = .camera
            case .failed(let message): self.visionState = .failed(message); self.pause()
            }
        }
        companion.onCommand = { [weak self] command in
            Task { @MainActor in self?.command(command) }
        }
        companion.onTelemetry = { [weak self] telemetry in
            Task { @MainActor in
                guard let self else { return }
                if self.configured != nil { self.configured?.receiveTelemetry(telemetry) }
                else { self.session.receiveTelemetry(telemetry) }
            }
        }
        companion.onReachability = { [weak self] reachable in
            Task { @MainActor in self?.watchReachable = reachable; self?.publish() }
        }
        companion.onRequest = { [weak self] in Task { @MainActor in self?.publish() } }
    }

    func publish() {
        if let configured { companion.publish(CompanionSnapshot(session: configured, at: now)) }
        else { companion.publish(CompanionSnapshot(session: session)) }
    }
    private func command(_ command: CompanionCommand) {
        guard command.sessionID == (configured?.id ?? session.id),
              command.generation == (configured?.generation ?? session.generation) else { publish(); return }
        switch command.action {
        case .startSet: beginConfiguredSet()
        case .pause: pause()
        case .resume: resume()
        case .endSet: endSet()
        case .nextSet: next()
        case .finish: finish()
        }
        publish()
    }
    func heartRate(at date: Date) -> String {
        (configured?.telemetry ?? session.telemetry).last?.heartRate?.heartRate(at: date).map { "\(Int($0.rounded())) bpm" } ?? "—"
    }

    var now: Double { ProcessInfo.processInfo.systemUptime }
    func start() {
        defer { publish() }
        configured = nil
        vision.stop(); secondaryVision.stop(); session = TrainingSession(firstExercise: selectedExercise)
        coachingPolicy = CoachingPolicy(history: history)
        reportedDiscomfort = false
        session.start(at: now); presented = true; error = nil; clearInput()
    }
    func startPlan(_ plan: CoachSavedPlan, availableSupport: Set<String>) {
        do {
            var run = try ConfigurableSession(plan: plan, availableSupport: availableSupport)
            run.start(at: now)
            vision.stop(); secondaryVision.stop(); clearInput(); configured = run
            reportedDiscomfort = false; presented = true; error = nil; publish()
        } catch { self.error = "This plan needs valid exercises and its required support selected in Coach before it can start." }
    }
    func beginConfiguredSet() { configured?.beginSet(at: now); publish() }
    func setConfiguredReps(_ reps: Int?) { configured?.setReps(reps); publish() }
    func stopConfiguredForDiscomfort() { configured?.stopForDiscomfort(at: now); cancelCoaching(); publish() }
    func camera() {
        defer { publish() }
        vision.stop(); secondaryVision.stop(); session.restartSet(source: .camera, at: now); clearInput()
        source = .camera; hasInput = true; vision.camera(token: session.generation)
    }
    func secondaryCamera() {
        guard configured == nil, session.phase == .active || session.phase == .paused else { return }
        defer { publish() }
        vision.stop(); secondaryVision.stop()
        session.restartSet(source: .camera, at: now); clearInput()
        usingSecondaryCamera = true; source = .camera; hasInput = true
        startSecondaryCamera()
    }
    private func startSecondaryCamera() {
        do { secondaryVision.start(client: try secondaryCameraClient(), generation: session.generation) }
        catch {
            visionState = .failed("Pair your side camera in Camera settings before starting capture.")
            pause()
        }
    }
    func video(_ url: URL) {
        defer { publish() }
        vision.stop(); secondaryVision.stop(); session.restartSet(source: .video, at: now); clearInput()
        source = .video; hasInput = true; vision.video(url: url, token: session.generation)
    }
    private func receive(_ frame: PoseFrame, image: UIImage, generation: UUID) {
        guard configured == nil, generation == session.generation, session.phase == .active else { return }
        self.frame = frame; self.image = image
        let sample = PoseGeometry.measure(frame, exercise: session.exercise, preferredSide: preferredSide)
        preferredSide = sample?.side
        let previousReps = session.counter.reps, previousCue = session.cue
        session.consume(sample ?? .init(time: frame.time, angle: .nan, confidence: 0), generation: generation)
        if previousReps != session.counter.reps || previousCue != session.cue {
            coachingTick()
            publish()
        }
    }
    func pause() {
        if configured != nil { configured?.pause(at: now); cancelCoaching(); publish(); return }
        session.pause(at: now); vision.pause(); secondaryVision.stop(); frame = nil; image = nil
        cancelCoaching()
        publish()
    }
    func resume() {
        if configured != nil { configured?.resume(at: now); publish(); return }
        guard session.phase == .paused else { return }
        session.resume(at: now)
        if usingSecondaryCamera { startSecondaryCamera() }
        else if hasInput { vision.resume(token: session.generation, source: source) }
        publish()
    }
    func endSet() {
        if let run = configured {
            let quantity = run.current.unit == .reps ? Double(run.manualReps ?? 0) : run.elapsed(at: now)
            configured?.endSet(at: now, reason: quantity >= Double(run.current.target) ? .target : .voluntary)
            cancelCoaching(); publish(); return
        }
        guard session.phase == .active || session.phase == .paused else { return }
        let time = now
        session.endSet(at: time, reason: session.counter.reps >= session.exercise.target ? .target : .voluntary)
        vision.stop(); secondaryVision.stop(); frame = nil; image = nil; restStartedAt = time
        restGeneration = session.generation
        cancelCoaching()
        publish()
    }
    func feedback(reserve: Int?, reason: StopReason) {
        if configured != nil { configured?.feedback(reserve: reserve, reason: reason); publish(); return }
        if session.phase == .rest, reason == .discomfort { reportedDiscomfort = true }
        session.feedback(reserve: reserve, reason: reportedDiscomfort ? .discomfort : reason)
        coachingTick()
    }
    func next() {
        if configured != nil {
            configured?.nextSet(at: now)
            if configured?.phase == .finished { save() }
            publish(); return
        }
        guard !reportedDiscomfort else { publish(); return }
        session.nextSet(at: now); clearInput()
        if session.phase == .finished { save() }
        publish()
    }
    func finish() {
        if configured != nil { configured?.finish(at: now); cancelCoaching(); save(); publish(); return }
        session.finish(at: now); vision.stop(); secondaryVision.stop(); frame = nil; image = nil; cancelCoaching(); save(); publish()
    }
    func save() {
        if let configured {
            guard configured.phase == .finished, !configured.completed.isEmpty else { return }
            persist(configured.record); return
        }
        persist(session.record)
    }
    func persist(_ record: SessionRecord) {
        do {
            try historyStore.save(record); history = try historyStore.load().reversed(); error = nil
        } catch { self.error = "Couldn’t save this session. Try again." }
    }
    func exportHistory() throws -> URL {
        var exportDirectory = historyStore.url.appendingPathExtension("exports")
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try exportDirectory.setResourceValues(resourceValues)
        let destination = exportDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("spottr-history.json")
        try historyStore.export(to: destination)
        return destination
    }
    func clearHistory() throws {
        guard sessionPhase == .idle || sessionPhase == .finished else { throw DataControlError.workoutInProgress }
        try historyStore.clear()
        history = []
        error = nil
        let exportDirectory = historyStore.url.appendingPathExtension("exports")
        if FileManager.default.fileExists(atPath: exportDirectory.path) {
            try FileManager.default.removeItem(at: exportDirectory)
        }
    }
    enum DataControlError: LocalizedError {
        case workoutInProgress
        var errorDescription: String? { "Finish your current workout before deleting training history." }
    }
    private func clearInput() {
        frame = nil; image = nil; preferredSide = nil; hasInput = false; visionState = .idle; source = .camera
        usingSecondaryCamera = false
        cancelCoaching()
    }
}

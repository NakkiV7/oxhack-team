import SwiftUI

@MainActor @Observable
final class TrainingStore {
    var session = TrainingSession()
    var presented = false
    var history: [SessionRecord] = []
    var error: String?
    var visionState: VisionState = .idle
    var frame: PoseFrame?
    var image: UIImage?
    var source: InputSource = .camera
    var hasInput = false
    var restStarted = Date()
    var selectedExercise: Exercise = .squat
    let vision = VisionWorker()
    let companion = CompanionLink()
    var watchReachable = false
    private let historyStore: HistoryStore
    private var preferredSide: Int?

    init() {
        let root = URL.applicationSupportDirectory.appendingPathComponent("Spottr")
        let namespace = ProcessInfo.processInfo.environment["SPOTTR_DATA_NAMESPACE"].flatMap(UUID.init(uuidString:))
        let folder = namespace.map { root.appendingPathComponent($0.uuidString) } ?? root
        historyStore = HistoryStore(url: folder.appendingPathComponent("history.json"))
        do { history = try historyStore.load().reversed() }
        catch { self.error = "Couldn’t read your saved sessions." }
        vision.onFrame = { [weak self] frame, image, generation in
            Task { @MainActor in self?.receive(frame, image: image, generation: generation) }
        }
        vision.onState = { [weak self] state, generation in
            Task { @MainActor in
                guard let self, self.session.generation == generation, self.session.phase == .active else { return }
                self.visionState = state
                if case .finished = state { self.pause() }
                if case .failed = state { self.pause() }
            }
        }
        companion.onCommand = { [weak self] command in
            Task { @MainActor in self?.command(command) }
        }
        companion.onTelemetry = { [weak self] telemetry in
            Task { @MainActor in self?.session.receiveTelemetry(telemetry) }
        }
        companion.onReachability = { [weak self] reachable in
            Task { @MainActor in self?.watchReachable = reachable; self?.publish() }
        }
        companion.onRequest = { [weak self] in Task { @MainActor in self?.publish() } }
    }

    func publish() { companion.publish(CompanionSnapshot(session: session)) }
    private func command(_ command: CompanionCommand) {
        guard command.sessionID == session.id, command.generation == session.generation else { publish(); return }
        switch command.action {
        case .pause: pause()
        case .resume: resume()
        case .endSet: endSet()
        case .nextSet: next()
        case .finish: finish()
        }
        publish()
    }
    func heartRate(at date: Date) -> String {
        session.telemetry.last?.heartRate?.heartRate(at: date).map { "\(Int($0.rounded())) bpm" } ?? "—"
    }

    var now: Double { ProcessInfo.processInfo.systemUptime }
    func start() {
        defer { publish() }
        vision.stop(); session = TrainingSession(firstExercise: selectedExercise)
        session.start(at: now); presented = true; error = nil; clearInput()
    }
    func camera() {
        defer { publish() }
        vision.stop(); session.restartSet(source: .camera, at: now); clearInput()
        source = .camera; hasInput = true; vision.camera(token: session.generation)
    }
    func video(_ url: URL) {
        defer { publish() }
        vision.stop(); session.restartSet(source: .video, at: now); clearInput()
        source = .video; hasInput = true; vision.video(url: url, token: session.generation)
    }
    private func receive(_ frame: PoseFrame, image: UIImage, generation: UUID) {
        guard generation == session.generation, session.phase == .active else { return }
        self.frame = frame; self.image = image
        let sample = PoseGeometry.measure(frame, exercise: session.exercise, preferredSide: preferredSide)
        preferredSide = sample?.side
        let previousReps = session.counter.reps, previousCue = session.cue
        session.consume(sample ?? .init(time: frame.time, angle: .nan, confidence: 0), generation: generation)
        if previousReps != session.counter.reps || previousCue != session.cue { publish() }
    }
    func pause() {
        session.pause(at: now); vision.pause(); frame = nil
        publish()
    }
    func resume() {
        session.resume(at: now)
        if hasInput { vision.resume(token: session.generation, source: source) }
        publish()
    }
    func endSet() {
        session.endSet(at: now, reason: session.counter.reps >= session.exercise.target ? .target : .voluntary)
        vision.stop(); frame = nil; restStarted = Date()
        publish()
    }
    func next() {
        session.nextSet(at: now); clearInput()
        if session.phase == .finished { save() }
        publish()
    }
    func finish() { session.finish(at: now); vision.stop(); frame = nil; save(); publish() }
    func save() {
        do {
            try historyStore.save(session.record); history = try historyStore.load().reversed(); error = nil
        } catch { self.error = "Couldn’t save this session. Try again." }
    }
    private func clearInput() {
        frame = nil; image = nil; preferredSide = nil; hasInput = false; visionState = .idle
    }
}

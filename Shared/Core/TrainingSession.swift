import Foundation

public enum SessionPhase: String, Codable, Sendable { case idle, active, paused, rest, finished }
public enum InputSource: String, Codable, Sendable { case camera, video }
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
}

public struct SessionRecord: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let date: Date
    public let sets: [SetRecord]
    public var reps: Int { sets.reduce(0) { $0 + $1.reps } }
    public var activeSeconds: Double { sets.reduce(0) { $0 + $1.activeSeconds } }
}

public struct TrainingSession: Sendable {
    public let id = UUID()
    public let date = Date()
    public private(set) var generation = UUID()
    public private(set) var phase: SessionPhase = .idle
    public private(set) var sets: [SetRecord] = []
    public private(set) var counter = RepCounter(exercise: .squat)
    public var exercise: Exercise { counter.exercise }
    public var setNumber: Int { sets.count % 3 + 1 }
    public var cue: Cue = .ready
    private var activeStarted: Double?
    private var accumulated = 0.0
    private var source: InputSource = .camera
    public init() {}
    public var record: SessionRecord { .init(id: id, date: date, sets: sets) }
    public mutating func feedback(reserve: Int?, reason: StopReason) {
        guard phase == .rest, !sets.isEmpty else { return }
        sets[sets.count - 1].reserve = reserve.flatMap { (0...3).contains($0) ? $0 : nil }
        sets[sets.count - 1].reason = reason
    }
    public mutating func nextSet(at time: Double) {
        guard phase == .rest else { return }
        guard sets.count < 6, sets.last?.reason != .discomfort else { phase = .finished; return }
        counter = RepCounter(exercise: sets.count < 3 ? .squat : .pushup)
        accumulated = 0; activeStarted = time; phase = .active; generation = UUID(); cue = .ready
        source = .camera
    }
    public mutating func finish(at time: Double) {
        if phase == .active || phase == .paused { endSet(at: time) }
        phase = .finished; generation = UUID(); activeStarted = nil
    }
    public mutating func restartSet(source: InputSource, at time: Double) {
        guard phase == .active || phase == .paused else { return }
        self.source = source; counter = RepCounter(exercise: exercise)
        accumulated = 0; activeStarted = time; phase = .active; generation = UUID(); cue = .ready
    }
    public func elapsed(at time: Double) -> Double { accumulated + max(0, time - (activeStarted ?? time)) }
    public mutating func start(at time: Double) {
        guard phase == .idle else { return }
        phase = .active; activeStarted = time
    }
    public mutating func consume(_ sample: MovementSample, generation: UUID) {
        guard phase == .active, generation == self.generation else { return }
        cue = counter.consume(sample)
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
        guard phase == .active || phase == .paused else { return }
        sets.append(.init(id: UUID(), exercise: exercise, number: setNumber, reps: counter.reps,
                          target: exercise.target, activeSeconds: elapsed(at: time), source: source, reason: reason))
        phase = .rest; activeStarted = nil; accumulated = 0; generation = UUID(); cue = .ready
    }
}

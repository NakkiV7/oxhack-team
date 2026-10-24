import Foundation

public struct CompanionState: Sendable {
    public private(set) var snapshot: CompanionSnapshot?
    public init() {}
    public mutating func receive(_ value: CompanionSnapshot, now: Date = Date()) {
        guard value.isFresh(at: now), value.sentAt > (snapshot?.sentAt ?? .distantPast) else { return }
        snapshot = value
    }
    public func command(_ action: CompanionCommand.Action, now: Date = Date()) -> CompanionCommand? {
        guard let snapshot, snapshot.isFresh(at: now) else { return nil }
        let allowed: Bool
        switch action {
        case .startSet: allowed = snapshot.phase == .active && snapshot.configured?.hasStarted == false
        case .pause: allowed = snapshot.phase == .active && (snapshot.configured?.hasStarted ?? true)
        case .resume: allowed = snapshot.phase == .paused
        case .endSet: allowed = (snapshot.phase == .active || snapshot.phase == .paused) && (snapshot.configured?.canEndSet ?? true)
        case .nextSet: allowed = snapshot.phase == .rest && snapshot.configured?.stoppedForDiscomfort != true
        case .finish: allowed = snapshot.phase != .idle && snapshot.phase != .finished
        }
        guard allowed else { return nil }
        return .init(sessionID: snapshot.sessionID, generation: snapshot.generation, action: action)
    }
}

public struct CompanionCommand: Codable, Sendable {
    public enum Action: String, Codable, Sendable { case startSet, pause, resume, endSet, nextSet, finish }
    public let sessionID: UUID
    public let generation: UUID
    public let action: Action
    public init(sessionID: UUID, generation: UUID, action: Action) {
        self.sessionID = sessionID; self.generation = generation; self.action = action
    }
}

public struct ConfiguredCompanionSnapshot: Codable, Sendable {
    public let exerciseID: String
    public let unit: ExerciseEntry.Unit
    public let totalSets: Int
    public let stepIndex: Int
    public let totalSteps: Int
    public let enteredReps: Int?
    public let activeSeconds: Double
    public let restElapsed: Double?
    public let restTarget: Int
    public let hasStarted: Bool
    public let canEndSet: Bool
    public let stoppedForDiscomfort: Bool
    public let source: InputSource?
}

public struct CompanionSnapshot: Codable, Sendable {
    public let sessionID: UUID
    public let generation: UUID
    public let exercise: Exercise?
    public let phase: SessionPhase
    public let reps: Int
    public let target: Int
    public let setNumber: Int
    public let cue: Cue
    public let sentAt: Date
    public let configured: ConfiguredCompanionSnapshot?
    public init(session: TrainingSession, sentAt: Date = Date()) {
        sessionID = session.id; generation = session.generation; exercise = session.exercise
        phase = session.phase; reps = session.counter.reps; target = session.exercise.target
        setNumber = session.setNumber; cue = session.cue; self.sentAt = sentAt
        configured = nil
    }
    public init(session: ConfigurableSession, at time: Double, sentAt: Date = Date()) {
        let ended = session.completed.last.flatMap {
            $0.exerciseID == session.current.exerciseID && $0.number == session.current.number ? $0 : nil
        }
        let activeSeconds = session.phase == .rest || session.phase == .finished
            ? (ended?.activeSeconds ?? ended?.seconds ?? 0) : session.elapsed(at: time)
        sessionID = session.id; generation = session.generation; exercise = nil
        phase = session.phase; reps = session.actualReps ?? 0; target = session.current.target
        setNumber = session.current.number; cue = session.cue
        self.sentAt = sentAt
        configured = .init(exerciseID: session.current.exerciseID, unit: session.current.unit,
            totalSets: session.current.totalSets, stepIndex: session.index + 1, totalSteps: session.steps.count,
            enteredReps: session.manualReps, activeSeconds: activeSeconds,
            restElapsed: session.restElapsed(at: time), restTarget: session.current.restSeconds,
            hasStarted: session.hasStarted, canEndSet: session.canEndSet(at: time),
            stoppedForDiscomfort: session.stoppedForDiscomfort, source: session.source)
    }
    public func isFresh(at now: Date) -> Bool {
        let age = now.timeIntervalSince(sentAt)
        guard age >= -5, age <= 10, reps >= 0, (1...1000).contains(target) else { return false }
        guard let configured else { return exercise != nil && (1...3).contains(setNumber) }
        guard configured.source != .video else { return false }
        if configured.source == .camera {
            guard Exercise(rawValue: configured.exerciseID) != nil, configured.unit == .reps,
                  configured.enteredReps == nil else { return false }
        }
        return ExerciseCatalog.find(configured.exerciseID)?.unit == configured.unit
            && (1...10).contains(configured.totalSets) && (1...configured.totalSets).contains(setNumber)
            && (1...120).contains(configured.totalSteps) && (1...configured.totalSteps).contains(configured.stepIndex)
            && configured.activeSeconds.isFinite && (0...86400).contains(configured.activeSeconds)
            && (configured.restElapsed.map { $0.isFinite && $0 >= 0 && $0 < Double(Int.max) } ?? true)
    }
}

extension TrainingSession {
    public mutating func apply(_ command: CompanionCommand, at time: Double) {
        guard command.sessionID == id, command.generation == generation else { return }
        switch command.action {
        case .startSet: break
        case .pause: pause(at: time)
        case .resume: resume(at: time)
        case .endSet: endSet(at: time)
        case .nextSet: nextSet(at: time)
        case .finish: finish(at: time)
        }
    }
}

import Foundation

public struct CompanionCommand: Codable, Sendable {
    public enum Action: String, Codable, Sendable { case pause, resume, endSet, nextSet, finish }
    public let sessionID: UUID
    public let generation: UUID
    public let action: Action
    public init(sessionID: UUID, generation: UUID, action: Action) {
        self.sessionID = sessionID; self.generation = generation; self.action = action
    }
}

public struct CompanionSnapshot: Codable, Sendable {
    public let sessionID: UUID
    public let generation: UUID
    public let exercise: Exercise
    public let phase: SessionPhase
    public let reps: Int
    public let target: Int
    public let setNumber: Int
    public let cue: Cue
    public let sentAt: Date
    public init(session: TrainingSession, sentAt: Date = Date()) {
        sessionID = session.id; generation = session.generation; exercise = session.exercise
        phase = session.phase; reps = session.counter.reps; target = session.exercise.target
        setNumber = session.setNumber; cue = session.cue; self.sentAt = sentAt
    }
    public func isFresh(at now: Date) -> Bool {
        let age = now.timeIntervalSince(sentAt)
        return age >= -5 && age <= 10 && reps >= 0 && (1...1000).contains(target) && (1...3).contains(setNumber)
    }
}

extension TrainingSession {
    public mutating func apply(_ command: CompanionCommand, at time: Double) {
        guard command.sessionID == id, command.generation == generation else { return }
        switch command.action {
        case .pause: pause(at: time)
        case .resume: resume(at: time)
        case .endSet: endSet(at: time)
        case .nextSet: nextSet(at: time)
        case .finish: finish(at: time)
        }
    }
}

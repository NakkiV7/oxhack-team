import Foundation

public enum CoachingPriority: String, Sendable, Equatable { case stop, form, pacing, rest }
public enum CoachingReason: String, Sendable, Equatable { case discomfort, tracking, alignment, slowerRep, targetReached, restReminder, steadyRhythm }

public struct CoachingInput: Sendable, Equatable {
    public let sessionID: UUID
    public let generation: UUID
    public let phase: SessionPhase
    public let now: Double
    public let exercise: Exercise
    public let repCount: Int
    public let lastRepDuration: Double?
    public let cue: Cue
    public let heartRate: [SensorReading]
    public let wallTime: Date
    public let restElapsed: Double?
    public let target: Int
    public let stopReason: StopReason?
    public let source: InputSource
    public let encouragementEnabled: Bool

    public init(sessionID: UUID, generation: UUID, phase: SessionPhase, now: Double, exercise: Exercise,
                repCount: Int, lastRepDuration: Double?, cue: Cue, heartRate: [SensorReading], wallTime: Date,
                restElapsed: Double?, target: Int, stopReason: StopReason?, source: InputSource = .camera, encouragementEnabled: Bool = false) {
        self.sessionID = sessionID; self.generation = generation; self.phase = phase; self.now = now
        self.exercise = exercise; self.repCount = repCount; self.lastRepDuration = lastRepDuration
        self.cue = cue; self.heartRate = heartRate; self.wallTime = wallTime
        self.restElapsed = restElapsed; self.target = target; self.stopReason = stopReason; self.source = source
        self.encouragementEnabled = encouragementEnabled
    }
}

public struct CoachingDecision: Sendable, Equatable {
    public let text: String
    public let priority: CoachingPriority
    public let reason: CoachingReason
    public let facts: [String]
    public let elapsed: Double?

    public static let discomfort = CoachingDecision(
        text: "Stop here. Do not continue through pain or discomfort.", priority: .stop,
        reason: .discomfort, facts: ["Pain or discomfort reported."], elapsed: nil)
}

public struct CoachingPolicy: Sendable {
    private var sessionID: UUID?
    private var generation: UUID?
    private var retiredSessions = Set<UUID>()
    private var retiredGenerations = Set<UUID>()
    private var previousPhase: SessionPhase?
    private var previousExercise: Exercise?
    private var lastInputAt: Double?
    private var stopped = false
    private var lastFormCue: Cue?
    private var repHighWater = 0
    private var rhythmRepHighWater = 0
    private var rhythmBaseline: [Exercise: [Double]] = [:]
    private let seedBaseline: [Exercise: [Double]]
    private var repBaseline: [Exercise: [Double]] = [:]
    private var lastOrdinaryAt: Double?
    private var targetHandled = false
    private var restReminderSent = false
    private var lastEvaluationAt: Double?

    public init(history: [SessionRecord] = []) {
        var sessions = Set<UUID>()
        var sets = Set<UUID>()
        let uniqueSets = history.sorted { $0.date > $1.date }
            .filter { sessions.insert($0.id).inserted }
            .map { WorkoutReport(record: $0).sets.filter { sets.insert($0.id).inserted } }
            .reversed().flatMap { $0 }
        seedBaseline = uniqueSets.reduce(into: [Exercise: [Double]]()) { baseline, set in
            guard set.source == .camera, set.reason != .discomfort, set.reason != .form,
                  set.reps > 0, let exercise = Exercise(rawValue: set.exerciseID),
                  !set.repDurations.isEmpty, set.repDurations.count == set.reps,
                  set.repDurations.count <= 200 else { return }
            let durations = set.repDurations
            guard durations.allSatisfy({ $0.isFinite && (0.6...15).contains($0) }) else { return }
            baseline[exercise] = Array(((baseline[exercise] ?? []) + durations).suffix(60))
        }
        repBaseline = seedBaseline
        rhythmBaseline = seedBaseline
    }
    public mutating func evaluate(_ input: CoachingInput) -> CoachingDecision? {
        let resumingFromPause = previousPhase == .paused && sessionID == input.sessionID
        guard acceptContext(input), !stopped else { return nil }
        if input.stopReason == .discomfort {
            stopped = true
            return .discomfort
        }
        let isFreshRhythmRep = !resumingFromPause && input.repCount > rhythmRepHighWater && input.repCount - rhythmRepHighWater == 1
        rhythmRepHighWater = max(rhythmRepHighWater, input.repCount)
        guard input.source == .camera else { return nil }
        if input.phase == .rest {
            guard input.now - (lastEvaluationAt ?? -.infinity) >= 1 else { return nil }
            lastEvaluationAt = input.now
            guard let rest = input.restElapsed, rest.isFinite, rest >= 45, !restReminderSent,
                  input.now - (lastOrdinaryAt ?? -.infinity) >= 10 else { return nil }
            restReminderSent = true; lastOrdinaryAt = input.now
            return .init(text: String(format: "%.0f seconds of rest recorded. Start again only when you feel ready.", rest), priority: .rest,
                         reason: .restReminder, facts: [String(format: "%.1f actual rest seconds recorded.", rest)], elapsed: rest)
        }
        guard input.phase == .active else { return nil }
        let prior = repBaseline[input.exercise] ?? []
        let isNewRep = input.repCount > repHighWater
        if isNewRep { repHighWater = input.repCount }
        let duration = isNewRep ? input.lastRepDuration.flatMap { $0.isFinite && (0.6...15).contains($0) ? $0 : nil } : nil
        let rhythmPrior = rhythmBaseline[input.exercise] ?? []
        if let duration, isFreshRhythmRep, input.cue == .controlled, input.stopReason == nil {
            rhythmBaseline[input.exercise] = Array((rhythmPrior + [duration]).suffix(60))
        }
        if let duration { repBaseline[input.exercise] = Array((prior + [duration]).suffix(60)) }
        if input.cue == .tracking || input.cue == .alignment {
            guard input.cue != lastFormCue else { return nil }
            lastFormCue = input.cue; lastOrdinaryAt = input.now
            return .init(text: input.cue.text, priority: .form,
                         reason: input.cue == .tracking ? .tracking : .alignment,
                         facts: [input.cue == .tracking ? "Camera tracking is incomplete." : "Camera detected a body alignment change."] + Self.heartRateFacts(input), elapsed: nil)
        }
        lastFormCue = nil
        if isNewRep, input.target > 0, input.repCount >= input.target, !targetHandled {
            targetHandled = true
            guard input.now - (lastOrdinaryAt ?? -.infinity) >= 10 else { return nil }
            lastOrdinaryAt = input.now
            return .init(text: "You reached your planned target. You can end the set here.", priority: .pacing,
                         reason: .targetReached, facts: ["\(input.repCount) reps recorded; planned target \(input.target)."], elapsed: nil)
        }
        guard let duration, prior.count >= 5, input.now - (lastOrdinaryAt ?? -.infinity) >= 10 else { return nil }
        let (mean, deviation) = Self.rhythmStatistics(prior)
        if duration > mean + max(deviation, 0.25) {
            lastOrdinaryAt = input.now
            return .init(text: "That rep took longer than your recent rhythm. Keep control; pause or end the set if you need to.",
                         priority: .pacing, reason: .slowerRep,
                         facts: [String(format: "Rep %.2f seconds; %d prior reps: mean %.2f seconds, sample SD %.2f seconds.", duration, prior.count, mean, deviation)] + Self.heartRateFacts(input), elapsed: duration)
        }
        guard input.encouragementEnabled, isFreshRhythmRep, input.cue == .controlled, input.stopReason == nil,
              input.target > 0, input.repCount < input.target, rhythmPrior.count >= 5 else { return nil }
        let (rhythmMean, rhythmDeviation) = Self.rhythmStatistics(rhythmPrior)
        guard abs(duration - rhythmMean) <= max(rhythmDeviation, 0.25) else { return nil }
        lastOrdinaryAt = input.now
        return .init(text: "Keep a steady rhythm.", priority: .pacing, reason: .steadyRhythm,
                     facts: [String(format: "Rep %.2f seconds; %d prior reps: mean %.2f seconds, sample SD %.2f seconds.", duration, rhythmPrior.count, rhythmMean, rhythmDeviation)], elapsed: duration)
    }
    private static func rhythmStatistics(_ durations: [Double]) -> (Double, Double) {
        let mean = durations.reduce(0, +) / Double(durations.count)
        let deviation = sqrt(durations.reduce(0) { $0 + pow($1 - mean, 2) } / Double(durations.count - 1))
        return (mean, deviation)
    }
    private static func heartRateFacts(_ input: CoachingInput) -> [String] {
        let valid = input.heartRate.filter {
            let age = input.wallTime.timeIntervalSince($0.date)
            return $0.value.isFinite && (1...300).contains($0.value) && age >= -2 && age <= 30
        }
        let unique = valid.reduce(into: [Date: SensorReading]()) { $0[$1.date] = $1 }
        let readings = unique.values.sorted { $0.date < $1.date }
        guard let latest = readings.last, let current = latest.heartRate(at: input.wallTime) else { return [] }
        let currentFact = String(format: "Watch observed %.0f bpm.", current)
        guard readings.count >= 5 else { return [currentFact] }
        let mean = readings.reduce(0) { $0 + $1.value } / Double(readings.count)
        let deviation = sqrt(readings.reduce(0) { $0 + pow($1.value - mean, 2) } / Double(readings.count - 1))
        return [currentFact, String(format: "Watch last 30 seconds: %d unique observations, mean %.2f bpm, sample SD %.2f bpm.", readings.count, mean, deviation)]
    }

    private mutating func acceptContext(_ input: CoachingInput) -> Bool {
        guard input.now.isFinite, input.repCount >= 0, !retiredSessions.contains(input.sessionID) else { return false }
        if sessionID != input.sessionID {
            if let sessionID { retiredSessions.insert(sessionID) }
            sessionID = input.sessionID; generation = nil; retiredGenerations = []
            repBaseline = seedBaseline; rhythmBaseline = seedBaseline
            repHighWater = 0; rhythmRepHighWater = 0; stopped = false; targetHandled = false
            previousPhase = nil; previousExercise = nil
        }
        guard !retiredGenerations.contains(input.generation) else { return false }
        if generation != input.generation {
            if let generation { retiredGenerations.insert(generation) }
            if previousPhase == .rest || input.repCount < repHighWater || previousExercise != input.exercise {
                repHighWater = 0; rhythmRepHighWater = 0; targetHandled = false
            }
            generation = input.generation; lastInputAt = nil; lastEvaluationAt = nil
            lastOrdinaryAt = nil; lastFormCue = nil; restReminderSent = false
        }
        guard input.now >= (lastInputAt ?? -.infinity) else { return false }
        lastInputAt = input.now; previousPhase = input.phase; previousExercise = input.exercise
        return true
    }

}

import Foundation

/// Phase timing of the rep just counted: from leaving the top to the deepest point, then back to the top.
public struct RepPhases: Equatable, Sendable {
    public let lowering: Double
    public let rising: Double
    /// The smallest joint angle reached, in degrees.
    public let minimumAngle: Double
}

public struct RepCounter: Sendable {
    public let exercise: Exercise
    public private(set) var reps = 0
    public private(set) var lastRepDuration: Double?
    /// Phases of the last counted rep, when the descent was observed from the top. Counting never depends on it.
    public private(set) var lastRepPhases: RepPhases?
    private var descentStartedAt: Double?
    private var deepest: (angle: Double, time: Double)?
    private var armedAt: Double?
    private var reachedBottom = false
    private var firstBottomAt: Double?
    private var bottomHoldStartedAt: Double?
    private var candidateAt: Double?
    private var candidate = 0
    private var lastTime: Double?
    private var lastReliableTime: Double?
    private var side: Int?
    private var interruptedPhases = false
    private var continuityWindow: Double { exercise.isSquat ? 2 : 1.5 }
    /// Hold the observed leg through a short squat occlusion; never combine two legs into one movement.
    public func continuitySide(at time: Double) -> Int? {
        guard exercise.isSquat, armedAt != nil, time.isFinite, let lastReliableTime,
              time >= (lastTime ?? lastReliableTime), time - lastReliableTime <= continuityWindow else { return nil }
        return side
    }
    public init(exercise: Exercise, initialReps: Int = 0) { self.exercise = exercise; reps = max(0, min(200, initialReps)) }
    public mutating func resetMovement() {
        armedAt = nil; reachedBottom = false; candidateAt = nil; candidate = 0
        lastTime = nil; lastReliableTime = nil; side = nil
        descentStartedAt = nil; deepest = nil
        firstBottomAt = nil; bottomHoldStartedAt = nil
        interruptedPhases = false
    }
    public mutating func consume(_ sample: MovementSample) -> Cue {
        guard sample.time.isFinite else { resetMovement(); return .tracking }
        let previousTime = lastTime
        defer { lastTime = sample.time }
        if let previousTime, sample.time == previousTime { return .tracking }
        if let previousTime, sample.time < previousTime { resetMovement(); return .tracking }
        guard sample.confidence.isFinite else { resetMovement(); return .tracking }
        guard sample.confidence >= 0.6 else {
            if exercise.requiresContinuousTiming { resetMovement(); return .tracking }
            interruptedPhases = true
            if !exercise.isSquat || candidate != -1 { candidate = 0; candidateAt = nil }
            if lastReliableTime.map({ sample.time - $0 > continuityWindow }) ?? true { resetMovement() }
            return .tracking
        }
        guard sample.angle.isFinite, (0...180).contains(sample.angle) else {
            resetMovement(); return .tracking
        }
        if let lastReliableTime, sample.time - lastReliableTime > continuityWindow { resetMovement() }
        else if let previousTime, sample.time - previousTime > 0.75 {
            if exercise.requiresContinuousTiming { resetMovement() }
            interruptedPhases = true
            if !exercise.isSquat || candidate != -1 { candidate = 0; candidateAt = nil }
        }
        if let side, side != sample.side { resetMovement() }
        guard sample.bodyLine != .reset else { resetMovement(); return .alignment }
        defer { lastReliableTime = sample.time; side = sample.side }
        let zone = sample.angle >= 160 ? 1 : (sample.angle <= exercise.bottomAngle ? -1 : 0)
        if candidate != zone {
            candidate = zone; candidateAt = sample.time
            if armedAt != nil, !reachedBottom { descentStartedAt = zone == 1 ? nil : (descentStartedAt ?? sample.time) }
        }
        if armedAt != nil, zone == -1 {
            firstBottomAt = firstBottomAt ?? sample.time
            bottomHoldStartedAt = bottomHoldStartedAt ?? sample.time
        } else {
            bottomHoldStartedAt = nil
        }
        if descentStartedAt != nil, sample.angle < (deepest?.angle ?? .infinity) { deepest = (sample.angle, sample.time) }
        guard let since = candidateAt, sample.time - since >= 0.15 else { return .lower }
        if zone == -1, armedAt != nil {
            guard sample.time - (bottomHoldStartedAt ?? sample.time) >= exercise.minimumBottomHoldSeconds else { return .hold }
            reachedBottom = true; return .rise
        }
        guard zone == 1 else { return reachedBottom ? .rise : .lower }
        guard let start = armedAt, reachedBottom else {
            armedAt = sample.time; descentStartedAt = nil; deepest = nil; firstBottomAt = nil
            return .lower
        }
        if exercise.minimumLoweringSeconds > 0 {
            guard let began = descentStartedAt, let bottom = firstBottomAt,
                  bottom - began >= exercise.minimumLoweringSeconds else {
                resetMovement(); armedAt = sample.time; return .lower
            }
        }
        guard (0.6...15).contains(sample.time - start) else {
            resetMovement(); armedAt = sample.time; return .lower
        }
        reps += 1; lastRepDuration = sample.time - start
        if !interruptedPhases, let began = descentStartedAt, let deepest, let top = candidateAt, deepest.time > began, top > deepest.time {
            lastRepPhases = RepPhases(lowering: deepest.time - began, rising: top - deepest.time, minimumAngle: deepest.angle)
        } else { lastRepPhases = nil }
        resetMovement(); armedAt = sample.time
        return .controlled
    }
}

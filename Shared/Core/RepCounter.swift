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
    public private(set) var reps: Int
    public private(set) var lastRepDuration: Double?
    public private(set) var lastRepPhases: RepPhases?
    private var limbs: [LimbRepCounter]
    private var lastSampleTime: Double?
    public init(exercise: Exercise, initialReps: Int = 0) {
        self.exercise = exercise; reps = max(0, initialReps)
        limbs = [LimbRepCounter(exercise: exercise), LimbRepCounter(exercise: exercise)]
    }
    public func continuitySide(at time: Double) -> Int? {
        exercise.tracksAlternatingLimbs ? nil : limbs[0].continuitySide(at: time)
    }
    public mutating func resetMovement() {
        limbs[0].resetMovement(); limbs[1].resetMovement(); lastSampleTime = nil
    }
    public mutating func consume(_ sample: MovementSample) -> Cue {
        guard !exercise.isTimed else { return .hold }
        guard sample.time.isFinite else { resetMovement(); return .tracking }
        if sample.time == lastSampleTime { return .tracking }
        if let lastSampleTime, sample.time < lastSampleTime { resetMovement(); return .tracking }
        defer { lastSampleTime = sample.time }
        guard (0...1).contains(sample.side) else { resetMovement(); return .tracking }
        let primaryCue = consumeLimb(sample)
        guard exercise.tracksAlternatingLimbs, let secondary = sample.secondary,
              (0...1).contains(secondary.side), secondary.side != sample.side else { return primaryCue }
        let otherCue = consumeLimb(.init(time: sample.time, angle: secondary.angle, confidence: secondary.confidence,
            side: secondary.side, aligned: secondary.aligned, bodyAngle: secondary.bodyAngle, provenance: secondary.provenance))
        return primaryCue == .controlled || otherCue == .controlled ? .controlled : primaryCue
    }
    private mutating func consumeLimb(_ sample: MovementSample) -> Cue {
        let index = exercise.tracksAlternatingLimbs ? sample.side : 0
        let before = limbs[index].reps
        let cue = limbs[index].consume(sample)
        if limbs[index].reps > before {
            reps += limbs[index].reps - before
            lastRepDuration = limbs[index].lastRepDuration
            lastRepPhases = limbs[index].lastRepPhases
        }
        return cue
    }
}

private struct LimbRepCounter: Sendable {
    public let exercise: Exercise
    public private(set) var reps = 0
    public private(set) var lastRepDuration: Double?
    /// Phases of the last counted rep, when the descent was observed from the top. Counting never depends on it.
    public private(set) var lastRepPhases: RepPhases?
    private var descentStartedAt: Double?
    private var deepest: (angle: Double, time: Double)?
    private var topAngle = 0.0
    private var initialSeatedStart = false
    private var witnessedInitialRise = false
    private var armedAt: Double?
    private var reachedBottom = false
    private var firstBottomAt: Double?
    private var bottomHoldStartedAt: Double?
    private var candidateAt: Double?
    private var candidate = 0
    private var lastTime: Double?
    private var lastReliableTime: Double?
    private var lastReliableAngle: Double?
    private var side: Int?
    private var interruptedPhases = false
    private var provenance: MeasurementProvenance?
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
        lastTime = nil; lastReliableTime = nil; lastReliableAngle = nil; side = nil
        descentStartedAt = nil; deepest = nil; topAngle = 0
        firstBottomAt = nil; bottomHoldStartedAt = nil
        interruptedPhases = false; provenance = nil
        initialSeatedStart = false; witnessedInitialRise = false
    }
    public mutating func consume(_ sample: MovementSample) -> Cue {
        guard sample.time.isFinite else { resetMovement(); return .tracking }
        let previousTime = lastTime
        defer { lastTime = sample.time }
        if let previousTime, sample.time == previousTime { return .tracking }
        if let previousTime, sample.time < previousTime { resetMovement(); return .tracking }
        guard sample.confidence.isFinite else { resetMovement(); return .tracking }
        guard sample.confidence >= 0.6 else {
            if exercise.requiresContinuousTiming || initialSeatedStart || (exercise == .sitToStand && armedAt == nil) {
                resetMovement(); return .tracking
            }
            interruptedPhases = true
            if !exercise.isSquat || candidate != -1 { candidate = 0; candidateAt = nil }
            if lastReliableTime.map({ sample.time - $0 > continuityWindow }) ?? true { resetMovement() }
            return .tracking
        }
        guard sample.angle.isFinite, (0...180).contains(sample.angle) else {
            resetMovement(); return .tracking
        }
        if let lastReliableTime, let lastReliableAngle, sample.time > lastReliableTime,
           abs(sample.angle - lastReliableAngle) / (sample.time - lastReliableTime) > 900 {
            resetMovement(); return .tracking
        }
        if let lastReliableTime, sample.time - lastReliableTime > continuityWindow { resetMovement() }
        else if let previousTime, sample.time - previousTime > 0.75 {
            if exercise.requiresContinuousTiming || initialSeatedStart { resetMovement() }
            interruptedPhases = true
            if !exercise.isSquat || candidate != -1 { candidate = 0; candidateAt = nil }
        }
        if let side, side != sample.side { resetMovement() }
        if let provenance, provenance != sample.provenance { resetMovement() }
        provenance = sample.provenance
        guard sample.bodyLine != .reset else { resetMovement(); return .alignment }
        defer { lastReliableTime = sample.time; lastReliableAngle = sample.angle; side = sample.side }
        let zone = sample.angle >= 160 ? 1 : (sample.angle <= exercise.bottomAngle ? -1 : 0)
        if zone == 1, !reachedBottom { topAngle = max(topAngle,sample.angle) }
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
        if (descentStartedAt != nil || initialSeatedStart), sample.angle < (deepest?.angle ?? .infinity) { deepest = (sample.angle, sample.time) }
        if initialSeatedStart, zone == 0, sample.angle > (deepest?.angle ?? sample.angle) + 8 { witnessedInitialRise = true }
        guard let since = candidateAt, sample.time - since >= (zone == -1 && !exercise.requiresContinuousTiming ? 0.04 : 0.15) else { return .lower }
        if exercise == .sitToStand, armedAt == nil, zone == -1 {
            guard sample.time - since >= 0.15 else { return .hold }
            armedAt = sample.time; reachedBottom = true; initialSeatedStart = true
            deepest = (sample.angle,sample.time)
            return .rise
        }
        if zone == -1, armedAt != nil {
            guard sample.time - (bottomHoldStartedAt ?? sample.time) >= exercise.minimumBottomHoldSeconds else { return .hold }
            reachedBottom = true; return .rise
        }
        guard zone == 1 else { return reachedBottom ? .rise : .lower }
        guard let start = armedAt, reachedBottom else {
            armedAt = sample.time; descentStartedAt = nil; deepest = nil; firstBottomAt = nil
            return .lower
        }
        let observedTop = initialSeatedStart ? sample.angle : topAngle
        guard let lowest = deepest?.angle, observedTop - lowest >= 18,
              !initialSeatedStart || witnessedInitialRise else {
            resetMovement(); armedAt = sample.time; topAngle = sample.angle; return .lower
        }
        if exercise.minimumLoweringSeconds > 0 {
            guard let began = descentStartedAt, let bottom = firstBottomAt,
                  bottom - began >= exercise.minimumLoweringSeconds else {
                resetMovement(); armedAt = sample.time; topAngle = sample.angle; return .lower
            }
        }
        let minimumDuration = initialSeatedStart ? 0.3 : 0.6
        guard (minimumDuration...15).contains(sample.time - start) else {
            resetMovement(); armedAt = sample.time; topAngle = sample.angle; return .lower
        }
        reps += 1; lastRepDuration = initialSeatedStart ? nil : sample.time - start
        if !initialSeatedStart, sample.provenance.isJointAngle, !interruptedPhases, let began = descentStartedAt, let deepest, let top = candidateAt, deepest.time > began, top > deepest.time {
            lastRepPhases = RepPhases(lowering: deepest.time - began, rising: top - deepest.time, minimumAngle: deepest.angle)
        } else { lastRepPhases = nil }
        resetMovement(); armedAt = sample.time; topAngle = sample.angle
        candidate = 1; candidateAt = sample.time
        return .controlled
    }
}

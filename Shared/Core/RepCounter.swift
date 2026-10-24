import Foundation

public struct RepCounter: Sendable {
    public let exercise: Exercise
    public private(set) var reps = 0
    public private(set) var lastRepDuration: Double?
    private var armedAt: Double?
    private var reachedBottom = false
    private var candidateAt: Double?
    private var candidate = 0
    private var lastTime: Double?
    private var side: Int?
    public init(exercise: Exercise) { self.exercise = exercise }
    public mutating func resetMovement() {
        armedAt = nil; reachedBottom = false; candidateAt = nil; candidate = 0
    }
    public mutating func consume(_ sample: MovementSample) -> Cue {
        guard sample.time.isFinite else { resetMovement(); return .tracking }
        guard sample.confidence.isFinite, sample.confidence >= 0.6,
              sample.angle.isFinite, (0...180).contains(sample.angle) else {
            resetMovement(); lastTime = sample.time; return .tracking
        }
        defer { lastTime = sample.time; side = sample.side }
        if let lastTime, sample.time <= lastTime || sample.time - lastTime > 0.75 { resetMovement() }
        if let side, side != sample.side { resetMovement() }
        guard sample.aligned else { resetMovement(); return .alignment }
        let zone = sample.angle >= 160 ? 1 : (sample.angle <= exercise.bottomAngle ? -1 : 0)
        if candidate != zone { candidate = zone; candidateAt = sample.time }
        guard let since = candidateAt, sample.time - since >= 0.15 else { return .lower }
        if zone == -1, armedAt != nil { reachedBottom = true; return .rise }
        guard zone == 1 else { return reachedBottom ? .rise : .lower }
        guard let start = armedAt, reachedBottom else { armedAt = sample.time; return .lower }
        guard (0.6...15).contains(sample.time - start) else {
            resetMovement(); armedAt = sample.time; return .lower
        }
        reps += 1; lastRepDuration = sample.time - start
        resetMovement(); armedAt = sample.time
        return .controlled
    }
}

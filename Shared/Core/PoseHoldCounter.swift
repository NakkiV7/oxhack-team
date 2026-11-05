import Foundation

public struct PoseHoldCounter: Sendable {
    public enum Mode: Sendable { case staticHold, dynamicActivity }
    public let mode: Mode
    public private(set) var observedSeconds: Double
    private var lastTime: Double?
    private var lastQualified = false
    private var lastSide: Int?
    private var activeSide: Int?
    private var lastLiftAt: Double?
    private var alternatingAt: Double?
    public init(exercise: Exercise, initialSeconds: Double = 0) {
        mode = exercise == .highKnees ? .dynamicActivity : .staticHold
        observedSeconds = initialSeconds.isFinite ? max(0, initialSeconds) : 0
    }
    public mutating func resetContinuity() {
        lastTime = nil; lastQualified = false; lastSide = nil
        activeSide = nil; lastLiftAt = nil; alternatingAt = nil
    }
    @discardableResult public mutating func consume(_ sample: MovementSample) -> Cue {
        guard sample.time.isFinite else { resetContinuity(); return .tracking }
        if sample.time == lastTime { return .tracking }
        if let lastTime, sample.time < lastTime { resetContinuity(); return .tracking }
        guard sample.confidence.isFinite, sample.confidence >= 0.6, sample.angle.isFinite,
              sample.aligned, sample.bodyLine != .reset else { resetContinuity(); return .tracking }
        if let lastTime, sample.time - lastTime > 0.25 { resetContinuity() }
        let qualified = qualifies(sample)
        if qualified, lastQualified, let lastTime, mode == .dynamicActivity || lastSide == sample.side {
            observedSeconds += sample.time - lastTime
        }
        lastTime = sample.time; lastQualified = qualified; lastSide = sample.side
        return qualified ? .hold : .ready
    }
    private mutating func qualifies(_ sample: MovementSample) -> Bool {
        guard mode == .dynamicActivity else { return sample.holdQualification == .staticHold }
        switch sample.holdQualification {
        case .activeLimb(let side):
            guard (0...1).contains(side) else { return false }
            if activeSide != side {
                if activeSide != nil, let lastLiftAt, sample.time - lastLiftAt <= 1.2 { alternatingAt = sample.time }
                lastLiftAt = sample.time; activeSide = side
            }
        case .transition: break
        default: activeSide = nil; lastLiftAt = nil; alternatingAt = nil; return false
        }
        return alternatingAt.map { sample.time - $0 <= 0.6 } ?? false
    }
}

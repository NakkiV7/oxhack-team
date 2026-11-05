import Foundation

public struct PosePoint: Sendable {
    public let x: Double
    public let y: Double
    public let confidence: Double
    public init(x: Double, y: Double, confidence: Double) {
        self.x = x; self.y = y; self.confidence = confidence
    }
}

public struct PoseWorldPoint: Sendable {
    public let x: Double
    public let y: Double
    public let z: Double
    public let confidence: Double
    public init(x: Double, y: Double, z: Double, confidence: Double) {
        self.x = x; self.y = y; self.z = z; self.confidence = confidence
    }
}

public enum PoseObservation: String, Sendable, Codable { case singlePerson, notDetected, multiplePeople }

public struct PoseFrame: Sendable {
    public let observation: PoseObservation
    public let time: Double
    public let width: Double
    public let height: Double
    public let points: [PosePoint]
    public let worldPoints: [PoseWorldPoint]?
    public init(time: Double, width: Double, height: Double, points: [PosePoint], worldPoints: [PoseWorldPoint]? = nil, observation: PoseObservation? = nil) {
        self.observation = observation ?? (points.count == 33 ? .singlePerson : .notDetected)
        self.worldPoints = worldPoints
        self.time = time; self.width = width; self.height = height; self.points = points
    }
}

public enum PoseGeometry {
    public static func measure(_ frame: PoseFrame, exercise: Exercise, preferredSide: Int? = nil, allowSideFallback: Bool = true) -> MovementSample? {
        guard frame.time.isFinite, frame.width.isFinite, frame.height.isFinite, frame.width > 0, frame.height > 0 else { return nil }
        if frame.observation == .multiplePeople {
            return MovementSample(time: frame.time, angle: .nan, confidence: 0, observation: .multiplePeople)
        }
        guard frame.observation == .singlePerson, frame.points.count == 33 else { return nil }
        guard preferredSide == nil || (0...1).contains(preferredSide!) else { return nil }
        if !exercise.isSquat && !exercise.isPushup {
            return ProfileGeometry.measure(frame, exercise: exercise, preferredSide: preferredSide, allowSideFallback: allowSideFallback)
        }
        let geometry = ImagePose(frame)
        let sides = allowSideFallback ? [preferredSide ?? 0, (preferredSide ?? 0) == 0 ? 1 : 0] : [preferredSide ?? 0]
        var measurements: [MovementSample] = []
        for side in sides {
            let indices = exercise.isSquat ? [23, 25, 27] : [11, 13, 15, 23]
            var points = indices.map { frame.points[$0 + side] }
            guard points.allSatisfy({ valid($0) }) else { continue }
            let positions = points.map { ($0.x * frame.width, $0.y * frame.height) }
            guard let measurement = geometry.joint(indices[0] + side, indices[1] + side, indices[2] + side) else { continue }
            let angle = measurement.angle
            if exercise.isSquat {
                guard geometry.upright(side), geometry.view(.side,side) else { continue }
                points.append(frame.points[11 + side])
            }
            var aligned = true
            var bodyAngle: Double?
            if !exercise.isSquat {
                let torsoX = abs(positions[0].0 - positions[3].0)
                let torsoY = abs(positions[0].1 - positions[3].1)
                if exercise == .wallPushup {
                    guard torsoY > torsoX else { continue }
                    guard abs(positions[2].0 - positions[0].0) > frame.width * 0.05 else { continue }
                } else if exercise != .inclinePushup {
                    guard torsoX > torsoY else { continue }
                } else {
                    guard torsoX > frame.width * 0.08 else { continue }
                }
                let endpoint = frame.points[(exercise == .kneePushup ? 25 : 27) + side]
                if (exercise == .kneePushup || exercise.requiresContinuousTiming) && !valid(endpoint) { continue }
                if valid(endpoint) {
                    let foot = (endpoint.x * frame.width, endpoint.y * frame.height)
                    if exercise == .wallPushup {
                        guard abs(positions[0].1 - foot.1) > abs(positions[0].0 - foot.0) else { continue }
                    } else if exercise != .inclinePushup {
                        guard abs(positions[0].0 - foot.0) > abs(positions[0].1 - foot.1) else { continue }
                    }
                    guard let measuredBodyAngle = self.angle(positions[0], positions[3], foot) else { continue }
                    points.append(endpoint)
                    bodyAngle = measuredBodyAngle; aligned = measuredBodyAngle >= (exercise == .kneePushup ? 135 : 150)
                }

            }
            let sample = MovementSample(time: frame.time, angle: angle, confidence: points.map(\.confidence).min() ?? 0,
                         side: side, aligned: aligned, bodyAngle: bodyAngle, provenance: measurement.provenance, bodySupport: exercise == .kneePushup ? .knees : .extended)
            if preferredSide != nil { return sample }
            measurements.append(sample)
        }
        return measurements.reduce(nil as MovementSample?) { best, sample in
            guard let best else { return sample }
            return sample.confidence > best.confidence ? sample : best
        }
    }

    private static func valid(_ point: PosePoint) -> Bool {
        point.confidence.isFinite && point.confidence >= 0.6 && point.x.isFinite && point.y.isFinite
        && (0...1).contains(point.x) && (0...1).contains(point.y)
    }

    private static func angle(_ a: (Double, Double), _ b: (Double, Double), _ c: (Double, Double)) -> Double? {
        let u = (a.0 - b.0, a.1 - b.1), v = (c.0 - b.0, c.1 - b.1)
        let denominator = hypot(u.0, u.1) * hypot(v.0, v.1)
        guard denominator > 0.001 else { return nil }
        return acos(max(-1, min(1, (u.0 * v.0 + u.1 * v.1) / denominator))) * 180 / .pi
    }
}

public enum CameraRecoveryState: String, Codable, Sendable {
    case ready, needsResume, waitingForClear
    public var message: String? {
        switch self {
        case .ready: return nil
        case .needsResume: return "Keep one person in view, then tap Resume camera."
        case .waitingForClear: return "Hold your starting position with one person clearly visible for two seconds."
        }
    }
}

struct PoseIdentityRecovery: Sendable {
    var state: CameraRecoveryState { requiresAcknowledgement ? .needsResume : (recovering ? .waitingForClear : .ready) }
    private(set) var requiresAcknowledgement = false
    private var recovering = false
    private var clearSince: Double?
    private var lastClearTime: Double?
    mutating func rejectAmbiguity() {
        requiresAcknowledgement = true; recovering = true; interrupt()
    }
    mutating func acknowledge() {
        guard requiresAcknowledgement else { return }
        requiresAcknowledgement = false; recovering = true; interrupt()
    }
    mutating func interrupt() { clearSince = nil; lastClearTime = nil }
    mutating func accepts(_ sample: MovementSample) -> Bool {
        guard !requiresAcknowledgement else { return false }
        guard recovering else { return true }
        guard sample.observation == .singlePerson, sample.confidence.isFinite, sample.confidence >= 0.6,
              sample.angle.isFinite, sample.bodyLine != .reset else { interrupt(); return false }
        if let lastClearTime {
            if sample.time == lastClearTime { return false }
            if sample.time < lastClearTime || sample.time - lastClearTime > 0.25 { interrupt() }
        }
        clearSince = clearSince ?? sample.time; lastClearTime = sample.time
        guard sample.time - (clearSince ?? sample.time) >= 2 - 1e-9 else { return false }
        recovering = false; interrupt(); return true
    }
}

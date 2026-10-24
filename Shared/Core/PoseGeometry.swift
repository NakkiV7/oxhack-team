import Foundation

public struct PosePoint: Sendable {
    public let x: Double
    public let y: Double
    public let confidence: Double
    public init(x: Double, y: Double, confidence: Double) {
        self.x = x; self.y = y; self.confidence = confidence
    }
}

public struct PoseFrame: Sendable {
    public let time: Double
    public let width: Double
    public let height: Double
    public let points: [PosePoint]
    public init(time: Double, width: Double, height: Double, points: [PosePoint]) {
        self.time = time; self.width = width; self.height = height; self.points = points
    }
}

public enum PoseGeometry {
    public static func measure(_ frame: PoseFrame, exercise: Exercise, preferredSide: Int? = nil) -> MovementSample? {
        guard frame.width.isFinite, frame.height.isFinite, frame.width > 0, frame.height > 0,
              frame.points.count == 33 else { return nil }
        for side in [preferredSide ?? 0, (preferredSide ?? 0) == 0 ? 1 : 0] {
            let indices = exercise == .squat ? [23, 25, 27] : [11, 13, 15, 23, 27]
            let points = indices.map { frame.points[$0 + side] }
            guard points.allSatisfy({ valid($0) }) else { continue }
            let positions = points.map { ($0.x * frame.width, $0.y * frame.height) }
            guard let angle = angle(positions[0], positions[1], positions[2]) else { continue }
            var aligned = true
            if exercise == .pushup {
                guard abs(positions[0].0 - positions[4].0) > abs(positions[0].1 - positions[4].1),
                      let bodyAngle = self.angle(positions[0], positions[3], positions[4]) else { continue }
                aligned = bodyAngle >= 150
            }
            return .init(time: frame.time, angle: angle, confidence: points.map(\.confidence).min() ?? 0,
                         side: side, aligned: aligned)
        }
        return nil
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

import Foundation

public enum Exercise: String, Codable, CaseIterable, Sendable {
    case squat, pushup
    public var title: String { self == .squat ? "Squats" : "Push-ups" }
    public var target: Int { self == .squat ? 12 : 10 }
    public var bottomAngle: Double { self == .squat ? 105 : 100 }
    public var guide: String { self == .squat ? "Sit back. Keep your feet planted." : "Brace your body. Lower with control." }
}

public struct MovementSample: Sendable {
    public let time: Double
    public let angle: Double
    public let confidence: Double
    public let side: Int
    public let aligned: Bool
    public init(time: Double, angle: Double, confidence: Double = 1, side: Int = 0, aligned: Bool = true) {
        self.time = time; self.angle = angle; self.confidence = confidence
        self.side = side; self.aligned = aligned
    }
}

public enum Cue: String, Codable, Sendable {
    case ready, tracking, lower, rise, alignment, controlled, paused
    public var text: String {
        switch self {
        case .ready: return "Get into position. Show your full body."
        case .tracking: return "Step into view. Keep your whole body visible."
        case .lower: return "Lower with control."
        case .rise: return "Drive back up. Stay controlled."
        case .alignment: return "Brace your body. Keep a straight line."
        case .controlled: return "Strong rep. Keep that rhythm."
        case .paused: return "Take a breath. Resume when you're ready."
        }
    }
}

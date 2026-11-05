import Foundation

public enum Exercise: String, Codable, CaseIterable, Sendable {
    case squat, pushup, halfSquat, supportedSquat, wideSquat
    case wallPushup, inclinePushup, kneePushup, closeGripPushup
    case tempoSquat, pausedSquat, tempoPushup, pausedPushup
    public var isSquat: Bool { [.squat, .halfSquat, .supportedSquat, .wideSquat, .tempoSquat, .pausedSquat].contains(self) }
    public var title: String {
        switch self {
        case .squat: return "Squats"
        case .pushup: return "Push-ups"
        case .halfSquat: return "Half squats"
        case .supportedSquat: return "Supported squats"
        case .wideSquat: return "Wide squats"
        case .wallPushup: return "Wall push-ups"
        case .inclinePushup: return "Incline push-ups"
        case .kneePushup: return "Knee push-ups"
        case .closeGripPushup: return "Close-grip push-ups"
        case .tempoSquat: return "Tempo squats"
        case .pausedSquat: return "Paused squats"
        case .tempoPushup: return "Tempo push-ups"
        case .pausedPushup: return "Paused push-ups"
        }
    }
    public var minimumLoweringSeconds: Double { [.tempoSquat, .tempoPushup].contains(self) ? 3 : 0 }
    public var minimumBottomHoldSeconds: Double { [.pausedSquat, .pausedPushup].contains(self) ? 2 : 0 }
    public var requiresContinuousTiming: Bool { minimumLoweringSeconds > 0 || minimumBottomHoldSeconds > 0 }
    public var target: Int { requiresContinuousTiming ? 6 : (isSquat ? 12 : (self == .pushup ? 10 : 8)) }
    public var bottomAngle: Double {
        switch self {
        case .halfSquat, .supportedSquat: return 135
        case .squat, .wideSquat, .tempoSquat, .pausedSquat: return 105
        case .wallPushup, .inclinePushup: return 110
        default: return 100
        }
    }
    public var art: String { requiresContinuousTiming ? "stick-\(rawValue)" : ([.squat, .pushup].contains(self) ? "\(rawValue)-mid" : rawValue) }
    public var guide: String { ExerciseCatalog.find(rawValue)?.instruction ?? "Move at a comfortable pace." }

}

public struct MovementSample: Sendable {
    public enum BodyLine: Sendable { case unknown, steady, adjust, reset }
    public let time: Double
    public let angle: Double
    public let confidence: Double
    public let side: Int
    public let aligned: Bool
    public let bodyAngle: Double?
    public var bodyLine: BodyLine {
        guard aligned else { return .reset }
        guard let bodyAngle, bodyAngle.isFinite else { return .unknown }
        if bodyAngle < 150 { return .reset }
        return bodyAngle < 165 ? .adjust : .steady
    }
    public init(time: Double, angle: Double, confidence: Double = 1, side: Int = 0, aligned: Bool = true, bodyAngle: Double? = nil) {
        self.time = time; self.angle = angle; self.confidence = confidence
        self.side = side; self.aligned = aligned; self.bodyAngle = bodyAngle
    }
}

public enum Cue: String, Codable, Sendable {
    case ready, tracking, lower, hold, rise, alignment, controlled, paused
    public var text: String {
        switch self {
        case .ready: return "Get into position. Show your full body."
        case .tracking: return "Step into view. Keep your whole body visible."
        case .lower: return "Lower with control."
        case .hold: return "Hold at depth. Keep steady."
        case .rise: return "Drive back up. Stay controlled."
        case .alignment: return "Brace your body. Keep a straight line."
        case .controlled: return "Strong rep. Keep that rhythm."
        case .paused: return "Take a breath. Resume when you're ready."
        }
    }
}

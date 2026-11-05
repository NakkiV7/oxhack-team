import Foundation

public enum Exercise: String, Codable, CaseIterable, Sendable {
    case squat, pushup, halfSquat, supportedSquat, wideSquat
    case wallPushup, inclinePushup, kneePushup, closeGripPushup
    case tempoSquat, pausedSquat, tempoPushup, pausedPushup
    case gluteBridge, reverseLunge, splitSquat, assistedSquat, deadBug, plank, sidePlank
    case stepJack, highKnees, mountainClimber, hipFlexorStretch, singleLegBalance
    case widePushup, diamondPushup, wallSit, calfRaise, birdDog, seatedKneeExtension
    case quarterSquat, sitToStand, narrowSquat, tempoHalfSquat, pausedHalfSquat
    case forwardLunge, lateralLunge, supportedSplitSquat, standingKneeRaise, seatedMarch
    case standingHipAbduction, standingHipExtension, kneePlank, highPlank, wallPlank
    case kneeSidePlank, tandemBalance, frontArmRaise, lateralArmRaise, standingBicepsCurl, wallSlide
    public var isSquat: Bool { [.squat, .halfSquat, .supportedSquat, .wideSquat, .tempoSquat, .pausedSquat, .quarterSquat, .sitToStand, .narrowSquat, .tempoHalfSquat, .pausedHalfSquat].contains(self) }
    public var isPushup: Bool { [.pushup, .wallPushup, .inclinePushup, .kneePushup,
        .closeGripPushup, .tempoPushup, .pausedPushup, .widePushup, .diamondPushup].contains(self) }
    public var isTimed: Bool { [.plank, .sidePlank, .wallSit, .singleLegBalance, .hipFlexorStretch,
        .highKnees, .kneePlank, .highPlank, .wallPlank, .kneeSidePlank, .tandemBalance].contains(self) }
    public var tracksAlternatingLimbs: Bool {
        [.reverseLunge, .forwardLunge, .lateralLunge, .assistedSquat, .deadBug, .birdDog,
         .mountainClimber, .stepJack, .standingKneeRaise, .seatedMarch, .standingHipAbduction,
         .standingHipExtension, .seatedKneeExtension, .frontArmRaise, .lateralArmRaise,
         .standingBicepsCurl].contains(self)
    }
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
        default: return ExerciseCatalog.find(rawValue)?.name ?? rawValue
        }
    }
    public var minimumLoweringSeconds: Double { [.tempoSquat, .tempoPushup, .tempoHalfSquat].contains(self) ? 3 : 0 }
    public var minimumBottomHoldSeconds: Double { [.pausedSquat, .pausedPushup, .pausedHalfSquat].contains(self) ? 2 : 0 }
    public var requiresContinuousTiming: Bool { minimumLoweringSeconds > 0 || minimumBottomHoldSeconds > 0 }
    public var target: Int { requiresContinuousTiming ? 6 : (isSquat ? 12 : (self == .pushup ? 10 : 8)) }
    public var bottomAngle: Double {
        switch self {
        case .quarterSquat: return 150
        case .halfSquat, .supportedSquat, .sitToStand, .tempoHalfSquat, .pausedHalfSquat: return 135
        case .squat, .wideSquat, .tempoSquat, .pausedSquat, .narrowSquat: return 105
        case .wallPushup, .inclinePushup: return 110
        default: return 100
        }
    }
    public var art: String { requiresContinuousTiming ? "stick-\(rawValue)" : ([.squat, .pushup].contains(self) ? "\(rawValue)-mid" : rawValue) }
    public var guide: String { ExerciseCatalog.find(rawValue)?.instruction ?? "Move at a comfortable pace." }

}

public enum MeasurementProvenance: String, Sendable, Codable {
    case jointAngle2D, jointAngle3D, normalizedDisplacement, normalizedJointExcursion, posture
    public var isJointAngle: Bool { self == .jointAngle2D || self == .jointAngle3D }
}

public enum HoldQualification: Equatable, Sendable {
    case none, staticHold, transition, activeLimb(Int)
}

public struct MovementLimbSample: Sendable {
    public let angle: Double
    public let confidence: Double
    public let side: Int
    public let aligned: Bool
    public let bodyAngle: Double?
    public let provenance: MeasurementProvenance
    public init(angle: Double, confidence: Double = 1, side: Int, aligned: Bool = true,
                bodyAngle: Double? = nil, provenance: MeasurementProvenance = .jointAngle2D) {
        self.angle = angle; self.confidence = confidence; self.side = side
        self.aligned = aligned; self.bodyAngle = bodyAngle; self.provenance = provenance
    }
}

public struct MovementSample: Sendable {
    public let observation: PoseObservation
    public enum BodySupport: Sendable { case extended, knees }
    public let bodySupport: BodySupport
    public enum BodyLine: Sendable { case unknown, steady, adjust, reset }
    public let time: Double
    public let angle: Double
    public let confidence: Double
    public let side: Int
    public let aligned: Bool
    public let bodyAngle: Double?
    public let provenance: MeasurementProvenance
    public let secondary: MovementLimbSample?
    public let holdQualification: HoldQualification
    public var bodyLine: BodyLine {
        guard aligned else { return .reset }
        guard let bodyAngle, bodyAngle.isFinite else { return .unknown }
        if bodyAngle < (bodySupport == .knees ? 135 : 150) { return .reset }
        return bodyAngle < 165 ? .adjust : .steady
    }
    public init(time: Double, angle: Double, confidence: Double = 1, side: Int = 0, aligned: Bool = true, bodyAngle: Double? = nil,
                provenance: MeasurementProvenance = .jointAngle2D, secondary: MovementLimbSample? = nil,
                holdQualification: HoldQualification = .none, observation: PoseObservation = .singlePerson, bodySupport: BodySupport = .extended) {
        self.provenance = provenance; self.secondary = secondary; self.holdQualification = holdQualification
        self.bodySupport = bodySupport
        self.observation = observation
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

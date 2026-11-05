public enum MovementIllustration {
    public enum Phase: CaseIterable, Hashable, Sendable {
        case standing, lowering, lowered, rising
    }

    public static func assetName(for exercise: Exercise, phase: Phase = .lowering) -> String {
        if [.wallPushup, .inclinePushup, .kneePushup, .closeGripPushup].contains(exercise) {
            return exercise.rawValue
        }
        let family = exercise.isSquat ? "squat" : "pushup"
        let shallow = [.halfSquat, .supportedSquat].contains(exercise)
        switch phase {
        case .standing: return "\(family)-top"
        case .lowering, .rising: return "\(family)-mid"
        case .lowered: return "\(family)-\(shallow ? "mid" : "bottom")"
        }
    }

    public static func nextPhase(after phase: Phase, isActive: Bool, reduceMotion: Bool) -> Phase {
        guard isActive && !reduceMotion else { return phase }
        switch phase {
        case .standing: return .lowering
        case .lowering: return .lowered
        case .lowered: return .rising
        case .rising: return .standing
        }
    }
}

public enum MovementFeedback {
    public static func text(_ cue: Cue, exercise: Exercise) -> String {
        if cue == .alignment { return "Check your starting position. Keep the movement comfortable and controlled." }
        if exercise.isTimed {
            switch cue {
            case .hold, .controlled: return exercise == .highKnees ? "Keep alternating at a comfortable pace." : "Hold comfortably and keep breathing."
            case .lower, .rise: return "Return to the starting position comfortably."
            default: return cue.text
            }
        }
        guard !exercise.isSquat && !exercise.isPushup else { return cue.text }
        switch cue {
        case .lower:
            switch exercise {
            case .standingBicepsCurl: return "Bend the elbow with control."
            case .seatedKneeExtension: return "Straighten the knee comfortably."
            case .deadBug, .birdDog: return "Reach opposite arm and leg."
            case .frontArmRaise, .lateralArmRaise, .standingKneeRaise, .seatedMarch, .gluteBridge, .calfRaise: return "Lift with control."
            case .standingHipAbduction: return "Move the leg out to the side."
            case .standingHipExtension: return "Move the leg back without leaning."
            case .wallSlide: return "Slide both arms upward comfortably."
            case .stepJack: return "Step out and raise the arms."
            case .mountainClimber: return "Bring one knee forward."
            default: return "Lower with control."
            }
        case .rise: return "Return with control."
        case .hold: return "Stay steady at the end of the movement."
        case .controlled: return "Movement recorded. Keep a comfortable rhythm."
        default: return cue.text
        }
    }
}

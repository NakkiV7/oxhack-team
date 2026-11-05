import Testing
@testable import SpottrCore

@Test func movementIllustrationUsesWorkoutFramesWithoutChangingSupportedPoses() {
    #expect(MovementIllustration.assetName(for: .halfSquat, phase: .lowering) == "squat-mid")
    #expect(MovementIllustration.assetName(for: .halfSquat, phase: .lowered) == "squat-mid")
    #expect(MovementIllustration.assetName(for: .squat, phase: .lowered) == "squat-bottom")
    #expect(MovementIllustration.assetName(for: .pushup, phase: .standing) == "pushup-top")
    #expect(MovementIllustration.assetName(for: .tempoPushup, phase: .rising) == "pushup-mid")
    for exercise in [Exercise.wallPushup, .inclinePushup, .kneePushup, .closeGripPushup] {
        #expect(MovementIllustration.assetName(for: exercise, phase: .lowered) == exercise.rawValue)
    }
}

@Test func movementIllustrationStaysStillWhenInactiveOrReduceMotionIsEnabled() {
    for phase in MovementIllustration.Phase.allCases {
        #expect(MovementIllustration.nextPhase(after: phase, isActive: false, reduceMotion: false) == phase)
        #expect(MovementIllustration.nextPhase(after: phase, isActive: true, reduceMotion: true) == phase)
    }
    let phases = MovementIllustration.Phase.allCases
    let advanced = phases.map { MovementIllustration.nextPhase(after: $0, isActive: true, reduceMotion: false) }
    #expect(advanced == [.lowering, .lowered, .rising, .standing])
}

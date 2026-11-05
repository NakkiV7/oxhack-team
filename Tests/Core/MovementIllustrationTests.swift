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

@Test func newMovementFamiliesNeverBorrowSquatOrPushupPictures() {
    for exercise in Exercise.allCases where !exercise.isSquat && !exercise.isPushup {
        #expect(MovementIllustration.assetName(for: exercise) == exercise.rawValue)
    }
}

@Test func vectorGuidesHaveFiniteCompleteBodiesAndStableSupports() {
    for entry in ExerciseCatalog.all {
        for phase in MovementIllustration.Phase.allCases {
            let pose = MovementFigure.pose(for: entry.id, phase: phase)
            #expect(pose.points.count == 11)
            #expect(pose.points.allSatisfy { $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) })
        }
    }
    for id in ["seatedKneeExtension", "seatedMarch", "sitToStand", "wallSlide", "wallPlank", "supportedSplitSquat"] {
        let start = MovementFigure.pose(for: id, phase: .standing)
        #expect(!start.supports.isEmpty)
        #expect(start.supports == MovementFigure.pose(for: id, phase: .lowered).supports)
    }
}

@Test func floorGuideContactsRemainGroundedThroughMovement() {
    // The Canvas floor is y=0.95; rounded body strokes have radius 0.0365.
    let contactY = 0.95 - 0.0365
    for phase in MovementIllustration.Phase.allCases {
        let bridge = MovementFigure.pose(for: "gluteBridge", phase: phase)
        for heel in [8,10] { #expect(abs(bridge.points[heel].y - contactY) < 0.001) }
        let bird = MovementFigure.pose(for: "birdDog", phase: phase)
        for support in [4,9,10] { #expect(abs(bird.points[support].y - contactY) < 0.001) }
    }
    let reach = MovementFigure.pose(for: "birdDog", phase: .lowered)
    #expect(reach.points[6].y < 0.5)
    #expect(reach.points[8].y < 0.6)
}

@Test func plankGuidesShowGroundedSupportsAndExtendedBodyLine() {
    for id in ["plank", "sidePlank", "kneePlank", "kneeSidePlank"] {
        let p = MovementFigure.pose(for: id, phase: .lowered).points
        let end = id.hasPrefix("knee") ? 7 : 8
        for contact in [3,4,end] { #expect(abs(p[contact].y - 0.9135) < 0.001) }
        let fraction = (p[2].x - p[1].x) / (p[end].x - p[1].x)
        let lineY = p[1].y + fraction * (p[end].y - p[1].y)
        #expect(abs(p[2].y - lineY) < 0.025)
    }
}

import Testing
@testable import SpottrCore

@Test func everyCameraVariationHasItsOwnCatalogueIdentity() {
    let ids = ["wallPushup", "inclinePushup", "kneePushup", "closeGripPushup", "halfSquat", "supportedSquat", "wideSquat"]
    for id in ids {
        #expect(ExerciseCatalog.find(id)?.tracking?.rawValue == id)
    }
}

@Test func halfSquatsUseAComfortableDistinctDepth() {
    var half = RepCounter(exercise: .halfSquat)
    var full = RepCounter(exercise: .squat)
    for (t, a) in [(0.0, 170.0), (0.2, 170), (0.6, 145), (1.0, 125), (1.2, 125), (1.8, 170), (2.0, 170)] {
        _ = half.consume(.init(time: t, angle: a)); _ = full.consume(.init(time: t, angle: a))
    }
    #expect(half.reps == 1)
    #expect(full.reps == 0)
}

@Test func wallPushupsAcceptUprightBodyButFloorPushupsRejectIt() {
    var points = Array(repeating: PosePoint(x: 0, y: 0, confidence: 0), count: 33)
    for (i,x,y) in [(11,0.4,0.2),(13,0.6,0.2),(15,0.6,0.4),(23,0.4,0.5),(27,0.4,0.9)] {
        points[i] = .init(x: x, y: y, confidence: 1)
    }
    let frame = PoseFrame(time: 1, width: 1000, height: 1000, points: points)
    #expect(PoseGeometry.measure(frame, exercise: .wallPushup)?.angle == 90)
    #expect(PoseGeometry.measure(frame, exercise: .pushup) == nil)
}

@Test func kneePushupUsesKneeInsteadOfMissingFoot() {
    var points = Array(repeating: PosePoint(x: 0, y: 0, confidence: 0), count: 33)
    for (i,x,y) in [(11,0.1,0.4),(13,0.1,0.6),(15,0.3,0.6),(23,0.5,0.4),(25,0.8,0.4)] {
        points[i] = .init(x: x, y: y, confidence: 1)
    }
    let frame = PoseFrame(time: 1, width: 1000, height: 1000, points: points)
    #expect(PoseGeometry.measure(frame, exercise: .kneePushup)?.bodyLine == .steady)
    points[25] = .init(x: 0.8, y: 0.4, confidence: 0)
    #expect(PoseGeometry.measure(.init(time: 2, width: 1000, height: 1000, points: points), exercise: .kneePushup) == nil)
}

@Test func allVariantsRetainWitnessedDepthAcrossShortOcclusionOnly() {
    for exercise in Exercise.allCases {
        var counter = RepCounter(exercise: exercise)
        for (t,a) in [(0.0,170.0),(0.2,170),(0.6,exercise.bottomAngle),(0.8,exercise.bottomAngle)] {
            _ = counter.consume(.init(time: t, angle: a))
        }
        _ = counter.consume(.init(time: 1, angle: .nan, confidence: 0))
        _ = counter.consume(.init(time: 1.3, angle: 170))
        _ = counter.consume(.init(time: 1.5, angle: 170))
        #expect(counter.reps == (exercise.requiresContinuousTiming ? 0 : 1))
        #expect(counter.lastRepPhases == nil)
    }
}

@Test func reusedPoseProcessorKeepsMonotonicTimestampsAndRealFrameSpacing() {
    var clock = PoseProcessingClock()
    let camera = clock.milliseconds(for: 100)
    let nextCamera = clock.milliseconds(for: 100.1)
    let video = clock.milliseconds(for: 0)
    let nextVideo = clock.milliseconds(for: 0.1)
    #expect(camera == 100000)
    #expect(nextCamera == 100100)
    #expect(video == 100101)
    #expect(nextVideo == 100201)
    let invalid = clock.milliseconds(for: .nan)
    #expect(invalid == nil)
}

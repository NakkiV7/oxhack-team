import Testing
@testable import SpottrCore

@Test func countsOnlyAfterReturningFromBottomToTop() {
    var counter = RepCounter(exercise: .squat)
    for (time, angle) in [(0.0, 170.0), (0.2, 170), (0.6, 130), (1.0, 90), (1.2, 90)] {
        _ = counter.consume(.init(time: time, angle: angle))
    }
    #expect(counter.reps == 0)
    _ = counter.consume(.init(time: 1.8, angle: 170))
    _ = counter.consume(.init(time: 2.0, angle: 170))
    #expect(counter.reps == 1)
    #expect(counter.lastRepDuration == 1.8)
}

@Test(arguments: [0.1, Double.nan, Double.infinity])
func losesIncompleteRepWhenTrackingIsUnreliable(confidence: Double) {
    var counter = loweredCounter()
    _ = counter.consume(.init(time: 1.4, angle: 90, confidence: confidence))
    finish(&counter)
    #expect(counter.reps == 0)
}

private func loweredCounter(_ exercise: Exercise = .pushup) -> RepCounter {
    var counter = RepCounter(exercise: exercise)
    for (t, a) in [(0.0, 170.0), (0.2, 170), (0.6, 130), (1.0, 90), (1.2, 90)] {
        _ = counter.consume(.init(time: t, angle: a))
    }
    return counter
}

private func finish(_ counter: inout RepCounter, at time: Double = 1.8) {
    _ = counter.consume(.init(time: time, angle: 170))
    _ = counter.consume(.init(time: time + 0.2, angle: 170))
}

@Test(arguments: ["gap", "backward", "side", "alignment", "badAngle"])
func rejectsBrokenMovementContinuity(reason: String) {
    var counter = loweredCounter()
    let sample: MovementSample
    switch reason {
    case "gap": sample = .init(time: 3, angle: 90)
    case "backward": sample = .init(time: 0.8, angle: 90)
    case "side": sample = .init(time: 1.4, angle: 90, side: 1)
    case "alignment": sample = .init(time: 1.4, angle: 90, aligned: false)
    default: sample = .init(time: 1.4, angle: .nan)
    }
    _ = counter.consume(sample)
    finish(&counter, at: reason == "gap" ? 3.4 : 1.8)
    #expect(counter.reps == 0)
}

@Test func doesNotCountHalfRepsOrOneFrameAtDepth() {
    var counter = RepCounter(exercise: .squat)
    for (t, a) in [(0.0, 170.0), (0.2, 170), (0.4, 130), (0.6, 170),
                   (0.8, 170), (1.0, 90), (1.1, 130), (1.5, 170), (1.7, 170)] {
        _ = counter.consume(.init(time: t, angle: a))
    }
    #expect(counter.reps == 0)
}

@Test func resetDropsIncompleteRepButPreservesCount() {
    var counter = loweredCounter()
    finish(&counter)
    #expect(counter.reps == 1)
    _ = counter.consume(.init(time: 2.3, angle: 90))
    _ = counter.consume(.init(time: 2.5, angle: 90))
    counter.resetMovement()
    finish(&counter, at: 2.9)
    #expect(counter.reps == 1)
}

@Test func measuresLoweringFromTheLastDepartureFromTheTopToTheDeepestPoint() {
    var counter = RepCounter(exercise: .squat)
    // A shallow dip that returns to the top does not start the clock; the counted rep's descent begins at 1.4 s.
    let samples: [(Double, Double)] = [(0.0, 170), (0.2, 170), (0.5, 140), (0.7, 140), (0.9, 170), (1.1, 170),
                                       (1.4, 130), (1.9, 95), (2.1, 85), (2.3, 92), (2.9, 170), (3.1, 170)]
    for (time, angle) in samples { _ = counter.consume(.init(time: time, angle: angle)) }
    #expect(counter.reps == 1 && counter.lastRepDuration == 2.0)
    let phases = counter.lastRepPhases
    #expect(abs((phases?.lowering ?? 0) - 0.7) < 1e-9 && abs((phases?.rising ?? 0) - 0.8) < 1e-9 && phases?.minimumAngle == 85)
}

@Test func phaseTimingIsClearedWhenTrackingBreaks() {
    var counter = loweredCounter(.squat)
    _ = counter.consume(.init(time: 1.4, angle: 90, confidence: 0.1))
    finish(&counter)
    #expect(counter.reps == 0 && counter.lastRepPhases == nil)
}

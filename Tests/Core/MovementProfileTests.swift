import Foundation
import Testing
@testable import SpottrCore

@Test func movementLibraryPreservesOldUnitsAndProvidesLevelledDedicatedIdentities() {
    #expect(ExerciseCatalog.all.count == 53)
    #expect(Set(ExerciseCatalog.all.map(\.id)).count == 53)
    for entry in ExerciseCatalog.all {
        #expect((1...5).contains(entry.level))
        #expect(entry.goal > 0)
        if entry.id == "catCow" { #expect(entry.tracking == nil) }
        else { #expect(entry.tracking?.rawValue == entry.id) }
    }
    for id in ["plank", "sidePlank", "wallSit", "singleLegBalance", "hipFlexorStretch", "highKnees"] {
        #expect(ExerciseCatalog.find(id)?.unit == .seconds)
    }
}

@Test func clearBriefDepthCountsButInstantTeleportDoesNot() {
    for teleport in [false, true] {
        var counter = RepCounter(exercise: .squat, initialReps: 7)
        let cycle: [(Double, Double)] = teleport
          ? [(0,170),(0.2,170),(0.201,90),(0.4,90),(0.8,170),(1,170)]
          : [(0,170),(0.2,170),(0.5,130),(0.8,90),(0.86,90),(1,130),(1.3,170),(1.5,170)]
        for (t,a) in cycle { _ = counter.consume(.init(time:t, angle:a)) }
        #expect(counter.reps == (teleport ? 7 : 8))
    }
}

@Test func alternatingLimbsKeepIndependentObservedNeutralAndNeverShareHalfCycles() {
    var counter = RepCounter(exercise: .standingKneeRaise, initialReps: 3)
    for side in [0,1] {
        for (t,a) in [(0.0,170.0),(0.2,170),(0.6,130),(1,90),(1.1,90),(1.6,170),(1.8,170)] {
            _ = counter.consume(.init(time: t + Double(side) * 2, angle: a, side: side))
        }
    }
    #expect(counter.reps == 5)
    var interleaved = RepCounter(exercise: .standingKneeRaise)
    for (t,a) in [(0.0,170.0),(0.2,170),(0.6,130),(1,90),(1.1,90),(1.6,170),(1.8,170)] {
        _ = interleaved.consume(.init(time:t, angle:a, side:0, secondary:.init(angle:170,side:1)))
        _ = interleaved.consume(.init(time:t + 0.01, angle:170, side:1, secondary:.init(angle:a,side:0)))
    }
    #expect(interleaved.reps == 1)
    var fused = RepCounter(exercise: .standingKneeRaise)
    for (t,a,s) in [(0.0,170.0,0),(0.2,170,0),(0.6,90,1),(0.8,90,1),(1.2,170,0),(1.4,170,0)] {
        _ = fused.consume(.init(time:t, angle:a, side:s))
    }
    #expect(fused.reps == 0)
}

@Test func savedCountsAboveTwoHundredAreNotClampedByCameraConstruction() {
    var counter = RepCounter(exercise: .squat, initialReps: 317)
    counter.resetMovement()
    #expect(counter.reps == 317)
}

@Test func proxyCyclesNeverPublishJointAnglePhasesAndBothVisibleLimbsCanCount() {
    var counter = RepCounter(exercise: .standingKneeRaise)
    for (t,a) in [(0.0,170.0),(0.2,170),(0.6,130),(1,90),(1.1,90),(1.6,170),(1.8,170)] {
        _ = counter.consume(.init(time:t, angle:a, provenance:.normalizedDisplacement,
            secondary:.init(angle:170, side:1, provenance:.normalizedDisplacement)))
    }
    #expect(counter.reps == 1)
    #expect(counter.lastRepDuration != nil)
    #expect(counter.lastRepPhases == nil)
}

@Test func observedHoldSecondsRequireAdjacentQualifiedFramesAndPreserveSavedQuantity() {
    var hold = PoseHoldCounter(exercise: .plank, initialSeconds: 12)
    for t in [0.0, 0.1, 0.2] { _ = hold.consume(.init(time:t, angle:170, holdQualification:.staticHold)) }
    #expect(abs(hold.observedSeconds - 12.2) < 1e-8)
    _ = hold.consume(.init(time:0.3, angle:170, confidence:0, holdQualification:.staticHold))
    for t in [0.4, 0.5] { _ = hold.consume(.init(time:t, angle:170, holdQualification:.staticHold)) }
    hold.resetContinuity()
    for t in [2.0, 2.1, 5.0, 5.0, 4.0, 4.1] { _ = hold.consume(.init(time:t, angle:170, holdQualification:.staticHold)) }
    #expect(abs(hold.observedSeconds - 12.4) < 1e-8)
    #expect(hold.mode == .staticHold)
}

@Test func highKneesNeedsRecentAlternationAndVisibleTransitions() {
    var hold = PoseHoldCounter(exercise: .highKnees)
    for t in [0.0,0.1,0.2] { _ = hold.consume(.init(time:t, angle:170)) }
    #expect(hold.observedSeconds == 0)
    for (t,q) in [(0.3, HoldQualification.activeLimb(0)),(0.4,.activeLimb(0)),(0.5,.transition),
                  (0.6,.activeLimb(1)),(0.7,.activeLimb(1)),(0.8,.transition)] {
        _ = hold.consume(.init(time:t, angle:100, holdQualification:q))
    }
    #expect(hold.observedSeconds > 0)
    let before = hold.observedSeconds
    for t in [2.0,2.1,2.2] { _ = hold.consume(.init(time:t, angle:170, holdQualification:.transition)) }
    #expect(hold.observedSeconds == before)
    hold.resetContinuity()
    _ = hold.consume(.init(time:2.3, angle:90, holdQualification:.activeLimb(0)))
    _ = hold.consume(.init(time:2.4, angle:90, holdQualification:.activeLimb(0)))
    #expect(hold.observedSeconds == before)
    #expect(hold.mode == .dynamicActivity)
}

@Test func alternatingClockRollbackInvalidatesBothLimbsAndProxyHistoryCannotBecomeAnAngle() {
    var counter=RepCounter(exercise:.standingKneeRaise)
    for (t,a) in [(0.0,170.0),(0.2,170),(0.6,130),(1,90),(1.1,90)] {
        _ = counter.consume(.init(time:t,angle:a,side:0))
    }
    _ = counter.consume(.init(time:0.5,angle:170,side:1))
    _ = counter.consume(.init(time:1.4,angle:170,side:0))
    _ = counter.consume(.init(time:1.6,angle:170,side:0))
    #expect(counter.reps == 0)
    var proxy=RepCounter(exercise:.squat)
    for (t,a) in [(0.0,170.0),(0.2,170),(0.6,130),(1,90),(1.1,90)] {
        _ = proxy.consume(.init(time:t,angle:a,provenance:.normalizedDisplacement))
    }
    _ = proxy.consume(.init(time:1.5,angle:170))
    _ = proxy.consume(.init(time:1.7,angle:170))
    #expect(proxy.lastRepPhases == nil)
}

@Test func switchingBetweenImageAndWorldAnglesCannotCreateACycle() {
    var counter=RepCounter(exercise:.squat,initialReps:2)
    for (t,a,p) in [(0.0,170.0,MeasurementProvenance.jointAngle2D),(0.2,170,.jointAngle2D),
                    (0.6,90,.jointAngle3D),(0.8,90,.jointAngle3D),(1.2,170,.jointAngle2D),(1.4,170,.jointAngle2D)] {
        _ = counter.consume(.init(time:t,angle:a,provenance:p))
    }
    #expect(counter.reps == 2)
}

@Test func quarterSquatThresholdNoiseDoesNotBecomeARep() {
    var counter=RepCounter(exercise:.quarterSquat)
    for (t,a) in [(0.0,161.0),(0.2,161),(0.6,149),(0.8,149),(1.2,161),(1.4,161)] {
        _ = counter.consume(.init(time:t,angle:a))
    }
    #expect(counter.reps == 0)
}

@Test(arguments: [Exercise.tempoHalfSquat, .pausedHalfSquat])
func halfDepthTimingPrescriptionsNeedObservedTimeAtTheirOwnThreshold(exercise: Exercise) {
    var fast=RepCounter(exercise:exercise)
    for (t,a) in [(0.0,170.0),(0.2,170),(0.6,150),(1,125),(1.2,125),(1.6,170),(1.8,170)] {
        _ = fast.consume(.init(time:t,angle:a))
    }
    #expect(fast.reps == 0)
    let cycle: [(Double,Double)] = exercise == .tempoHalfSquat
      ? [(0,170),(0.2,170),(0.6,155),(1,151),(1.5,148),(2,145),(2.5,141),(3,138),(3.7,125),(3.9,125),(4.4,150),(4.9,170),(5.1,170)]
      : [(0,170),(0.2,170),(0.6,150),(1,125),(1.5,125),(2,125),(2.5,125),(3.1,125),(3.5,150),(4,170),(4.2,170)]
    var observed=RepCounter(exercise:exercise)
    for (t,a) in cycle { _ = observed.consume(.init(time:t,angle:a)) }
    #expect(observed.reps == 1)
    #expect(observed.lastRepPhases?.minimumAngle == 125)
}

@Test func sitToStandCountsAnObservedSeatedStartWithoutInventingLoweringOrCycleDuration() {
    var stand=RepCounter(exercise:.sitToStand,initialReps:4)
    var squat=RepCounter(exercise:.halfSquat)
    for (t,a) in [(0.0,125.0),(0.2,125),(0.6,145),(0.9,170),(1.1,170)] {
        _ = stand.consume(.init(time:t,angle:a)); _ = squat.consume(.init(time:t,angle:a))
    }
    #expect(stand.reps == 5)
    #expect(stand.lastRepDuration == nil)
    #expect(stand.lastRepPhases == nil)
    #expect(squat.reps == 0)
    for (t,a) in [(1.4,145.0),(1.8,125),(2,125),(2.4,145),(2.7,170),(2.9,170)] {
        _ = stand.consume(.init(time:t,angle:a))
    }
    #expect(stand.reps == 6)
    #expect(stand.lastRepDuration != nil)
    #expect(stand.lastRepPhases != nil)
}

@Test(arguments: ["midrange","missing","gap","teleport","unseenRise"])
func seatedStartCannotCountWithoutAStableRangeAndContinuouslyWitnessedRise(reason: String) {
    var stand=RepCounter(exercise:.sitToStand,initialReps:4)
    for (t,a) in [(0.0,reason == "midrange" ? 145.0 : 125.0),(0.2,reason == "midrange" ? 145.0 : 125.0)] {
        _ = stand.consume(.init(time:t,angle:a))
    }
    if reason == "missing" { _ = stand.consume(.init(time:0.4,angle:.nan,confidence:0)) }
    let offset=reason == "gap" ? 1.0 : 0.0
    if reason != "unseenRise" { _ = stand.consume(.init(time:offset + (reason == "teleport" ? 0.201 : 0.6),angle:145)) }
    for t in [0.9,1.1] { _ = stand.consume(.init(time:t+offset,angle:170)) }
    #expect(stand.reps == 4)
    #expect(stand.lastRepDuration == nil)
}

@Test func aBriskButWitnessedFirstStandDoesNotNeedAFullCycleDuration() {
    var stand=RepCounter(exercise:.sitToStand)
    for (t,a) in [(0.0,125.0),(0.2,125),(0.3,145),(0.45,170),(0.65,170)] {
        _ = stand.consume(.init(time:t,angle:a))
    }
    #expect(stand.reps == 1)
    #expect(stand.lastRepDuration == nil)
    #expect(stand.lastRepPhases == nil)
}

@Test(arguments: [0,1], ["wholeFrame","absentSecondary"])
func missingObservationInterruptsEitherLimbTimingWithoutErasingWitnessedDepth(side: Int, loss: String) {
    var counter=RepCounter(exercise:.standingBicepsCurl,initialReps:7)
    for (t,a) in [(0.0,170.0),(0.2,170),(0.5,130),(0.8,90),(1,90)] {
        _ = counter.consume(.init(time:t,angle:a,side:side,secondary:.init(angle:170,side:1-side)))
    }
    if loss == "wholeFrame" {
        _ = counter.consume(.init(time:1.1,angle:.nan,confidence:0))
    } else {
        _ = counter.consume(.init(time:1.1,angle:170,side:1-side))
    }
    for t in [1.3,1.5] {
        _ = counter.consume(.init(time:t,angle:170,side:side,secondary:.init(angle:170,side:1-side)))
    }
    #expect(counter.reps == 8)
    #expect(counter.lastRepDuration != nil)
    #expect(counter.lastRepPhases == nil)
}

@Test(arguments: [0,1])
func continuouslyObservedBothLimbsRetainActualAngularPhases(side: Int) {
    var counter=RepCounter(exercise:.standingBicepsCurl)
    for (t,a) in [(0.0,170.0),(0.2,170),(0.5,130),(0.8,90),(1,90),(1.3,170),(1.5,170)] {
        _ = counter.consume(.init(time:t,angle:a,side:side,secondary:.init(angle:170,side:1-side)))
    }
    #expect(counter.reps == 1)
    #expect(counter.lastRepPhases != nil)
}

import Foundation
import Testing
@testable import SpottrCore

@Test func expandedCameraStylesHaveDistinctPersistentIdentities() throws {
    for id in ["tempoSquat", "pausedSquat", "tempoPushup", "pausedPushup"] {
        let entry = try #require(ExerciseCatalog.find(id))
        #expect(entry.tracking?.rawValue == id)
        #expect(entry.unit == .reps)
        #expect(entry.goal > 0)
    }
}

@Test func expandedTrackedAlternativesRetainManualLoggingIdentityAndCountingUnit() throws {
    for (id, unit) in [("widePushup", ExerciseEntry.Unit.reps), ("diamondPushup", .reps),
                       ("wallSit", .seconds), ("calfRaise", .reps), ("birdDog", .reps), ("seatedKneeExtension", .reps)] {
        let entry = try #require(ExerciseCatalog.find(id))
        #expect(entry.tracking?.rawValue == id)
        #expect(entry.unit == unit)
        let record = try LoggedWorkout.make(exerciseID: id, count: entry.goal, sets: 1)
        let set = try #require(WorkoutReport(record: record).sets.first)
        #expect(set.exerciseID == id)
        #expect(set.source == .manual)
        #expect(unit == .seconds ? set.holdSeconds == Double(entry.goal) : set.reps == entry.goal)
    }
}

@Test func addingLibraryStylesDoesNotInsertNewObstaclesIntoTheExistingPushPath() {
    #expect(LocalSkillPath.chain(family: .push) == ["wallPushup", "inclinePushup", "kneePushup", "pushup", "closeGripPushup"])
}

@Test func tempoStylesRejectFastCyclesAndAcceptObservedThreeSecondLowering() throws {
    for id in ["tempoSquat", "tempoPushup"] {
        let exercise = try #require(Exercise(rawValue: id))
        var fast = RepCounter(exercise: exercise)
        consume([(0,170),(0.2,170),(0.6,140),(1,90),(1.2,90),(1.6,170),(1.8,170)], into: &fast)
        #expect(fast.reps == 0)
        var slow = RepCounter(exercise: exercise)
        consume(tempoCycle, into: &slow)
        #expect(slow.reps == 1)
        #expect(slow.lastRepPhases != nil)
    }
}

@Test func waitingAtTheBottomCannotSubstituteForTempoLowering() throws {
    for id in ["tempoSquat", "tempoPushup"] {
        var counter = RepCounter(exercise: try #require(Exercise(rawValue: id)))
        consume([(0,170),(0.2,170),(0.6,140),(1,90),(1.2,90),(1.7,90),(2.2,90),
                 (2.7,90),(3.2,90),(3.7,90),(4.2,90),(4.7,170),(4.9,170)], into: &counter)
        #expect(counter.reps == 0)
    }
}

@Test func pausedStylesRequireTwoContinuousSecondsAtDepth() throws {
    for id in ["pausedSquat", "pausedPushup"] {
        let exercise = try #require(Exercise(rawValue: id))
        var brief = RepCounter(exercise: exercise)
        consume([(0,170),(0.2,170),(0.6,140),(1,90),(1.2,90),(1.6,170),(1.8,170)], into: &brief)
        #expect(brief.reps == 0)
        var held = RepCounter(exercise: exercise)
        consume(pausedCycle, into: &held)
        #expect(held.reps == 1)
    }
}

@Test func returningAboveDepthRestartsTheRequiredPause() throws {
    for id in ["pausedSquat", "pausedPushup"] {
        var counter = RepCounter(exercise: try #require(Exercise(rawValue: id)))
        consume([(0,170),(0.2,170),(0.6,140),(1,90),(1.5,90),(2,90),(2.3,130),
                 (2.7,90),(3.2,90),(3.7,90),(4.1,170),(4.3,170)], into: &counter)
        #expect(counter.reps == 0)
    }
}

@Test func temporalStylesRejectUnobservedTimeWithoutRemovingPreviouslyCountedReps() throws {
    for id in ["tempoSquat", "tempoPushup", "pausedSquat", "pausedPushup"] {
        let exercise = try #require(Exercise(rawValue: id))
        let cycle = id.hasPrefix("tempo") ? tempoCycle : pausedCycle
        for interruption in ["confidence", "gap", "side", "alignment", "reset"] {
            var counter = RepCounter(exercise: exercise)
            consume(cycle, into: &counter)
            #expect(counter.reps == 1)
            let offset = 6.0
            for (time, angle) in cycle {
                if time == 1 {
                    switch interruption {
                    case "confidence": _ = counter.consume(.init(time: offset + 0.9, angle: .nan, confidence: 0))
                    case "side": _ = counter.consume(.init(time: offset + 0.9, angle: 130, side: 1))
                    case "alignment": _ = counter.consume(.init(time: offset + 0.9, angle: 130, aligned: false))
                    case "reset": counter.resetMovement()
                    default: break
                    }
                }
                if interruption == "gap", time >= 1, time < 2 { continue }
                _ = counter.consume(.init(time: offset + time, angle: angle))
            }
            #expect(counter.reps == 1)
        }
    }
}

@Test func temporalPushupsRequireAVisibleBodyLineAndRejectUprightArmBends() throws {
    for id in ["tempoPushup", "pausedPushup"] {
        let exercise = try #require(Exercise(rawValue: id))
        var points = Array(repeating: PosePoint(x: 0, y: 0, confidence: 0), count: 33)
        for (index,x,y) in [(11,0.1,0.4),(13,0.1,0.6),(15,0.3,0.6),(23,0.5,0.4),(27,0.9,0.4)] {
            points[index] = .init(x: x, y: y, confidence: 1)
        }
        #expect(PoseGeometry.measure(.init(time: 1, width: 1000, height: 1000, points: points), exercise: exercise)?.bodyLine == .steady)
        points[27] = .init(x: 0.9, y: 0.4, confidence: 0)
        #expect(PoseGeometry.measure(.init(time: 1, width: 1000, height: 1000, points: points), exercise: exercise) == nil)
        points[23] = .init(x: 0.1, y: 0.8, confidence: 1)
        #expect(PoseGeometry.measure(.init(time: 1, width: 1000, height: 1000, points: points), exercise: exercise) == nil)
    }
}

private let tempoCycle: [(Double, Double)] = [(0,170),(0.2,170),(0.6,150),(1,145),(1.5,140),
    (2,135),(2.5,125),(3,115),(3.7,90),(3.9,90),(4.4,130),(4.9,170),(5.1,170)]
private let pausedCycle: [(Double, Double)] = [(0,170),(0.2,170),(0.6,140),(1,90),(1.5,90),
    (2,90),(2.5,90),(3.1,90),(3.5,130),(4,170),(4.2,170)]
private func consume(_ samples: [(Double, Double)], into counter: inout RepCounter) {
    for (time, angle) in samples { _ = counter.consume(.init(time: time, angle: angle)) }
}

@Test func newGuidesExplainTimingAndManualSupports() throws {
    for id in ["tempoSquat", "tempoPushup"] {
        let guide = try #require(ExerciseDemonstrationGuide.find(id))
        #expect(guide.phases.contains { $0.contains("3 seconds") })
    }
    for id in ["pausedSquat", "pausedPushup"] {
        let guide = try #require(ExerciseDemonstrationGuide.find(id))
        #expect(guide.phases.contains { $0.contains("2 seconds") })
    }
    #expect(try #require(ExerciseDemonstrationGuide.find("wallSit")).support == "Wall")
    #expect(try #require(ExerciseDemonstrationGuide.find("seatedKneeExtension")).support == "Stable chair")
    #expect(try #require(ExerciseDemonstrationGuide.find("birdDog")).requiresBothSides)
}

@Test func pausedStyleAsksForAHoldUntilObservedPauseIsComplete() throws {
    var counter = RepCounter(exercise: try #require(Exercise(rawValue: "pausedSquat")))
    consume([(0,170),(0.2,170),(0.6,140),(1,90)], into: &counter)
    #expect(counter.consume(.init(time: 1.3, angle: 90)).rawValue == "hold")
    _ = counter.consume(.init(time: 1.8, angle: 90))
    _ = counter.consume(.init(time: 2.3, angle: 90))
    _ = counter.consume(.init(time: 2.8, angle: 90))
    #expect(counter.consume(.init(time: 3.1, angle: 90)) == .rise)
}

@Test func expandedStylesSelectDedicatedFacelessFigureGuides() throws {
    for id in ["tempoSquat", "pausedSquat", "tempoPushup", "pausedPushup", "widePushup", "diamondPushup",
               "wallSit", "calfRaise", "birdDog", "seatedKneeExtension"] {
        let guide = try #require(ExerciseDemonstrationGuide.find(id))
        #expect(guide.art == "stick-\(id)")
    }
}

import Foundation
import Testing
@testable import SpottrCore

@Test func recordsActualRestBetweenCompletedSetsWithoutInitialPreparation() {
    var session = TrainingSession()
    session.start(at: 100)
    session.endSet(at: 102)
    session.nextSet(at: 113)
    session.endSet(at: 115)
    #expect(session.sets.first?.restSecondsBefore == nil)
    #expect(session.sets.last?.restSecondsBefore == 11)
}

@Test(arguments: [Double.nan, Double.infinity, -Double.infinity])
func rejectsNonFiniteSetTransitionTimes(time: Double) {
    var session = TrainingSession()
    session.start(at: 0)
    session.endSet(at: time)
    #expect(session.phase == .active)
    #expect(session.sets.isEmpty)
    session.endSet(at: 2)
    session.nextSet(at: time)
    #expect(session.phase == .rest)
    session.nextSet(at: 13)
    session.endSet(at: 14)
    #expect(session.sets.last?.restSecondsBefore == 11)
}

@Test func activeSetPausesDoNotBecomeRestBeforeTheNextSet() {
    var session = TrainingSession()
    session.start(at: 0)
    session.pause(at: 1)
    session.resume(at: 100)
    session.endSet(at: 102)
    session.nextSet(at: 113)
    session.pause(at: 114)
    session.resume(at: 200)
    session.endSet(at: 201)
    #expect(session.sets.first?.restSecondsBefore == nil)
    #expect(session.sets.last?.restSecondsBefore == 11)
    #expect(session.sets.last?.activeSeconds == 2)
}

@Test func restartingAnInputSourcePreservesPreviousRestWithoutCountingStaging() {
    var session = TrainingSession()
    session.start(at: 0)
    session.restartSet(source: .video, at: 50)
    session.endSet(at: 52)
    session.nextSet(at: 63)
    session.restartSet(source: .video, at: 100)
    session.endSet(at: 102)
    #expect(session.sets.first?.restSecondsBefore == nil)
    #expect(session.sets.last?.restSecondsBefore == 11)
    #expect(session.sets.last?.activeSeconds == 2)
}

@Test(arguments: [2.0, 1.0])
func immediateOrBackwardsSetTransitionsRecordZeroRest(nextStart: Double) {
    var session = TrainingSession()
    session.start(at: 0)
    session.endSet(at: 2)
    session.nextSet(at: nextStart)
    session.endSet(at: 3)
    #expect(session.sets.last?.restSecondsBefore == 0)
}

@Test func legacySetJSONWithoutRestTimingRemainsReadable() throws {
    let json = """
    {"id":"00000000-0000-0000-0000-000000000001","exercise":"squat","number":1,
     "reps":4,"target":12,"activeSeconds":20,"source":"camera","reason":"voluntary"}
    """
    let record = try JSONDecoder().decode(SetRecord.self, from: Data(json.utf8))
    #expect(record.restSecondsBefore == nil)
    #expect(record.reps == 4)
}

@Test func savesObservedRepDurationsAndClearsThemForNextSet() {
    var session = TrainingSession()
    session.start(at: 0)
    for (time, angle) in [(0.0, 170.0), (0.2, 170), (0.6, 90), (0.8, 90), (1.2, 170), (1.4, 170)] {
        session.consume(.init(time: time, angle: angle), generation: session.generation)
    }
    session.endSet(at: 2)
    #expect(session.sets.first?.repDurations?.count == 1)
    #expect(abs((session.sets.first?.repDurations?.first ?? 0) - 1.2) < 0.001)
    session.nextSet(at: 3)
    session.endSet(at: 4)
    #expect(session.sets.last?.repDurations?.isEmpty == true)
}

@Test func trackingLossTakesPriorityOverAnUncertainFormCue() {
    var session = TrainingSession()
    session.start(at: 0)
    session.consume(.init(time: 0.1, angle: 90, confidence: 0.1, bodyAngle: 153), generation: session.generation)
    #expect(session.cue == .tracking)
}

@Test func canStartWithPushupsAndThenSwitchToSquats() {
    var session = TrainingSession(firstExercise: .pushup)
    session.start(at: 0)
    #expect(session.exercise == .pushup)
    for index in 0..<3 {
        session.endSet(at: Double(index + 1))
        session.nextSet(at: Double(index + 2))
    }
    #expect(session.exercise == .squat)
}

@Test func pauseDiscardsPartialRepAndExcludesPausedTime() {
    var session = TrainingSession()
    session.start(at: 10)
    let original = session.generation
    for (t, a) in [(10.0, 170.0), (10.2, 170), (10.6, 90), (10.8, 90)] {
        session.consume(.init(time: t, angle: a), generation: original)
    }
    session.pause(at: 11)
    session.resume(at: 20)
    session.consume(.init(time: 20.1, angle: 170), generation: original)
    session.consume(.init(time: 20.3, angle: 170), generation: session.generation)
    session.endSet(at: 22)
    #expect(session.phase == .rest)
    #expect(session.sets.first?.reps == 0)
    #expect(session.sets.first?.activeSeconds == 3)
    #expect(session.generation != original)
}

@Test func progressesAcrossBothExercisesAndFinishesOnce() {
    var session = TrainingSession()
    session.start(at: 0)
    session.endSet(at: 1)
    session.endSet(at: 2)
    session.feedback(reserve: 2, reason: .form)
    #expect(session.sets.count == 1)
    #expect(session.sets.first?.reserve == 2)
    #expect(session.sets.first?.reason == .form)
    for index in 1...5 {
        session.nextSet(at: Double(index * 10))
        #expect(session.exercise == (index < 3 ? .squat : .pushup))
        session.endSet(at: Double(index * 10 + 1))
    }
    session.nextSet(at: 60)
    #expect(session.phase == .finished)
    #expect(session.record.sets.count == 6)
    session.finish(at: 70)
    #expect(session.record.sets.count == 6)
}

@Test func changingVideoSourceRestartsSetRatherThanCombiningCounts() {
    var session = TrainingSession()
    session.start(at: 0)
    for (t, a) in [(0.0, 170.0), (0.2, 170), (0.6, 90), (0.8, 90), (1.2, 170), (1.4, 170)] {
        session.consume(.init(time: t, angle: a), generation: session.generation)
    }
    #expect(session.counter.reps == 1)
    let old = session.generation
    session.restartSet(source: .video, at: 2)
    #expect(session.counter.reps == 0)
    #expect(session.generation != old)
    session.endSet(at: 3)
    #expect(session.sets.first?.source == .video)
    #expect(session.sets.first?.activeSeconds == 1)
}

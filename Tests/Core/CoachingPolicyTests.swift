import XCTest
@testable import SpottrCore

final class CoachingPolicyTests: XCTestCase {
    private let sessionID = UUID()
    private let generation = UUID()
    private let wallTime = Date(timeIntervalSince1970: 1_000)

    private func input(now: Double = 0, phase: SessionPhase = .active, reps: Int = 0,
                       duration: Double? = nil, cue: Cue = .controlled, heartRate: [SensorReading] = [],
                       rest: Double? = nil, target: Int = 12, stop: StopReason? = nil,
                       generation: UUID? = nil, sessionID: UUID? = nil, exercise: Exercise = .squat,
                       source: InputSource = .camera, encouragementEnabled: Bool = false) -> CoachingInput {
        .init(sessionID: sessionID ?? self.sessionID, generation: generation ?? self.generation,
              phase: phase, now: now, exercise: exercise, repCount: reps, lastRepDuration: duration,
              cue: cue, heartRate: heartRate, wallTime: wallTime, restElapsed: rest, target: target, stopReason: stop, source: source, encouragementEnabled: encouragementEnabled)
    }

    func testDiscomfortStopsCoachingImmediatelyAndOnlyOnceForTheSession() {
        var policy = CoachingPolicy()
        let decision = policy.evaluate(input(now: 0.1, stop: .discomfort))
        XCTAssertEqual(decision?.priority, .stop)
        XCTAssertEqual(decision?.reason, .discomfort)
        XCTAssertNil(policy.evaluate(input(now: 0.2, stop: .discomfort)))
        XCTAssertNil(policy.evaluate(input(now: 60, phase: .rest, rest: 60)))
        XCTAssertNil(policy.evaluate(input(now: 70, reps: 12, generation: UUID())))
    }
    func testFormAndTrackingInterruptImmediatelyAndSuppressConflictingEncouragement() {
        var policy = CoachingPolicy()
        XCTAssertNil(policy.evaluate(input(now: 0)))
        XCTAssertEqual(policy.evaluate(input(now: 0.1, reps: 12, cue: .alignment))?.reason, .alignment)
        XCTAssertNil(policy.evaluate(input(now: 0.2, reps: 12, cue: .alignment)))
        XCTAssertEqual(policy.evaluate(input(now: 0.3, reps: 12, cue: .tracking))?.reason, .tracking)
        XCTAssertNil(policy.evaluate(input(now: 1, phase: .paused, cue: .tracking)))
        XCTAssertNil(policy.evaluate(input(now: 2, phase: .finished, cue: .alignment)))
    }

    func testSlowRepUsesFivePriorDistinctSamplesAndSampleStandardDeviation() {
        var policy = CoachingPolicy()
        for (index, seconds) in [1.0, 2, 3, 4, 5].enumerated() {
            XCTAssertNil(policy.evaluate(input(now: Double(index), reps: index + 1, duration: seconds)))
        }
        let decision = policy.evaluate(input(now: 4.1, reps: 6, duration: 4.6))
        XCTAssertEqual(decision?.reason, .slowerRep)
        XCTAssertEqual(decision?.priority, .pacing)
        XCTAssertEqual(decision?.elapsed, 4.6)
        XCTAssertTrue(decision?.facts.contains { $0.contains("5 prior") && $0.contains("3.00") && $0.contains("1.58") } == true)
        XCTAssertNil(policy.evaluate(input(now: 5, reps: 6, duration: 4.6)))
        XCTAssertNil(policy.evaluate(input(now: 6, reps: 7, duration: 8)))
    }

    func testTargetBoundaryIsObservedOnRepCompletionEvenWithinOneSecond() {
        var policy = CoachingPolicy()
        XCTAssertNil(policy.evaluate(input(now: 1, reps: 11)))
        let reached = policy.evaluate(input(now: 1.1, reps: 12, duration: 2))
        XCTAssertEqual(reached?.reason, .targetReached)
        XCTAssertEqual(reached?.priority, .pacing)
        XCTAssertNil(policy.evaluate(input(now: 20, reps: 12)))
        XCTAssertNil(policy.evaluate(input(now: 30, reps: 13)))
    }

    func testRestReminderUsesActualElapsedRestOnceAndRespectsOneSecondChecks() {
        var policy = CoachingPolicy()
        XCTAssertNil(policy.evaluate(input(now: 0, phase: .rest)))
        XCTAssertNil(policy.evaluate(input(now: 1, phase: .rest, rest: 44.9)))
        XCTAssertNil(policy.evaluate(input(now: 1.1, phase: .rest, rest: 45)))
        let reminder = policy.evaluate(input(now: 2, phase: .rest, rest: 45.9))
        XCTAssertEqual(reminder?.reason, .restReminder)
        XCTAssertEqual(reminder?.elapsed, 45.9)
        XCTAssertEqual(reminder?.priority, .rest)
        XCTAssertNil(policy.evaluate(input(now: 20, phase: .rest, rest: 63.9)))
    }

    func testNewSetsRetainExerciseBaselineAndRetiredGenerationsCannotSpeak() {
        var policy = CoachingPolicy()
        for rep in 1...5 { XCTAssertNil(policy.evaluate(input(now: Double(rep), reps: rep, duration: 1))) }
        let restGeneration = UUID()
        XCTAssertNil(policy.evaluate(input(now: 10, phase: .rest, rest: 0, generation: restGeneration)))
        let nextGeneration = UUID()
        XCTAssertEqual(policy.evaluate(input(now: 0, reps: 1, duration: 2, generation: nextGeneration))?.reason, .slowerRep)
        XCTAssertNil(policy.evaluate(input(now: 100, cue: .tracking, generation: generation)))
        XCTAssertNil(policy.evaluate(input(now: 101, reps: 1, duration: 5, generation: nextGeneration, exercise: .pushup)))
    }

    func testPauseResumeCannotLearnSameRepAgainAndNewSessionCanCoachAfterDiscomfort() {
        var policy = CoachingPolicy()
        for rep in 1...5 { _ = policy.evaluate(input(now: Double(rep), reps: rep, duration: 1)) }
        let paused = UUID()
        XCTAssertNil(policy.evaluate(input(now: 6, phase: .paused, reps: 5, duration: 15, generation: paused)))
        let resumed = UUID()
        XCTAssertNil(policy.evaluate(input(now: 0, reps: 5, duration: 15, generation: resumed)))
        XCTAssertEqual(policy.evaluate(input(now: 1, reps: 6, duration: 2, generation: resumed))?.reason, .slowerRep)
        XCTAssertEqual(policy.evaluate(input(now: 1.1, stop: .discomfort, generation: resumed))?.priority, .stop)
        let otherSession = UUID()
        XCTAssertEqual(policy.evaluate(input(now: 0, cue: .tracking, sessionID: otherSession))?.reason, .tracking)
        XCTAssertNil(policy.evaluate(input(now: 100, cue: .alignment)))
    }

    func testWatchReadingsAreObservationsOnlyAndDuplicatesCannotCreateBaseline() {
        let readings = [100.0, 102, 104, 106, 108].enumerated().map {
            SensorReading(value: $0.element, date: wallTime.addingTimeInterval(Double($0.offset) - 4))
        }
        var policy = CoachingPolicy()
        XCTAssertNil(policy.evaluate(input(now: 0, heartRate: readings)))
        let decision = policy.evaluate(input(now: 0.1, cue: .alignment, heartRate: readings + readings))
        XCTAssertTrue(decision?.facts.contains { $0.contains("108 bpm") } == true)
        XCTAssertTrue(decision?.facts.contains { $0.contains("5 unique") && $0.contains("104.00") && $0.contains("3.16") } == true)
        let duplicate = Array(repeating: readings[0], count: 20)
        var sparse = CoachingPolicy()
        let sparseDecision = sparse.evaluate(input(cue: .alignment, heartRate: duplicate))
        XCTAssertFalse(sparseDecision?.facts.contains { $0.contains("sample SD") } == true)
        let invalid = [SensorReading(value: .nan, date: wallTime), SensorReading(value: 301, date: wallTime),
                       SensorReading(value: 80, date: wallTime.addingTimeInterval(-13)),
                       SensorReading(value: 80, date: wallTime.addingTimeInterval(3))]
        var stale = CoachingPolicy()
        XCTAssertFalse(stale.evaluate(input(cue: .alignment, heartRate: invalid))?.facts.contains { $0.contains("bpm") } == true)
    }

    func testFormCueReservesCooldownBeforeOrdinaryPacingCanSpeak() {
        var policy = CoachingPolicy()
        for rep in 1...5 { _ = policy.evaluate(input(now: Double(rep), reps: rep, duration: 1)) }
        XCTAssertEqual(policy.evaluate(input(now: 5.1, cue: .alignment))?.priority, .form)
        XCTAssertNil(policy.evaluate(input(now: 5.2, reps: 6, duration: 3)))
        XCTAssertEqual(policy.evaluate(input(now: 15.1, reps: 7, duration: 5))?.reason, .slowerRep)
    }

    func testTempoNoiseMarginAndInvalidOrDuplicateDurationsDoNotCreateSlowdown() {
        var policy = CoachingPolicy()
        for (index, duration) in [Double.nan, 0.5, .infinity, 16].enumerated() {
            XCTAssertNil(policy.evaluate(input(now: Double(index), reps: index + 1, duration: duration, target: 100)))
        }
        for rep in 5...9 { XCTAssertNil(policy.evaluate(input(now: Double(rep), reps: rep, duration: 1, target: 100))) }
        for tick in 10...14 { XCTAssertNil(policy.evaluate(input(now: Double(tick), reps: 9, duration: 15, target: 100))) }
        XCTAssertNil(policy.evaluate(input(now: 15, reps: 10, duration: 1.25, target: 100)))
        XCTAssertEqual(policy.evaluate(input(now: 16, reps: 11, duration: 1.5, target: 100))?.reason, .slowerRep)
    }

    func testInvalidOrBackwardsClockCannotProduceCueAndHugeRestDoesNotCrash() {
        var policy = CoachingPolicy()
        XCTAssertNil(policy.evaluate(input(now: .nan, cue: .tracking)))
        XCTAssertNil(policy.evaluate(input(now: 3)))
        XCTAssertNil(policy.evaluate(input(now: 2, cue: .tracking)))
        XCTAssertEqual(policy.evaluate(input(now: 4, cue: .tracking))?.priority, .form)
        var resting = CoachingPolicy()
        XCTAssertNil(resting.evaluate(input(phase: .rest, rest: .infinity)))
        XCTAssertEqual(resting.evaluate(input(now: 1, phase: .rest, rest: 1e30))?.reason, .restReminder)
    }

    private func recordedSet(id: UUID = UUID(), exercise: Exercise = .squat, reps: Int? = nil,
                             durations: [Double]?, source: InputSource = .camera,
                             reason: StopReason = .target) -> SetRecord {
        .init(id: id, exercise: exercise, number: 1, reps: reps ?? durations?.count ?? 0, target: 12,
              activeSeconds: 20, source: source, reason: reason, repDurations: durations)
    }

    func testFirstNewRepUsesPersonalHistoryAndNewSessionRestoresSeed() {
        let saved = SessionRecord(id: UUID(), date: wallTime, sets: [recordedSet(durations: [1, 1, 1, 1, 1])])
        var policy = CoachingPolicy(history: [saved])
        let first = policy.evaluate(input(reps: 1, duration: 2))
        XCTAssertEqual(first?.reason, .slowerRep)
        XCTAssertTrue(first?.facts.contains { $0.contains("5 prior") && $0.contains("mean 1.00") } == true)
        _ = policy.evaluate(input(now: 1, stop: .discomfort))
        let nextSession = policy.evaluate(input(reps: 1, duration: 2, sessionID: UUID()))
        XCTAssertEqual(nextSession?.reason, .slowerRep)
        XCTAssertTrue(nextSession?.facts.contains { $0.contains("5 prior") } == true)
    }

    func testPersonalHistoryRejectsReplayManualCensoredAndMalformedSets() {
        let ineligible = [
            recordedSet(durations: [15, 15, 15, 15, 15], source: .video),
            recordedSet(durations: [15, 15, 15, 15, 15], source: .manual),
            recordedSet(durations: [15, 15, 15, 15, 15], reason: .discomfort),
            recordedSet(durations: [15, 15, 15, 15, 15], reason: .form),
            recordedSet(reps: 6, durations: [15, 15, 15, 15, 15]),
            recordedSet(durations: [1, 1, 1, 1, .nan]),
            recordedSet(durations: [1, 1, 1, 1, .infinity]),
            recordedSet(durations: [1, 1, 1, 1, 0.5]),
            recordedSet(durations: [1, 1, 1, 1, 16]),
            recordedSet(durations: nil)
        ]
        for badSet in ineligible {
            let saved = SessionRecord(id: UUID(), date: wallTime,
                                      sets: [recordedSet(durations: [1, 1, 1, 1, 1]), badSet])
            var policy = CoachingPolicy(history: [saved])
            let decision = policy.evaluate(input(reps: 1, duration: 2))
            XCTAssertEqual(decision?.reason, .slowerRep)
            XCTAssertTrue(decision?.facts.contains { $0.contains("5 prior") && $0.contains("mean 1.00") } == true)
        }
    }

    func testRepeatedSavedSessionsAndSetIDsCannotCreateFivePersonalSamples() {
        let saved = SessionRecord(id: UUID(), date: wallTime, sets: [recordedSet(durations: [1, 1, 1])])
        let repeatedSet = SessionRecord(id: UUID(), date: wallTime.addingTimeInterval(1), sets: saved.sets)
        let repeatedSession = SessionRecord(id: saved.id, date: wallTime.addingTimeInterval(1),
                                            sets: [recordedSet(durations: [1, 1, 1])])
        for history in [[saved, saved], [saved, repeatedSet], [saved, repeatedSession]] {
            var policy = CoachingPolicy(history: history)
            XCTAssertNil(policy.evaluate(input(reps: 1, duration: 2)))
        }
    }

    func testPersonalSeedKeepsLatestSixtySamplesPerExerciseAndNewestSessionSnapshot() {
        let older = SessionRecord(id: UUID(), date: wallTime.addingTimeInterval(-1),
                                  sets: [recordedSet(durations: [15, 15, 15, 15, 15])])
        let recent = SessionRecord(id: UUID(), date: wallTime,
                                   sets: [recordedSet(durations: Array(repeating: 1, count: 60)),
                                          recordedSet(exercise: .pushup, durations: Array(repeating: 15, count: 60))])
        var capped = CoachingPolicy(history: [recent, older])
        let squat = capped.evaluate(input(reps: 1, duration: 2))
        XCTAssertEqual(squat?.reason, .slowerRep)
        XCTAssertTrue(squat?.facts.contains { $0.contains("60 prior") && $0.contains("mean 1.00") } == true)
        var separate = CoachingPolicy(history: [recent, older])
        XCTAssertNil(separate.evaluate(input(reps: 1, duration: 2, exercise: .pushup)))
        let replacement = SessionRecord(id: older.id, date: wallTime,
                                        sets: [recordedSet(durations: [1, 1, 1, 1, 1])])
        var updated = CoachingPolicy(history: [older, replacement])
        XCTAssertEqual(updated.evaluate(input(reps: 1, duration: 2))?.reason, .slowerRep)
    }

    func testVideoReplayCannotTrainPersonalBaselineButRealCameraRepsCan() {
        var policy = CoachingPolicy()
        for rep in 1...5 {
            XCTAssertNil(policy.evaluate(input(now: Double(rep), reps: rep, duration: 1, source: .video)))
        }
        let camera = UUID()
        XCTAssertNil(policy.evaluate(input(now: 10, reps: 1, duration: 2, generation: camera)))
        for rep in 2...6 {
            XCTAssertNil(policy.evaluate(input(now: Double(rep + 10), reps: rep, duration: 1, generation: camera)))
        }
        XCTAssertEqual(policy.evaluate(input(now: 20, reps: 7, duration: 2, generation: camera))?.reason, .slowerRep)
        let replay = UUID()
        XCTAssertNil(policy.evaluate(input(now: 21, reps: 1, duration: 15, generation: replay, source: .video)))
        let returnedCamera = UUID()
        XCTAssertEqual(policy.evaluate(input(now: 22, reps: 1, duration: 3, generation: returnedCamera))?.reason, .slowerRep)
    }

    func testNonCameraInputStaysSilentExceptExplicitDiscomfort() {
        for source in [InputSource.video, .manual] {
            var policy = CoachingPolicy()
            let readings = [SensorReading(value: 120, date: wallTime)]
            XCTAssertNil(policy.evaluate(input(cue: .alignment, heartRate: readings, source: source)))
            XCTAssertNil(policy.evaluate(input(now: 11, phase: .rest, rest: 60, source: source)))
            XCTAssertEqual(policy.evaluate(input(now: 12, stop: .discomfort, source: source))?.reason, .discomfort)
            XCTAssertNil(policy.evaluate(input(now: 13, stop: .discomfort, source: source)))
        }
    }

}

extension CoachingPolicyTests {
    func testConfiguredCameraHistorySeedsRhythmButManualReplayAndInvalidTimingDoNot() {
        let cases: [(InputSource, StopReason, [Double], String, Bool)] = [
            (.camera, .voluntary, [1, 1, 1, 1, 1], "squat", true),
            (.manual, .voluntary, [1, 1, 1, 1, 1], "squat", false),
            (.video, .voluntary, [1, 1, 1, 1, 1], "squat", false),
            (.camera, .discomfort, [1, 1, 1, 1, 1], "squat", false),
            (.camera, .form, [1, 1, 1, 1, 1], "squat", false),
            (.camera, .voluntary, [1, 1, 1, 1], "squat", false),
            (.camera, .voluntary, [1, 1, 1, 1, .nan], "squat", false),
            (.camera, .voluntary, [1, 1, 1, 1, 16], "squat", false),
            (.camera, .voluntary, [1, 1, 1, 1, 1], "wallPushup", false)
        ]
        for (source, reason, durations, exerciseID, eligible) in cases {
            let set = LoggedSet(id: UUID(), exerciseID: exerciseID, reps: 5, seconds: 0,
                source: source, reason: reason, repDurations: durations)
            let record = SessionRecord(id: UUID(), date: wallTime, sets: [], loggedSets: [set, set])
            var policy = CoachingPolicy(history: [record, record])
            let decision = policy.evaluate(input(now: 1, reps: 1, duration: 2))
            XCTAssertEqual(decision?.reason, eligible ? CoachingReason.slowerRep : nil)
            if eligible { XCTAssertTrue(decision?.facts.contains { $0.contains("5 prior reps") } == true) }
        }
    }
}


extension CoachingPolicyTests {
    private func rhythmPolicy(_ durations: [Double] = [1, 2, 3, 4, 5], exercise: Exercise = .squat) -> CoachingPolicy {
        CoachingPolicy(history: [SessionRecord(id: UUID(), date: wallTime,
            sets: [recordedSet(exercise: exercise, durations: durations)])])
    }

    func testSteadyRhythmRequiresExplicitOptInAndUsesOnlyPriorSameExerciseSamples() {
        var disabled = rhythmPolicy()
        XCTAssertNil(disabled.evaluate(input(reps: 1, duration: 3)))
        var enabled = rhythmPolicy()
        let cue = enabled.evaluate(input(reps: 1, duration: 3, encouragementEnabled: true))
        XCTAssertEqual(cue?.reason.rawValue, "steadyRhythm")
        XCTAssertEqual(cue?.text, "Keep a steady rhythm.")
        XCTAssertEqual(cue?.priority, .pacing)
        XCTAssertEqual(cue?.elapsed, 3)
        XCTAssertTrue(cue?.facts.contains { $0.contains("5 prior") && $0.contains("3.00") && $0.contains("1.58") } == true)
        for (durations, exercise) in [([1.0, 2, 3, 4], Exercise.squat), ([1.0, 2, 3, 4, 5], .pushup)] {
            var insufficient = rhythmPolicy(durations, exercise: exercise)
            XCTAssertNil(insufficient.evaluate(input(reps: 1, duration: 3, encouragementEnabled: true)))
        }
    }

    func testEncouragementRejectsFastInvalidAndOutlyingRepsButSlowCueWins() {
        for duration in [Double.nan, .infinity, 0.5, 16, 1.4] {
            var policy = rhythmPolicy()
            XCTAssertNil(policy.evaluate(input(reps: 1, duration: duration, encouragementEnabled: true)))
        }
        var slow = rhythmPolicy()
        XCTAssertEqual(slow.evaluate(input(reps: 1, duration: 4.6, encouragementEnabled: true))?.reason, .slowerRep)
        for duration in [0.75, 1.25] {
            var consistent = rhythmPolicy([1, 1, 1, 1, 1])
            XCTAssertEqual(consistent.evaluate(input(reps: 1, duration: duration, encouragementEnabled: true))?.reason.rawValue, "steadyRhythm")
        }
        var fast = rhythmPolicy([1, 1, 1, 1, 1])
        XCTAssertNil(fast.evaluate(input(reps: 1, duration: 0.74, encouragementEnabled: true)))
    }

    func testEncouragementNeverOverridesStopFormTargetRestOrCooldown() {
        for (cue, reason) in [(Cue.tracking, CoachingReason.tracking), (.alignment, .alignment)] {
            var policy = rhythmPolicy()
            XCTAssertEqual(policy.evaluate(input(reps: 1, duration: 3, cue: cue, encouragementEnabled: true))?.reason, reason)
            XCTAssertNil(policy.evaluate(input(now: 1, reps: 2, duration: 3, encouragementEnabled: true)))
        }
        var stopped = rhythmPolicy()
        XCTAssertEqual(stopped.evaluate(input(reps: 1, duration: 3, stop: .discomfort, encouragementEnabled: true))?.reason, .discomfort)
        XCTAssertNil(stopped.evaluate(input(now: 20, reps: 2, duration: 3, encouragementEnabled: true)))
        var target = rhythmPolicy()
        XCTAssertEqual(target.evaluate(input(reps: 1, duration: 3, target: 1, encouragementEnabled: true))?.reason, .targetReached)
        XCTAssertNil(target.evaluate(input(now: 20, reps: 2, duration: 3, target: 1, encouragementEnabled: true)))
        for target in [0, -1] {
            var unspecified = rhythmPolicy()
            XCTAssertNil(unspecified.evaluate(input(reps: 1, duration: 3, target: target, encouragementEnabled: true)))
        }
        var rest = rhythmPolicy()
        XCTAssertEqual(rest.evaluate(input(phase: .rest, rest: 45, encouragementEnabled: true))?.reason, .restReminder)
        var cooldown = rhythmPolicy()
        XCTAssertEqual(cooldown.evaluate(input(reps: 1, duration: 3, encouragementEnabled: true))?.reason.rawValue, "steadyRhythm")
        XCTAssertNil(cooldown.evaluate(input(now: 9.99, reps: 2, duration: 3, encouragementEnabled: true)))
        XCTAssertEqual(cooldown.evaluate(input(now: 10, reps: 3, duration: 3, encouragementEnabled: true))?.reason.rawValue, "steadyRhythm")
    }

    func testEncouragementCannotReplayDuplicateStaleNonCameraOrPausedObservations() {
        var policy = rhythmPolicy()
        XCTAssertEqual(policy.evaluate(input(now: 10, reps: 1, duration: 3, encouragementEnabled: true))?.reason.rawValue, "steadyRhythm")
        XCTAssertNil(policy.evaluate(input(now: 20, reps: 1, duration: 3, encouragementEnabled: true)))
        XCTAssertNil(policy.evaluate(input(now: 19, reps: 2, duration: 3, encouragementEnabled: true)))
        for source in [InputSource.manual, .video] {
            var replay = rhythmPolicy()
            XCTAssertNil(replay.evaluate(input(reps: 1, duration: 3, source: source, encouragementEnabled: true)))
            XCTAssertNil(replay.evaluate(input(now: 20, reps: 1, duration: 3, encouragementEnabled: true)))
        }
        var paused = rhythmPolicy()
        XCTAssertNil(paused.evaluate(input(phase: .paused, reps: 1, duration: 3, encouragementEnabled: true)))
        let resumed = UUID()
        XCTAssertNil(paused.evaluate(input(now: 1, reps: 1, duration: 3, generation: resumed, encouragementEnabled: true)))
        XCTAssertEqual(paused.evaluate(input(now: 20, reps: 2, duration: 3, generation: resumed, encouragementEnabled: true))?.reason.rawValue, "steadyRhythm")
        XCTAssertNil(paused.evaluate(input(now: 40, reps: 3, duration: 3, encouragementEnabled: true)))
    }

    func testHeartRateCannotEnableEncouragementWithoutRhythmEvidence() {
        var policy = CoachingPolicy()
        let readings = [SensorReading(value: 80, date: wallTime)]
        XCTAssertNil(policy.evaluate(input(reps: 1, duration: 3, heartRate: readings, encouragementEnabled: true)))
        var sufficient = rhythmPolicy()
        let cue = sufficient.evaluate(input(reps: 1, duration: 3, heartRate: readings, encouragementEnabled: true))
        XCTAssertEqual(cue?.reason.rawValue, "steadyRhythm")
        XCTAssertFalse(cue?.facts.contains { $0.contains("bpm") } == true)
    }
}


extension CoachingPolicyTests {
    func testEncouragementLearnsOnlyDistinctControlledCameraRepsAndRejectsRepJumps() {
        for cue in [Cue.tracking, .alignment, .paused, .ready] {
            var policy = CoachingPolicy()
            for rep in 1...5 {
                _ = policy.evaluate(input(now: Double(rep), reps: rep, duration: 3, cue: cue, encouragementEnabled: true))
            }
            XCTAssertNil(policy.evaluate(input(now: 20, reps: 6, duration: 3, encouragementEnabled: true)))
        }
        var live = CoachingPolicy()
        for rep in 1...5 {
            XCTAssertNil(live.evaluate(input(now: Double(rep), reps: rep, duration: 3, encouragementEnabled: true)))
        }
        XCTAssertEqual(live.evaluate(input(now: 6, reps: 6, duration: 3, encouragementEnabled: true))?.reason.rawValue, "steadyRhythm")
        var jump = rhythmPolicy()
        XCTAssertNil(jump.evaluate(input(reps: 4, duration: 3, encouragementEnabled: true)))
        for stop in [StopReason.form, .failure, .voluntary, .target] {
            var ending = rhythmPolicy()
            XCTAssertNil(ending.evaluate(input(reps: 1, duration: 3, stop: stop, encouragementEnabled: true)))
        }
    }
}


extension CoachingPolicyTests {
    func testFirstResumeSnapshotCannotEncourageAnUnseenRep() {
        var policy = rhythmPolicy()
        XCTAssertNil(policy.evaluate(input(phase: .paused, encouragementEnabled: true)))
        let resumed = UUID()
        XCTAssertNil(policy.evaluate(input(now: 1, reps: 1, duration: 3, generation: resumed, encouragementEnabled: true)))
        XCTAssertNil(policy.evaluate(input(now: 11, reps: 1, duration: 3, generation: resumed, encouragementEnabled: true)))
        XCTAssertEqual(policy.evaluate(input(now: 20, reps: 2, duration: 3, generation: resumed, encouragementEnabled: true))?.reason.rawValue, "steadyRhythm")
    }
}


extension CoachingPolicyTests {
    func testNewSessionAfterPauseCanUseSavedRhythmWithoutReplayingOldSession() {
        var policy = rhythmPolicy()
        XCTAssertNil(policy.evaluate(input(phase: .paused, encouragementEnabled: true)))
        let newSession = UUID()
        XCTAssertEqual(policy.evaluate(input(reps: 1, duration: 3, sessionID: newSession, encouragementEnabled: true))?.reason.rawValue, "steadyRhythm")
        XCTAssertNil(policy.evaluate(input(now: 20, reps: 1, duration: 3, encouragementEnabled: true)))
    }
}

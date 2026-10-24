import XCTest
@testable import Spottr

@MainActor
final class CoachingFlowTests: XCTestCase {
    func testReplayCannotProducePersonalCoachingAndNewSessionUsesCameraSource() {
        let store = TrainingStore()
        store.session.start(at: 0)
        store.source = .video
        store.session.cue = .alignment
        store.coachingTick(at: 10)
        XCTAssertNil(store.coachingEvent)
        store.start()
        XCTAssertEqual(store.source, .camera)
    }

    func testFormEventExpiresAndRetainsItsGenerationForVoiceConsumers() throws {
        let store = TrainingStore()
        store.session.start(at: 0)
        store.session.cue = .alignment

        store.coachingTick(at: 10, wallTime: Date(timeIntervalSince1970: 100))

        let event = try XCTUnwrap(store.coachingEvent)
        XCTAssertEqual(event.generation, store.session.generation)
        XCTAssertEqual(event.sessionID, store.session.id)
        XCTAssertEqual(event.decision.priority, .form)
        XCTAssertEqual(event.decision.reason, .alignment)
        XCTAssertEqual(event.expiresAt, 16)

        store.coachingTick(at: 15, wallTime: Date(timeIntervalSince1970: 105))
        XCTAssertEqual(store.coachingEvent?.id, event.id)
        store.coachingTick(at: 16, wallTime: Date(timeIntervalSince1970: 106))
        XCTAssertNil(store.coachingEvent)
    }

    func testPauseCancellationAndSourceReplacementDiscardVisibleCoaching() {
        let transitions: [(TrainingStore) -> Void] = [
            { $0.pause() },
            { $0.cancelCoaching() },
            { $0.session.restartSet(source: .video, at: 11) },
            { $0.session.finish(at: 11) }
        ]
        for transition in transitions {
            let store = TrainingStore()
            store.session.start(at: 0)
            store.session.cue = .alignment
            store.coachingTick(at: 10)
            XCTAssertNotNil(store.coachingEvent)

            transition(store)

            XCTAssertNil(store.coachingEvent)
        }
    }

    func testReportedDiscomfortImmediatelyReplacesRestCoachingAndPersists() {
        let store = TrainingStore()
        store.session.start(at: 0)
        store.endSet()

        store.feedback(reserve: nil, reason: .discomfort)

        XCTAssertEqual(store.coachingEvent?.decision.priority, .stop)
        XCTAssertEqual(store.coachingEvent?.decision.reason, .discomfort)
        XCTAssertNil(store.coachingEvent?.expiresAt)
        store.coachingTick(at: store.now + 100)
        XCTAssertEqual(store.coachingEvent?.decision.priority, .stop)
        store.session.nextSet(at: store.now + 100)
        XCTAssertEqual(store.session.phase, .finished)
        XCTAssertNil(store.coachingEvent)
    }

    func testCorrectedFormAndNewSetDoNotReplayAnOldInterjection() {
        let store = TrainingStore()
        store.session.start(at: 0)
        store.session.cue = .alignment
        store.coachingTick(at: 10)
        XCTAssertNotNil(store.coachingEvent)

        store.session.cue = .lower
        store.coachingTick(at: 11)
        XCTAssertNil(store.coachingEvent)

        store.session.restartSet(source: .video, at: 12)
        store.coachingTick(at: 12)
        XCTAssertNil(store.coachingEvent)
        store.session.cue = .tracking
        store.coachingTick(at: 13)
        XCTAssertEqual(store.coachingEvent?.decision.reason, .tracking)
        XCTAssertEqual(store.coachingEvent?.generation, store.session.generation)
    }

    func testRestReminderUsesTimeSinceTheSetActuallyEnded() {
        let store = TrainingStore()
        store.session.start(at: 0)
        store.endSet()
        let time = store.now
        let wallTime = Date(timeIntervalSince1970: 100)

        store.coachingTick(at: time + 44, wallTime: wallTime)
        XCTAssertNil(store.coachingEvent)
        store.coachingTick(at: time + 45.1, wallTime: wallTime)
        XCTAssertEqual(store.coachingEvent?.decision.reason, .restReminder)
        XCTAssertEqual(store.coachingEvent?.decision.elapsed ?? 0, 45.1, accuracy: 0.1)
    }

    func testNoRestReminderWithoutAnEndedSetOrFromHeartRateAlone() {
        let store = TrainingStore()
        store.session.start(at: 0)
        let wallTime = Date(timeIntervalSince1970: 100)
        for index in 0..<6 {
            let date = wallTime.addingTimeInterval(Double(index))
            store.session.receiveTelemetry(.init(sessionID: store.session.id, sentAt: date,
                heartRate: .init(value: Double(100 + index * 15), date: date),
                accelerationG: nil, rotationRadiansPerSecond: nil), now: date)
            store.coachingTick(at: Double(index), wallTime: date)
            XCTAssertNil(store.coachingEvent)
        }
        store.session.endSet(at: 6)
        store.coachingTick(at: 100, wallTime: wallTime.addingTimeInterval(100))
        XCTAssertNil(store.coachingEvent)
    }

    func testFormEventCarriesOnlyRecentDistinctObservedHeartRateContext() throws {
        let store = TrainingStore()
        store.session.start(at: 0)
        let first = Date(timeIntervalSince1970: 100)
        for index in 0..<10 {
            let sentAt = first.addingTimeInterval(Double(index))
            let observedIndex = min(index, 4)
            store.session.receiveTelemetry(.init(sessionID: store.session.id, sentAt: sentAt,
                heartRate: .init(value: Double(80 + observedIndex * 10), date: first.addingTimeInterval(Double(observedIndex))),
                accelerationG: nil, rotationRadiansPerSecond: nil), now: sentAt)
        }
        store.session.cue = .alignment

        store.coachingTick(at: 10, wallTime: first.addingTimeInterval(10))

        let facts = try XCTUnwrap(store.coachingEvent).decision.facts
        XCTAssertTrue(facts.contains { $0.contains("120 bpm") })
        XCTAssertTrue(facts.contains { $0.contains("5 unique observations") })
    }

    func testReportedDiscomfortKeepsNextSetBlockedForTheSession() {
        let store = TrainingStore()
        store.session.start(at: 0)
        store.endSet()
        store.feedback(reserve: nil, reason: .discomfort)
        store.feedback(reserve: nil, reason: .voluntary)

        store.next()

        XCTAssertEqual(store.session.phase, .rest)
        XCTAssertEqual(store.coachingEvent?.decision.priority, .stop)
        XCTAssertEqual(store.session.sets.last?.reason, .discomfort)
    }

    func testNewSessionUsesSavedCameraRhythmFromTheFirstObservedRep() {
        let store = TrainingStore()
        let set = SetRecord(id: UUID(), exercise: .squat, number: 1, reps: 5,
            target: 12, activeSeconds: 6, source: .camera, reason: .voluntary,
            repDurations: Array(repeating: 1.2, count: 5))
        store.history = [.init(id: UUID(), date: Date(timeIntervalSince1970: 100), sets: [set])]
        store.start()
        for (time, angle) in [(0.0, 170.0), (0.2, 170), (0.6, 90), (0.8, 90),
                              (1.2, 90), (1.4, 90), (1.8, 170), (2.0, 170)] {
            store.session.consume(.init(time: time, angle: angle), generation: store.session.generation)
        }

        store.coachingTick()

        XCTAssertEqual(store.session.counter.reps, 1)
        XCTAssertEqual(store.coachingEvent?.decision.reason, .slowerRep)
    }

    func testWallClockChangesCannotShortenOrDelayActualRest() {
        let store = TrainingStore()
        store.session.start(at: 0)
        store.endSet()
        let time = store.now
        let wallTime = Date(timeIntervalSince1970: 100)

        store.coachingTick(at: time + 1, wallTime: wallTime.addingTimeInterval(600))
        XCTAssertNil(store.coachingEvent)

        store.coachingTick(at: time + 45.1, wallTime: wallTime)
        XCTAssertEqual(store.coachingEvent?.decision.reason, .restReminder)
        XCTAssertEqual(store.coachingEvent?.decision.elapsed ?? 0, 45.1, accuracy: 0.1)
    }
}

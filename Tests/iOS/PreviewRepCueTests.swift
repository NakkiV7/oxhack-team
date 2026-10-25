import XCTest
@testable import Spottr

@MainActor
final class PreviewRepCueTests: XCTestCase {
    func testPreviewCameraEncouragesEveryTwoFreshRepsWithoutHistoryAndDoesNotRepeatATick() throws {
        for exercise in Exercise.allCases {
            let (store, cached, clock) = makeStore(exercise: exercise)
            defer { store.cancelCoaching() }
            XCTAssertTrue(store.history.isEmpty)
            completeRep(0, store: store, clock: clock)
            XCTAssertTrue(cached.spoken.isEmpty)
            completeRep(1, store: store, clock: clock)
            let first = try XCTUnwrap(cached.spoken.last)
            XCTAssertEqual(first.reason, .steadyRhythm)
            XCTAssertEqual(first.kind, .coaching(.pacing))
            XCTAssertEqual(first.sessionID, store.session.id)
            XCTAssertEqual(first.generation, store.session.generation)
            store.coachingTick(at: clock.now)
            XCTAssertEqual(cached.spoken.count, 1)
            cached.onFinish?(first.id)
            completeRep(2, store: store, clock: clock)
            XCTAssertEqual(cached.spoken.count, 1)
            completeRep(3, store: store, clock: clock)
            XCTAssertEqual(cached.spoken.count, 2)
            XCTAssertEqual(cached.spoken.last?.reason, .steadyRhythm)
            XCTAssertNotEqual(cached.spoken.last?.id, first.id, "A new cue allows the cached bank to choose its next variant")
            XCTAssertEqual(store.session.counter.reps, 4)
            XCTAssertTrue(store.history.isEmpty, "Encouragement cannot create completed work")
        }
    }

    func testNormalModeAndVideoCannotUseThePreviewRepShortcut() {
        for scenario in ["normal", "video"] {
            let (store, cached, clock) = makeStore(preview: scenario != "normal")
            defer { store.cancelCoaching() }
            if scenario == "video" {
                store.source = .video
                store.session.restartSet(source: .video, at: 0)
            }
            for index in 0..<4 { completeRep(index, store: store, clock: clock) }
            XCTAssertEqual(store.session.counter.reps, 4)
            XCTAssertTrue(cached.spoken.isEmpty, scenario)
            XCTAssertNotEqual(store.coachingEvent?.decision.reason, .steadyRhythm, scenario)
        }
    }

    func testMutedRepsCannotCatchUpWhenVoiceIsEnabledAgain() {
        let (store, cached, clock) = makeStore()
        defer { store.cancelCoaching() }
        store.setVoiceFeedback(false)
        completeRep(0, store: store, clock: clock)
        completeRep(1, store: store, clock: clock)
        store.setVoiceFeedback(true)
        store.coachingTick(at: clock.now)
        XCTAssertTrue(cached.spoken.isEmpty)
        completeRep(2, store: store, clock: clock)
        XCTAssertTrue(cached.spoken.isEmpty)
        completeRep(3, store: store, clock: clock)
        XCTAssertEqual(cached.spoken.map(\.reason), [.steadyRhythm])
    }

    func testPauseBackgroundAndOldGenerationCannotAnnounceOrReplayARep() {
        for scenario in ["pause", "background", "stale"] {
            let (store, cached, clock) = makeStore()
            defer { store.cancelCoaching() }
            completeRep(0, store: store, clock: clock)
            let oldGeneration = store.session.generation
            if scenario == "background" { store.setAppActive(false) }
            else { store.pause() }
            if scenario == "stale" { store.resume() }
            completeRep(1, store: store, clock: clock, generation: oldGeneration)
            XCTAssertEqual(store.session.counter.reps, 1)
            XCTAssertTrue(cached.spoken.isEmpty, scenario)
            if scenario == "background" { store.setAppActive(true) }
            if scenario != "stale" { store.resume() }
            store.coachingTick(at: clock.now)
            XCTAssertTrue(cached.spoken.isEmpty, "Returning to active state cannot replay paused or stale work")
        }
    }

    func testTrackingAndAlignmentWinOverAnEligibleSecondRepAndCannotReplayItLater() {
        for cue in [Cue.tracking, .alignment] {
            let (store, cached, clock) = makeStore()
            defer { store.cancelCoaching() }
            completeRep(0, store: store, clock: clock)
            completeRep(1, store: store, clock: clock, tick: false)
            store.session.cue = cue
            store.coachingTick(at: clock.now)
            XCTAssertEqual(store.coachingEvent?.decision.priority, .form)
            XCTAssertEqual(cached.spoken.last?.kind, .coaching(.form))
            XCTAssertFalse(cached.spoken.contains { $0.reason == .steadyRhythm })
            store.session.cue = .controlled
            store.coachingTick(at: clock.now + 1)
            XCTAssertFalse(cached.spoken.contains { $0.reason == .steadyRhythm }, "Clearing a form cue is not a new rep")
        }
    }

    func testDiscomfortStopsEncouragementAndRepeatedTicksDoNotReplaceTheStopCue() {
        let (store, cached, clock) = makeStore()
        defer { store.cancelCoaching() }
        completeRep(0, store: store, clock: clock)
        store.endSet()
        store.feedback(reserve: nil, reason: .discomfort)
        XCTAssertEqual(store.coachingEvent?.decision.reason, .discomfort)
        XCTAssertEqual(store.coachingEvent?.decision.priority, .stop)
        store.coachingTick(at: store.now + 1)
        XCTAssertEqual(store.coachingEvent?.decision.reason, .discomfort)
        XCTAssertFalse(cached.spoken.contains { $0.reason == .steadyRhythm })
    }

    private func makeStore(preview: Bool = true, exercise: Exercise = .squat) -> (TrainingStore, RepRecordingVoice, RepCueClock) {
        let clock = RepCueClock(), cached = RepRecordingVoice()
        let remote = RemoteVoicePlayback(local: RepRecordingVoice(), previewPlayback: cached, client: {
            XCTFail("Rep encouragement must use the cache without a provider request")
            throw RemoteVoiceError.configuration
        }, uptime: { clock.now })
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("history.json")
        let store = TrainingStore(historyURL: url, voicePlayback: remote, previewMode: preview, previewPlayback: cached)
        store.selectedExercise = exercise
        store.start()
        store.hasInput = true
        store.setVoiceFeedback(true)
        return (store, cached, clock)
    }

    private func completeRep(_ index: Int, store: TrainingStore, clock: RepCueClock, generation: UUID? = nil, tick: Bool = true) {
        let base = Double(index) * 2.2
        for (offset, angle) in [(0.0, 170.0), (0.2, 170), (0.6, 90), (0.8, 90),
                                (1.2, 90), (1.4, 90), (1.8, 170), (2.0, 170)] {
            store.session.consume(.init(time: base + offset, angle: angle), generation: generation ?? store.session.generation)
        }
        clock.now = 100 + base + 2
        if tick { store.coachingTick(at: clock.now) }
    }
}

@MainActor private final class RepCueClock { var now = 100.0 }

@MainActor private final class RepRecordingVoice: VoicePlayback {
    var onFinish: ((UUID) -> Void)?
    var spoken: [VoiceCue] = []
    func speak(_ cue: VoiceCue) { spoken.append(cue) }
    func stop() {}
}

import XCTest
@testable import Spottr

@MainActor
final class VoiceFeedbackTests: XCTestCase {
    func testEndingSetPreservesOrdinarySentenceAndFinishingWaitsForActualCompletion() throws {
        let playback = FakeVoicePlayback()
        let store = TrainingStore(voicePlayback: playback)
        store.repVoice.coach = nil
        defer { store.cancelCoaching() }
        store.start(); store.setVoiceFeedback(true)
        store.session.cue = .alignment
        store.coachingTick()
        let first = try XCTUnwrap(playback.spoken.first)
        store.endSet(); store.coachingTick()
        XCTAssertEqual(playback.stops, 0)
        store.finish(); store.coachingTick()
        XCTAssertEqual(playback.stops, 0)
        playback.onFinish?(first.id)
    }

    func testDismissingTheSessionCancelsSpeechImmediatelyAndNeverReplaysIt() {
        let playback = FakeVoicePlayback()
        let store = TrainingStore(voicePlayback: playback)
        store.repVoice.coach = nil
        store.start(); store.setVoiceFeedback(true)
        store.session.cue = .alignment; store.coachingTick()
        XCTAssertEqual(playback.spoken.count, 1)
        store.presented = false
        XCTAssertEqual(playback.stops, 1)
        store.presented = true; store.coachingTick()
        XCTAssertEqual(playback.spoken.count, 1)
        store.cancelCoaching()
    }

    func testRepHandoffRechecksCompletionFreshnessAndDropsCancelledCallbacks() {
        for action in ["fresh", "expired", "cancelled"] {
            var clock = 0.0
            let playback = FakeVoicePlayback(), clips = RepClipRecorder()
            let rep = RepVoicePlayer(defaults: UserDefaults(suiteName: UUID().uuidString)!, uptime: { clock }, makeOutput: clips.make)
            let bridge = CoachingVoiceBridge(playback: playback, uptime: { clock })
            bridge.repVoice = rep
            rep.start()
            let sessionID = UUID(), generation = UUID()
            let event = CoachingEvent(sessionID: sessionID, generation: generation,
                decision: .init(text: "Completed.", priority: .rest, reason: .workoutCompleted, facts: [], elapsed: nil),
                issuedAt: 0, expiresAt: 6)
            bridge.update(context: .init(sessionID: sessionID, generation: generation, phase: .finished),
                          event: event, enabled: true, now: clock)
            XCTAssertTrue(playback.spoken.isEmpty)
            if action == "cancelled" { bridge.cancel(); rep.cancel() }
            clock = action == "expired" ? 7 : 2
            clips.finish()
            XCTAssertEqual(playback.spoken.map(\.reason), action == "fresh" ? [.workoutCompleted] : [])
            bridge.cancel(); rep.cancel()
        }
    }

    func testVisibilityPromptFinishesThenRepeatsOnlyIfBodyIsStillMissing() throws {
        let playback = FakeVoicePlayback()
        let store = TrainingStore(voicePlayback: playback)
        store.repVoice.coach = nil
        store.session.start(at: 0)
        store.setVoiceFeedback(true)
        store.session.cue = .tracking
        store.coachingTick(at: 10)
        XCTAssertTrue(playback.spoken.isEmpty, "Brief pose flicker must not immediately speak")
        store.coachingTick(at: 10.8)
        let first = try XCTUnwrap(playback.spoken.first)
        store.session.cue = .lower
        store.coachingTick(at: 11)
        XCTAssertEqual(playback.stops, 0)
        store.session.cue = .tracking
        store.coachingTick(at: 11.2)
        store.coachingTick(at: 12.2)
        XCTAssertEqual(playback.spoken.count, 1)
        playback.onFinish?(first.id)
        store.coachingTick(at: 13)
        XCTAssertEqual(playback.spoken.count, 2, "Reassess current tracking after the recording finishes")
        store.session.cue = .lower
        store.coachingTick(at: 13.2)
        XCTAssertEqual(playback.stops, 0)
        playback.onFinish?(playback.spoken[1].id)
        store.coachingTick(at: 14)
        XCTAssertEqual(playback.spoken.count, 2, "Recovery must prevent another visibility prompt")
    }

    func testSubsecondTrackingFlickerDoesNotSpeak() {
        let playback = FakeVoicePlayback()
        let store = TrainingStore(voicePlayback: playback)
        store.repVoice.coach = nil
        store.session.start(at: 0)
        store.setVoiceFeedback(true)
        for start in [10.0, 11, 12] {
            store.session.cue = .tracking; store.coachingTick(at: start)
            store.session.cue = .lower; store.coachingTick(at: start + 0.3)
        }
        XCTAssertTrue(playback.spoken.isEmpty)
    }

    func testAppOwnsOfflineArnoldAndPreservesInjectedPlayback() {
        let store = TrainingStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        XCTAssertEqual(store.remoteVoice?.preference, .maya)
        XCTAssertFalse(store.voiceFeedbackEnabled)
        XCTAssertEqual(store.remoteVoice?.configuredVoices, [.maya, .leo, .local, .arnold, .david])

        let remote = RemoteVoicePlayback(local: FakeVoicePlayback(), client: {
            XCTFail("Creating a workout must not contact a voice provider")
            throw RemoteVoiceError.configuration
        })
        let injected = TrainingStore(voicePlayback: remote)
        XCTAssertTrue(injected.remoteVoice === remote)
        injected.start()
        XCTAssertTrue(injected.remoteVoice === remote)
        XCTAssertFalse(injected.voiceFeedbackEnabled)

        let fake = FakeVoicePlayback()
        XCTAssertNil(TrainingStore(voicePlayback: fake).remoteVoice,
                     "An injected test playback must not be replaced by a second voice engine")
    }

    func testVoiceDefaultsOffAndEnablingDoesNotReplayExistingCue() {
        let playback = FakeVoicePlayback()
        let store = TrainingStore(voicePlayback: playback)
        store.session.start(at: 0)
        store.session.cue = .alignment
        store.coachingTick(at: 10)
        XCTAssertFalse(store.voiceFeedbackEnabled)
        XCTAssertTrue(playback.spoken.isEmpty)

        store.setVoiceFeedback(true)
        XCTAssertTrue(playback.spoken.isEmpty)
        store.session.cue = .lower
        store.coachingTick(at: 11)
        store.session.cue = .tracking
        store.coachingTick(at: 12)
        store.coachingTick(at: 12.8)
        XCTAssertEqual(playback.spoken.map(\.text), [Cue.tracking.text])
    }

    func testMutePauseAndCancellationStopSpeechImmediately() {
        let transitions: [(TrainingStore) -> Void] = [
            { $0.setVoiceFeedback(false) }, { $0.pause() }, { $0.cancelCoaching() }
        ]
        for transition in transitions {
            let playback = FakeVoicePlayback()
            let store = TrainingStore(voicePlayback: playback)
            store.session.start(at: 0)
            store.setVoiceFeedback(true)
            store.session.cue = .alignment
            store.coachingTick(at: 10)
            XCTAssertEqual(playback.spoken.count, 1)
            transition(store)
            XCTAssertEqual(playback.stops, 1)
        }
    }

    func testManualFallbackStopsSpeechAndCannotGenerateOrReplayCameraCoaching() {
        let playback = FakeVoicePlayback()
        let store = TrainingStore(voicePlayback: playback)
        store.session.start(at: 0)
        store.setVoiceFeedback(true)
        store.session.cue = .alignment
        store.coachingTick(at: 10)
        XCTAssertEqual(playback.spoken.count, 1)

        store.switchToManualReps()

        XCTAssertEqual(playback.stops, 1)
        XCTAssertNil(store.coachingEvent)
        store.session.cue = .tracking
        store.coachingTick(at: 11)
        XCTAssertNil(store.coachingEvent)
        XCTAssertEqual(playback.spoken.count, 1)
    }

    func testStartingAnotherWorkoutResetsVoiceAndVideoDoesNotSpeakPersonalCues() {
        let playback = FakeVoicePlayback()
        let store = TrainingStore(voicePlayback: playback)
        store.session.start(at: 0)
        store.setVoiceFeedback(true)
        store.source = .video
        store.session.cue = .alignment
        store.coachingTick(at: 10)
        XCTAssertTrue(playback.spoken.isEmpty)
        store.start()
        XCTAssertTrue(store.voiceFeedbackEnabled)
    }

    func testLeavingForegroundCancelsRestSpeechWithoutStoppingRestClockOrReplayingOnReturn() {
        let playback = FakeVoicePlayback()
        let store = TrainingStore(voicePlayback: playback)
        store.session.start(at: 0)
        store.setVoiceFeedback(true)
        store.endSet()
        let restStart = store.now
        store.coachingTick(at: restStart + 45.1)
        XCTAssertEqual(playback.spoken.count, 1)
        XCTAssertEqual(store.coachingEvent?.decision.priority, .rest)

        store.setAppActive(false)
        XCTAssertEqual(playback.stops, 1)
        XCTAssertNil(store.coachingEvent)
        store.coachingTick(at: restStart + 60)
        XCTAssertNil(store.coachingEvent)
        XCTAssertEqual(store.sessionPhase, .rest)
        XCTAssertGreaterThanOrEqual(store.actualRestElapsed(at: restStart + 60) ?? 0, 60)

        store.setAppActive(true)
        store.coachingTick(at: restStart + 61)
        XCTAssertNil(store.coachingEvent)
        XCTAssertEqual(playback.spoken.count, 1)
    }

    func testBackgroundTicksCannotIssueNewRestCoachingAndForegroundAloneNeverSpeaks() {
        let playback = FakeVoicePlayback()
        let store = TrainingStore(voicePlayback: playback)
        store.session.start(at: 0)
        store.setVoiceFeedback(true)
        store.endSet()
        let restStart = store.now
        store.setAppActive(false)
        store.coachingTick(at: restStart + 45.1)
        store.coachingTick(at: restStart + 60)
        XCTAssertNil(store.coachingEvent)
        XCTAssertTrue(playback.spoken.isEmpty)
        store.setAppActive(true)
        XCTAssertTrue(playback.spoken.isEmpty)
    }
}

@MainActor
private final class FakeVoicePlayback: VoicePlayback {
    var onFinish: ((UUID) -> Void)?
    var spoken: [VoiceCue] = []
    var stops = 0
    func speak(_ cue: VoiceCue) { spoken.append(cue) }
    func stop() { stops += 1 }
}

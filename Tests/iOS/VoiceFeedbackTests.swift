import XCTest
@testable import Spottr

@MainActor
final class VoiceFeedbackTests: XCTestCase {
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
        XCTAssertFalse(store.voiceFeedbackEnabled)
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

import XCTest
@testable import Spottr

@MainActor
final class VoiceFeedbackTests: XCTestCase {
    func testSpokenManualPauseResumeKeepsCameraAcknowledgementPending() async throws {
        let spoken = RecoverySpokenRepInput()
        let vision = VisionWorker(cameraAvailable: { true }, requestAccess: { _ in })
        let store = TrainingStore(voicePlayback: FakeVoicePlayback(), vision: vision, spokenReps: spoken)
        store.repVoice.coach = nil; store.beginAuthorizedSession(); store.hasInput = true
        defer { store.finish(); store.cancelCoaching(); vision.stop() }
        vision.onFrame?(.init(time: 1, width: 640, height: 480, points: [], observation: .multiplePeople), UIImage(), store.session.generation)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(store.session.cameraRecoveryState, .needsResume)
        store.switchToManualReps(); store.startSpokenReps()
        XCTAssertTrue(spoken.isListening)
        spoken.onCount?(4)
        XCTAssertEqual(store.session.actualReps, 4)
        store.pause(); store.resume(); store.camera()
        XCTAssertEqual(store.session.cameraRecoveryState, .needsResume)
        XCTAssertEqual(store.session.actualReps, 4)
        for time in stride(from: 2.0, through: 5.0, by: 0.1) {
            store.session.consume(.init(time: time, angle: 170), generation: store.session.generation)
        }
        XCTAssertEqual(store.session.cameraRecoveryState, .needsResume)
        store.resume()
        XCTAssertEqual(store.session.cameraRecoveryState, .waitingForClear)
        XCTAssertEqual(store.session.actualReps, 4)
    }

    func testAmbiguitySuspendsOnlyCameraCountingAndExplicitResumeRenewsCapture() async throws {
        let playback = FakeVoicePlayback()
        let vision = VisionWorker(cameraAvailable: { true }, requestAccess: { _ in })
        let store = TrainingStore(voicePlayback: playback, vision: vision)
        store.repVoice.coach = nil
        store.beginAuthorizedSession(); store.hasInput = true; store.setVoiceFeedback(true)
        store.session.cue = .alignment; store.coachingTick()
        XCTAssertEqual(playback.spoken.count, 1)
        let generation = store.session.generation
        vision.onFrame?(.init(time: 1, width: 640, height: 480, points: [], observation: .multiplePeople), UIImage(), generation)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(store.session.cameraRecoveryState, .needsResume)
        XCTAssertEqual(store.session.phase, .active)
        XCTAssertEqual(playback.stops, 0)
        let speaking = try XCTUnwrap(playback.spoken.first)
        store.resume(); store.coachingTick()
        XCTAssertEqual(playback.stops, 0, "A same-camera recovery tick must let the ordinary sentence finish")
        XCTAssertEqual(playback.spoken.count, 1)
        XCTAssertNotEqual(store.session.generation, generation)
        XCTAssertEqual(store.session.cameraRecoveryState, .waitingForClear)
        vision.onFrame?(.init(time: 2, width: 640, height: 480, points: [], observation: .multiplePeople), UIImage(), generation)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(store.session.cameraRecoveryState, .waitingForClear)
        XCTAssertEqual(playback.stops, 0)
        playback.onFinish?(speaking.id); store.coachingTick()
        XCTAssertEqual(playback.spoken.count, 1, "Recovery must not replay an intro or old queued cue")
        store.finish(); store.cancelCoaching(); vision.stop()
    }

    func testSameCameraRecoveryDoesNotReplayTheRepSetIntro() async throws {
        let playback=FakeVoicePlayback(), clips=RepClipRecorder()
        let vision=VisionWorker(cameraAvailable:{true},requestAccess:{_ in})
        let store=TrainingStore(voicePlayback:playback,vision:vision)
        store.repVoice=RepVoicePlayer(defaults:UserDefaults(suiteName:UUID().uuidString)!,makeOutput:clips.make)
        store.beginAuthorizedSession(); store.hasInput=true; store.setVoiceFeedback(true); store.coachingTick()
        XCTAssertFalse(store.repVoice.started.isEmpty)
        clips.finish()
        let started=store.repVoice.started, generation=store.session.generation
        vision.onFrame?(.init(time:1,width:640,height:480,points:[],observation:.multiplePeople),UIImage(),generation)
        for _ in 0..<20 { await Task.yield() }
        store.resume(); store.coachingTick()
        if let ordinary=playback.spoken.first { playback.onFinish?(ordinary.id) }
        store.coachingTick()
        XCTAssertEqual(store.repVoice.started,started)
        store.finish(); store.cancelCoaching(); vision.stop()
    }

    func testEndingSetPreservesOrdinarySentenceAndFinishingWaitsForActualCompletion() throws {
        let playback = FakeVoicePlayback()
        let store = TrainingStore(voicePlayback: playback)
        store.repVoice.coach = nil
        defer { store.cancelCoaching() }
        store.beginAuthorizedSession(); store.setVoiceFeedback(true)
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
        store.beginAuthorizedSession(); store.setVoiceFeedback(true)
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
        injected.beginAuthorizedSession()
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
        store.beginAuthorizedSession()
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

@MainActor private final class RecoverySpokenRepInput: SpokenRepListening {
    var isListening = false
    var message: String?
    var onCount: (@MainActor (Int) -> Void)?
    func start(initialCount: Int, onCount: @escaping @MainActor (Int) -> Void) {
        self.onCount = onCount; isListening = true
    }
    func stop() { isListening = false }
}

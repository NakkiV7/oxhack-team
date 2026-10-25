import XCTest
@testable import Spottr

@MainActor
final class PreviewVoiceIntegrationTests: XCTestCase {
    private func historyURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("history.json")
    }

    func testPreviewStoreOwnsArnoldCacheButFeedbackStaysOffUntilAFreshFormCue() throws {
        let cached = PreviewRecordingVoice()
        let store = TrainingStore(historyURL: historyURL(), previewMode: true, previewPlayback: cached)
        defer { store.cancelCoaching() }
        let remote = try XCTUnwrap(store.remoteVoice)
        XCTAssertEqual(remote.preference, .arnold)
        XCTAssertEqual(remote.configuredVoices, [.arnold])
        XCTAssertFalse(store.voiceFeedbackEnabled)
        store.start()
        XCTAssertTrue(store.remoteVoice === remote)
        XCTAssertFalse(store.voiceFeedbackEnabled)
        store.session.cue = .alignment
        store.coachingTick()
        XCTAssertTrue(cached.spoken.isEmpty)
        store.setVoiceFeedback(true)
        XCTAssertTrue(cached.spoken.isEmpty, "Opt-in cannot replay an existing event")
        store.session.cue = .lower
        store.coachingTick()
        store.session.cue = .tracking
        store.coachingTick()
        let spoken = try XCTUnwrap(cached.spoken.last)
        XCTAssertEqual(cached.spoken.count, 1)
        XCTAssertEqual(spoken.sessionID, store.session.id)
        XCTAssertEqual(spoken.generation, store.session.generation)
        XCTAssertEqual(spoken.kind, .coaching(.form))
        XCTAssertEqual(spoken.reason, .tracking)

        let normal = TrainingStore(historyURL: historyURL(), previewMode: false, previewPlayback: PreviewRecordingVoice())
        XCTAssertEqual(normal.remoteVoice?.preference, .local)
        XCTAssertFalse(normal.voiceFeedbackEnabled)
    }

    func testActualStorePolicyAndBridgeSendObservedPacingToInjectedCacheWithoutHTTP() async throws {
        let cached = PreviewRecordingVoice()
        var gatewayAttempts = 0
        let remote = RemoteVoicePlayback(local: PreviewRecordingVoice(), previewPlayback: cached, client: {
            gatewayAttempts += 1
            XCTFail("Preview store must not discover or synthesize through HTTP")
            throw RemoteVoiceError.configuration
        })
        let store = TrainingStore(historyURL: historyURL(), voicePlayback: remote,
                                  previewMode: true, previewPlayback: cached)
        defer { store.cancelCoaching() }
        XCTAssertTrue(store.remoteVoice === remote)
        let baseline = SetRecord(id: UUID(), exercise: .squat, number: 1, reps: 5,
            target: 12, activeSeconds: 6, source: .camera, reason: .voluntary,
            repDurations: Array(repeating: 1.2, count: 5))
        store.history = [.init(id: UUID(), date: Date(timeIntervalSince1970: 100), sets: [baseline])]
        store.start()
        store.setVoiceFeedback(true)
        // Synthetic observed movement samples use the same public counter flow as existing coaching tests.
        for (time, angle) in [(0.0, 170.0), (0.2, 170), (0.6, 90), (0.8, 90),
                              (1.2, 90), (1.4, 90), (1.8, 170), (2.0, 170)] {
            store.session.consume(.init(time: time, angle: angle), generation: store.session.generation)
        }
        store.coachingTick()
        XCTAssertEqual(store.session.counter.reps, 1)
        XCTAssertEqual(store.coachingEvent?.decision.reason, .slowerRep)
        XCTAssertEqual(cached.spoken.count, 1)
        XCTAssertEqual(cached.spoken.first?.kind, .coaching(.pacing))
        XCTAssertEqual(cached.spoken.first?.reason, .slowerRep)
        try await remote.refreshVoices()
        XCTAssertEqual(gatewayAttempts, 0)
    }

    func testStoreMutePauseAndBackgroundCancelCachedSpeechWithoutReplayingIt() throws {
        let transitions: [(TrainingStore) -> Void] = [
            { $0.setVoiceFeedback(false) }, { $0.pause() }, { $0.setAppActive(false) }
        ]
        for transition in transitions {
            let cached = PreviewRecordingVoice()
            let store = TrainingStore(historyURL: historyURL(), previewMode: true, previewPlayback: cached)
            defer { store.cancelCoaching() }
            store.start()
            store.setVoiceFeedback(true)
            store.session.cue = .alignment
            store.coachingTick()
            XCTAssertEqual(cached.spoken.count, 1)
            transition(store)
            XCTAssertEqual(cached.stops, 1)
            store.coachingTick()
            XCTAssertEqual(cached.spoken.count, 1)
        }
    }
}

@MainActor
private final class PreviewRecordingVoice: VoicePlayback {
    var onFinish: ((UUID) -> Void)?
    var spoken: [VoiceCue] = []
    var stops = 0
    func speak(_ cue: VoiceCue) { spoken.append(cue) }
    func stop() { stops += 1 }
}

import XCTest
@testable import SpottrCore

@MainActor
final class VoiceCuePlaybackTests: XCTestCase {
    private let sessionID = UUID()
    private let generation = UUID()

    private func cue(_ kind: VoiceCue.Kind = .coaching(.pacing), issuedAt: Double = 0, expiresAt: Double? = 6,
                     sessionID: UUID? = nil, generation: UUID? = nil) -> VoiceCue {
        .init(id: UUID(), sessionID: sessionID ?? self.sessionID, generation: generation ?? self.generation,
              text: "Keep control.", kind: kind, issuedAt: issuedAt, expiresAt: expiresAt)
    }
    private func context(_ phase: SessionPhase = .active, sessionID: UUID? = nil, generation: UUID? = nil) -> VoiceCueContext {
        .init(sessionID: sessionID ?? self.sessionID, generation: generation ?? self.generation, phase: phase)
    }

    func testStopInterruptsPacingImmediatelyAndDuplicateEventsNeverReplay() {
        let playback = RecordingVoicePlayback()
        let controller = VoiceCuePlaybackController(playback: playback)
        let pacing = cue(), stop = cue(.coaching(.stop), issuedAt: 1, expiresAt: nil)
        controller.update(context: context(), event: pacing, enabled: true, now: 0)
        controller.update(context: context(), event: pacing, enabled: true, now: 0.5)
        controller.update(context: context(), event: stop, enabled: true, now: 1)
        XCTAssertEqual(playback.events, [.speak(pacing.id), .stop, .speak(stop.id)])
        playback.onFinish?(stop.id)
        controller.update(context: context(), event: stop, enabled: true, now: 2)
        XCTAssertEqual(playback.events.count, 3)
    }

    func testChatCannotInterruptCoachingAndIsNeverQueuedButFormCanReplacePacing() {
        let playback = RecordingVoicePlayback()
        let controller = VoiceCuePlaybackController(playback: playback)
        let pacing = cue(), chat = cue(.chat), form = cue(.coaching(.form))
        controller.update(context: context(), event: pacing, enabled: true, now: 0)
        controller.update(context: context(), event: chat, enabled: true, now: 1)
        XCTAssertEqual(playback.events, [.speak(pacing.id)])
        controller.update(context: context(), event: form, enabled: true, now: 2)
        playback.onFinish?(form.id)
        controller.update(context: context(), event: chat, enabled: true, now: 3)
        XCTAssertEqual(playback.events, [.speak(pacing.id), .stop, .speak(form.id)])
    }

    func testExpiredCuesDoNotStartAndActiveCueStopsAtItsDeadline() {
        let playback = RecordingVoicePlayback()
        let controller = VoiceCuePlaybackController(playback: playback)
        controller.update(context: context(), event: cue(expiresAt: 1), enabled: true, now: 1)
        XCTAssertTrue(playback.events.isEmpty)
        let current = cue(expiresAt: 3)
        controller.update(context: context(), event: current, enabled: true, now: 1)
        controller.update(context: context(), event: current, enabled: true, now: 3)
        XCTAssertEqual(playback.events, [.speak(current.id), .stop])
    }

    func testMuteConsumesEventsAndEnablingSpeaksOnlyNewEvents() {
        let playback = RecordingVoicePlayback()
        let controller = VoiceCuePlaybackController(playback: playback)
        let muted = cue(), fresh = cue(issuedAt: 2)
        controller.update(context: context(), event: muted, enabled: false, now: 0)
        controller.update(context: context(), event: muted, enabled: true, now: 1)
        XCTAssertTrue(playback.events.isEmpty)
        controller.update(context: context(), event: fresh, enabled: true, now: 2)
        controller.update(context: context(), event: fresh, enabled: false, now: 3)
        controller.update(context: context(), event: fresh, enabled: true, now: 4)
        XCTAssertEqual(playback.events, [.speak(fresh.id), .stop])
    }

    func testCancelAndInactivePhasesStopWithoutReplayingEvent() {
        for phase in [SessionPhase.paused, .idle, .finished] {
            let playback = RecordingVoicePlayback()
            let controller = VoiceCuePlaybackController(playback: playback)
            let event = cue()
            controller.update(context: context(), event: event, enabled: true, now: 0)
            controller.update(context: context(phase), event: event, enabled: true, now: 1)
            controller.update(context: context(), event: event, enabled: true, now: 2)
            XCTAssertEqual(playback.events, [.speak(event.id), .stop])
        }
        let playback = RecordingVoicePlayback()
        let controller = VoiceCuePlaybackController(playback: playback)
        let event = cue()
        controller.update(context: context(), event: event, enabled: true, now: 0)
        controller.cancel()
        controller.update(context: context(), event: event, enabled: true, now: 1)
        XCTAssertEqual(playback.events, [.speak(event.id), .stop])
    }

    func testSessionAndGenerationChangesStopOldSpeechAndRejectStaleEvents() {
        for changedContext in [context(sessionID: UUID()), context(generation: UUID())] {
            let playback = RecordingVoicePlayback()
            let controller = VoiceCuePlaybackController(playback: playback)
            let old = cue()
            controller.update(context: context(), event: old, enabled: true, now: 0)
            controller.update(context: changedContext, event: old, enabled: true, now: 1)
            XCTAssertEqual(playback.events, [.speak(old.id), .stop])
        }
    }

    func testLateCompletionCannotClearNewCueAndNilEventCancelsSpeech() {
        let playback = RecordingVoicePlayback()
        let controller = VoiceCuePlaybackController(playback: playback)
        let old = cue(), stop = cue(.coaching(.stop), expiresAt: nil)
        controller.update(context: context(), event: old, enabled: true, now: 0)
        controller.update(context: context(), event: stop, enabled: true, now: 1)
        playback.onFinish?(old.id)
        controller.update(context: context(), event: cue(.chat), enabled: true, now: 2)
        controller.update(context: context(), event: nil, enabled: true, now: 3)
        XCTAssertEqual(playback.events, [.speak(old.id), .stop, .speak(stop.id), .stop])
    }

    func testWorkoutCompletionSpeaksOnceOnlyInFinishedPhaseAndOrdinaryCuesStaySilent() {
        let playback = RecordingVoicePlayback()
        let controller = VoiceCuePlaybackController(playback: playback)
        let completion = VoiceCue(id: UUID(), sessionID: sessionID, generation: generation,
            text: "We'll be back.", kind: .coaching(.rest), issuedAt: 0, expiresAt: 6, reason: .workoutCompleted)
        controller.update(context: context(.finished), event: completion, enabled: true, now: 1)
        controller.update(context: context(.finished), event: completion, enabled: true, now: 2)
        XCTAssertEqual(playback.events, [.speak(completion.id)])
        controller.update(context: context(.finished), event: cue(), enabled: true, now: 2)
        XCTAssertEqual(playback.events, [.speak(completion.id), .stop])
        for phase in [SessionPhase.idle, .active, .rest, .paused] {
            let wrongPhasePlayback = RecordingVoicePlayback()
            let wrongPhaseController = VoiceCuePlaybackController(playback: wrongPhasePlayback)
            wrongPhaseController.update(context: context(phase), event: completion, enabled: true, now: 1)
            XCTAssertTrue(wrongPhasePlayback.events.isEmpty)
        }
    }

    func testCompletionReplacesOrdinaryAudioButCannotCutOffAnActiveStop() {
        for kind in [VoiceCue.Kind.coaching(.pacing), .coaching(.stop)] {
            let playback = RecordingVoicePlayback()
            let controller = VoiceCuePlaybackController(playback: playback)
            let ordinary = cue(kind, expiresAt: kind == .coaching(.stop) ? nil : 6)
            controller.update(context: context(), event: ordinary, enabled: true, now: 0)
            let completion = VoiceCue(id: UUID(), sessionID: sessionID, generation: generation,
                text: "We'll be back.", kind: .coaching(.rest), issuedAt: 1, expiresAt: 6, reason: .workoutCompleted)
            controller.update(context: context(.finished), event: completion, enabled: true, now: 1)
            let expected: [RecordingVoicePlayback.Event] = kind == .coaching(.stop)
                ? [.speak(ordinary.id)] : [.speak(ordinary.id), .stop, .speak(completion.id)]
            XCTAssertEqual(playback.events, expected)
        }
    }

    func testMutedExpiredAndWrongPriorityCompletionNeverSpeaksOrReplays() {
        for (priority, expiry, enabled) in [(CoachingPriority.rest, 6.0, false), (.rest, 1, true), (.pacing, 6, true), (.stop, 6, true)] {
            let playback = RecordingVoicePlayback()
            let controller = VoiceCuePlaybackController(playback: playback)
            let completion = VoiceCue(id: UUID(), sessionID: sessionID, generation: generation,
                text: "We'll be back.", kind: .coaching(priority), issuedAt: 0, expiresAt: expiry, reason: .workoutCompleted)
            controller.update(context: context(.finished), event: completion, enabled: enabled, now: 1)
            controller.update(context: context(.finished), event: completion, enabled: true, now: 2)
            XCTAssertTrue(playback.events.isEmpty)
        }
    }

    func testInvalidTextAndTimeNeverReachPlayback() {
        let playback = RecordingVoicePlayback()
        let controller = VoiceCuePlaybackController(playback: playback)
        let cases: [(String, Double, Double?, Double)] = [
            ("  \n", 0, 6, 0), (String(repeating: "a", count: 501), 0, 6, 0),
            ("Cue", .nan, 6, 0), ("Cue", 1, 6, 0), ("Cue", 0, .infinity, 0),
            ("Cue", 0, nil, 0), ("Cue", 0, 6, .nan)
        ]
        for (text, issuedAt, expiresAt, now) in cases {
            controller.update(context: context(), event: .init(id: UUID(), sessionID: sessionID,
                generation: generation, text: text, kind: .coaching(.form), issuedAt: issuedAt,
                expiresAt: expiresAt), enabled: true, now: now)
        }
        XCTAssertTrue(playback.events.isEmpty)
    }
}

@MainActor
private final class RecordingVoicePlayback: VoicePlayback {
    enum Event: Equatable { case speak(UUID), stop }
    var onFinish: ((UUID) -> Void)?
    var events: [Event] = []
    func speak(_ cue: VoiceCue) { events.append(.speak(cue.id)) }
    func stop() { events.append(.stop) }
}

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

    func testStartedVisibilityPromptFinishesDespiteRecoveryReplacementAndExpiry() {
        let playback = RecordingVoicePlayback()
        let controller = VoiceCuePlaybackController(playback: playback)
        let visibility = VoiceCue(id: UUID(), sessionID: sessionID, generation: generation,
            text: "Keep your whole body visible.", kind: .coaching(.form), issuedAt: 0, expiresAt: 1, reason: .tracking)
        controller.update(context: context(), event: visibility, enabled: true, now: 0)
        controller.update(context: context(), event: nil, enabled: true, now: 0.2)
        controller.update(context: context(), event: cue(issuedAt: 0.3), enabled: true, now: 0.3)
        controller.update(context: context(), event: nil, enabled: true, now: 2)
        XCTAssertEqual(playback.events, [.speak(visibility.id)])
        playback.onFinish?(visibility.id)
        controller.update(context: context(), event: nil, enabled: true, now: 3)
        XCTAssertEqual(playback.events, [.speak(visibility.id)])
    }

    func testVisibilityPromptNeverQueuesFlickeringTrackingWarnings() {
        let playback = RecordingVoicePlayback()
        let controller = VoiceCuePlaybackController(playback: playback)
        func visibility(_ time: Double) -> VoiceCue {
            .init(id: UUID(), sessionID: sessionID, generation: generation,
                  text: "Keep your whole body visible.", kind: .coaching(.form), issuedAt: time, expiresAt: time + 6, reason: .tracking)
        }
        let first = visibility(0), flicker = visibility(0.5), recheck = visibility(3)
        controller.update(context: context(), event: first, enabled: true, now: 0)
        controller.update(context: context(), event: flicker, enabled: true, now: 0.5)
        XCTAssertEqual(playback.events, [.speak(first.id)])
        playback.onFinish?(first.id)
        controller.update(context: context(), event: flicker, enabled: true, now: 2)
        XCTAssertEqual(playback.events, [.speak(first.id)])
        controller.update(context: context(), event: recheck, enabled: true, now: 3)
        XCTAssertEqual(playback.events, [.speak(first.id), .speak(recheck.id)])
    }

    func testVisibilityPromptStillStopsForMutePauseOrAnImmediateStopWarning() {
        for interruption in ["mute", "pause", "stop"] {
            let playback = RecordingVoicePlayback()
            let controller = VoiceCuePlaybackController(playback: playback)
            let first = VoiceCue(id: UUID(), sessionID: sessionID, generation: generation,
                text: "Keep your whole body visible.", kind: .coaching(.form), issuedAt: 0, expiresAt: 6, reason: .tracking)
            controller.update(context: context(), event: first, enabled: true, now: 0)
            let stop = cue(.coaching(.stop), issuedAt: 1, expiresAt: nil)
            controller.update(context: context(interruption == "pause" ? .paused : .active),
                              event: interruption == "stop" ? stop : nil, enabled: interruption != "mute", now: 1)
            let expected: [RecordingVoicePlayback.Event] = interruption == "stop"
                ? [.speak(first.id), .stop, .speak(stop.id)] : [.speak(first.id), .stop]
            XCTAssertEqual(playback.events, expected)
        }
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

    func testFormWaitsForCurrentSentenceAndOnlyStartsOnAFreshCurrentTick() {
        for clears in [false, true] {
            let playback = RecordingVoicePlayback()
            let controller = VoiceCuePlaybackController(playback: playback)
            let pacing = cue(), chat = cue(.chat), form = cue(.coaching(.form))
            controller.update(context: context(), event: pacing, enabled: true, now: 0)
            controller.update(context: context(), event: chat, enabled: true, now: 1)
            controller.update(context: context(), event: form, enabled: true, now: 2)
            XCTAssertEqual(playback.events, [.speak(pacing.id)])
            controller.update(context: context(), event: clears ? nil : form, enabled: true, now: 3)
            playback.onFinish?(pacing.id)
            XCTAssertEqual(playback.events, [.speak(pacing.id)], "Warnings are not queued by the controller")
            controller.update(context: context(), event: clears ? nil : form, enabled: true, now: 4)
            XCTAssertEqual(playback.events, clears ? [.speak(pacing.id)] : [.speak(pacing.id), .speak(form.id)])
            controller.update(context: context(), event: chat, enabled: true, now: 4)
            XCTAssertEqual(playback.events.count, clears ? 1 : 2, "Lower cues were consumed while busy")
        }
    }

    func testDifferentCurrentFormCanSpeakAfterTheFirstFormFinishes() {
        let playback = RecordingVoicePlayback()
        let controller = VoiceCuePlaybackController(playback: playback)
        let alignment = VoiceCue(id: UUID(), sessionID: sessionID, generation: generation,
            text: "Align.", kind: .coaching(.form), issuedAt: 0, expiresAt: 6, reason: .alignment)
        let tracking = VoiceCue(id: UUID(), sessionID: sessionID, generation: generation,
            text: "Stay visible.", kind: .coaching(.form), issuedAt: 1, expiresAt: 6, reason: .tracking)
        controller.update(context: context(), event: alignment, enabled: true, now: 0)
        controller.update(context: context(), event: tracking, enabled: true, now: 1)
        XCTAssertEqual(playback.events, [.speak(alignment.id)])
        playback.onFinish?(alignment.id)
        controller.update(context: context(), event: tracking, enabled: true, now: 2)
        XCTAssertEqual(playback.events, [.speak(alignment.id), .speak(tracking.id)])
    }

    func testDeferredCompletionIsDiscardedForEveryExplicitCancellation() {
        for action in ["mute", "pause", "cancel", "generation", "session"] {
            let playback = RecordingVoicePlayback()
            let controller = VoiceCuePlaybackController(playback: playback)
            let first = cue()
            controller.update(context: context(), event: first, enabled: true, now: 0)
            let completion = VoiceCue(id: UUID(), sessionID: sessionID, generation: generation,
                text: "Finished.", kind: .coaching(.rest), issuedAt: 1, expiresAt: 6, reason: .workoutCompleted)
            controller.update(context: context(.finished), event: completion, enabled: true, now: 1)
            switch action {
            case "cancel": controller.cancel()
            case "generation": controller.update(context: context(generation: UUID()), event: nil, enabled: true, now: 2)
            case "session": controller.update(context: context(sessionID: UUID()), event: nil, enabled: true, now: 2)
            default: controller.update(context: context(action == "pause" ? .paused : .finished), event: nil,
                                       enabled: action != "mute", now: 2)
            }
            playback.onFinish?(first.id)
            XCTAssertEqual(playback.events, [.speak(first.id), .stop], action)
        }
    }

    func testExpiryLimitsStartAndNeverCutsOffAnActiveSentence() {
        let playback = RecordingVoicePlayback()
        let controller = VoiceCuePlaybackController(playback: playback)
        controller.update(context: context(), event: cue(expiresAt: 1), enabled: true, now: 1)
        XCTAssertTrue(playback.events.isEmpty)
        let current = cue(expiresAt: 3)
        controller.update(context: context(), event: current, enabled: true, now: 1)
        controller.update(context: context(), event: current, enabled: true, now: 3)
        XCTAssertEqual(playback.events, [.speak(current.id)])
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
        for phase in [SessionPhase.paused, .idle] {
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

    func testLateCompletionCannotClearNewCueAndNilEventPreservesSpeech() {
        let playback = RecordingVoicePlayback()
        let controller = VoiceCuePlaybackController(playback: playback)
        let old = cue(), stop = cue(.coaching(.stop), expiresAt: nil)
        controller.update(context: context(), event: old, enabled: true, now: 0)
        controller.update(context: context(), event: stop, enabled: true, now: 1)
        playback.onFinish?(old.id)
        controller.update(context: context(), event: cue(.chat), enabled: true, now: 2)
        controller.update(context: context(), event: nil, enabled: true, now: 3)
        XCTAssertEqual(playback.events, [.speak(old.id), .stop, .speak(stop.id)])
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
        XCTAssertEqual(playback.events, [.speak(completion.id)])
        for phase in [SessionPhase.idle, .active, .rest, .paused] {
            let wrongPhasePlayback = RecordingVoicePlayback()
            let wrongPhaseController = VoiceCuePlaybackController(playback: wrongPhasePlayback)
            wrongPhaseController.update(context: context(phase), event: completion, enabled: true, now: 1)
            XCTAssertTrue(wrongPhasePlayback.events.isEmpty)
        }
    }

    func testCompletionWaitsForSentenceAndSpeaksOnceOnlyWhileFresh() {
        for finishTime in [2.0, 7.0] {
            var clock = 0.0
            let playback = RecordingVoicePlayback()
            let controller = VoiceCuePlaybackController(playback: playback, uptime: { clock })
            let ordinary = cue()
            let completion = VoiceCue(id: UUID(), sessionID: sessionID, generation: generation,
                text: "Finished.", kind: .coaching(.rest), issuedAt: 1, expiresAt: 6, reason: .workoutCompleted)
            controller.update(context: context(), event: ordinary, enabled: true, now: 0)
            clock = 1
            controller.update(context: context(.finished), event: completion, enabled: true, now: 1)
            XCTAssertEqual(playback.events, [.speak(ordinary.id)])
            clock = finishTime
            playback.onFinish?(ordinary.id)
            playback.onFinish?(ordinary.id)
            let expected: [RecordingVoicePlayback.Event] = finishTime < 6
                ? [.speak(ordinary.id), .speak(completion.id)] : [.speak(ordinary.id)]
            XCTAssertEqual(playback.events, expected)
            controller.update(context: context(.finished), event: completion, enabled: true, now: finishTime)
            XCTAssertEqual(playback.events, expected)
        }
    }

    func testNilEqualAndLowerWarningsNeverCutOrQueueOrdinarySpeech() {
        let playback = RecordingVoicePlayback()
        let controller = VoiceCuePlaybackController(playback: playback)
        let first = cue(), equal = cue(), lower = cue(.coaching(.rest))
        controller.update(context: context(), event: first, enabled: true, now: 0)
        for event in [nil, equal, lower] {
            controller.update(context: context(), event: event, enabled: true, now: 1)
        }
        XCTAssertEqual(playback.events, [.speak(first.id)])
        playback.onFinish?(first.id)
        for event in [equal, lower] {
            controller.update(context: context(), event: event, enabled: true, now: 2)
        }
        XCTAssertEqual(playback.events, [.speak(first.id)])
    }

    func testNaturalRestTransitionPreservesSentenceAndInvalidatesDeferredOnNewContext() {
        let playback = RecordingVoicePlayback()
        let controller = VoiceCuePlaybackController(playback: playback)
        let first = cue()
        controller.update(context: context(), event: first, enabled: true, now: 0)
        let rest = context(.rest, generation: UUID())
        controller.transition(to: rest)
        let recovery = VoiceCue(id: UUID(), sessionID: sessionID, generation: rest.generation,
            text: "Recover.", kind: .coaching(.rest), issuedAt: 1, expiresAt: 6)
        controller.update(context: rest, event: recovery, enabled: true, now: 1)
        XCTAssertEqual(playback.events, [.speak(first.id)])
        controller.update(context: context(generation: UUID()), event: recovery, enabled: true, now: 2)
        playback.onFinish?(first.id)
        XCTAssertEqual(playback.events, [.speak(first.id), .stop])
    }

    func testStopDiscardsDeferredRecoveryImmediately() {
        let playback = RecordingVoicePlayback()
        let controller = VoiceCuePlaybackController(playback: playback)
        let first = cue(), stop = cue(.coaching(.stop), expiresAt: nil)
        controller.update(context: context(), event: first, enabled: true, now: 0)
        let rest = context(.rest)
        controller.update(context: rest, event: cue(.coaching(.rest)), enabled: true, now: 1)
        controller.update(context: rest, event: stop, enabled: true, now: 2)
        playback.onFinish?(first.id)
        playback.onFinish?(stop.id)
        XCTAssertEqual(playback.events, [.speak(first.id), .stop, .speak(stop.id)])
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

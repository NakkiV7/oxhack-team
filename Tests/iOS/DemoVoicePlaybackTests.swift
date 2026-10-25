import AVFoundation
import XCTest
@testable import Spottr

@MainActor
final class DemoVoicePlaybackTests: XCTestCase {
    func testBundledBankExistsAndDecodesWithoutPlayingAudio() throws {
        for name in ["positive-1", "positive-2", "positive-3", "positive-4", "slower-1", "slower-2", "slower-3", "recovery", "recovery-2", "positive-5", "slower-4", "completion", "tracking", "alignment", "target", "rest", "stop"] {
            let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "mp3", subdirectory: "DemoVoice/arnold"))
            let player = try AVAudioPlayer(contentsOf: url)
            XCTAssertEqual(player.format.sampleRate, 22_050)
            XCTAssertGreaterThan(player.duration, 0)
            XCTAssertLessThanOrEqual(player.duration, 10)
            XCTAssertTrue(player.prepareToPlay())
            XCTAssertFalse(player.isPlaying)
        }
    }

    func testPreviewArnoldIsTheOnlyCachedSelection() {
        XCTAssertTrue(DemoVoicePlayback.isAvailable(preview: true, coach: .arnold))
        XCTAssertFalse(DemoVoicePlayback.isAvailable(preview: false, coach: .arnold))
        XCTAssertFalse(DemoVoicePlayback.isAvailable(preview: true, coach: .david))
        XCTAssertFalse(DemoVoicePlayback.isAvailable(preview: true, coach: .local))
    }

    func testReasonAndPrioritySelectSafeVariantsWithoutTextGuessing() {
        XCTAssertEqual(DemoVoicePlayback.clipName(reason: .steadyRhythm, priority: .pacing, variant: 0), "positive-1")
        XCTAssertEqual(DemoVoicePlayback.clipName(reason: .steadyRhythm, priority: .pacing, variant: 1), "positive-2")
        XCTAssertEqual(DemoVoicePlayback.clipName(reason: .slowerRep, priority: .pacing, variant: 0), "slower-1")
        XCTAssertEqual(DemoVoicePlayback.clipName(reason: .slowerRep, priority: .pacing, variant: 1), "slower-2")
        XCTAssertEqual(DemoVoicePlayback.clipName(reason: .tracking, priority: .form, variant: 0), "tracking")
        XCTAssertEqual(DemoVoicePlayback.clipName(reason: .alignment, priority: .form, variant: 0), "alignment")
        XCTAssertEqual(DemoVoicePlayback.clipName(reason: .targetReached, priority: .pacing, variant: 0), "target")
        XCTAssertEqual(DemoVoicePlayback.clipName(reason: .restReminder, priority: .rest, variant: 0), "rest")
        XCTAssertEqual(DemoVoicePlayback.clipName(reason: .discomfort, priority: .stop, variant: 0), "stop")
        XCTAssertNil(DemoVoicePlayback.clipName(reason: .steadyRhythm, priority: .form, variant: 0))
        XCTAssertNil(DemoVoicePlayback.clipName(reason: nil, priority: .pacing, variant: 0))
    }

    func testRecoveryRequiresAnExplicitEndedSetOrFatigueEventAndRestPriority() {
        XCTAssertEqual(DemoVoicePlayback.clipName(reason: nil, priority: .rest, variant: 0, recovery: .endedSet), "recovery")
        XCTAssertEqual(DemoVoicePlayback.clipName(reason: nil, priority: .rest, variant: 0, recovery: .fatigue), "recovery")
        XCTAssertNil(DemoVoicePlayback.clipName(reason: nil, priority: .rest, variant: 0))
        XCTAssertNil(DemoVoicePlayback.clipName(reason: .tracking, priority: .rest, variant: 0, recovery: .endedSet))
        XCTAssertNil(DemoVoicePlayback.clipName(reason: nil, priority: .pacing, variant: 0, recovery: .fatigue))
        let local = DemoSilentVoice(), audio = DemoSilentAudio()
        var names: [String] = []
        let ended = cue(reason: nil, kind: .coaching(.rest))
        let playback = DemoVoicePlayback(local: local, makeAudio: { names.append($0); return audio },
            recoveryReason: { $0.id == ended.id ? .endedSet : nil }, prepareAudioSession: {}, releaseAudioSession: {}, uptime: { 2 })
        playback.speak(ended)
        XCTAssertEqual(names, ["recovery"])
        let stop = cue(reason: .discomfort, kind: .coaching(.stop), expiry: nil)
        playback.speak(stop)
        XCTAssertTrue(local.spoken.isEmpty)
        XCTAssertEqual(audio.stops, 1)
    }

    func testCompletedWorkoutUsesSignatureLineOnceAndStopsOnMute() {
        let local = DemoSilentVoice(), output = DemoSilentAudio()
        var names: [String] = []
        let playback = DemoVoicePlayback(local: local, makeAudio: { names.append($0); return output }, prepareAudioSession: {}, releaseAudioSession: {}, uptime: { 2 })
        let controller = VoiceCuePlaybackController(playback: playback)
        let completion = cue(reason: .workoutCompleted, kind: .coaching(.rest))
        let context = VoiceCueContext(sessionID: completion.sessionID, generation: completion.generation, phase: .finished)
        controller.update(context: context, event: completion, enabled: true, now: 2)
        controller.update(context: context, event: completion, enabled: true, now: 2)
        XCTAssertEqual(names, ["completion"])
        XCTAssertEqual(output.plays, 1)
        XCTAssertTrue(local.spoken.isEmpty)
        controller.update(context: context, event: completion, enabled: false, now: 2)
        XCTAssertEqual(output.stops, 1)
        controller.update(context: context, event: completion, enabled: true, now: 2)
        XCTAssertEqual(output.plays, 1)
        XCTAssertNil(DemoVoicePlayback.clipName(reason: .workoutCompleted, priority: .pacing, variant: 0))
    }

    func testEveryCategoryRotatesIndependentlyThroughAllVariants() {
        let local = DemoSilentVoice(), audio = DemoSilentAudio()
        var names: [String] = []
        let playback = DemoVoicePlayback(local: local, makeAudio: { names.append($0); return audio },
            recoveryReason: { $0.kind == .coaching(.rest) && $0.reason == nil ? .endedSet : nil }, prepareAudioSession: {}, releaseAudioSession: {}, uptime: { 2 })
        for _ in 0..<6 {
            playback.speak(cue())
            playback.speak(cue(reason: .slowerRep))
            playback.speak(cue(reason: nil, kind: .coaching(.rest)))
        }
        XCTAssertEqual(names, ["positive-1", "slower-1", "recovery", "positive-2", "slower-2", "recovery-2",
            "positive-3", "slower-3", "recovery", "positive-4", "slower-4", "recovery-2",
            "positive-5", "slower-1", "recovery", "positive-1", "slower-2", "recovery-2"])
    }

    func testCachedPlaybackAlternatesAndStopInterruptsWithImmediateArnoldAudio() {
        let local = DemoSilentVoice(), first = DemoSilentAudio(), second = DemoSilentAudio()
        var names: [String] = []
        let playback = DemoVoicePlayback(local: local, makeAudio: { name in
            names.append(name); return names.count == 1 ? first : second
        }, prepareAudioSession: {}, releaseAudioSession: {}, uptime: { 2 })
        let one = cue(), two = cue()
        playback.speak(one)
        let stale = first.onFinish
        playback.speak(two)
        XCTAssertEqual(names, ["positive-1", "positive-2"])
        XCTAssertEqual(first.stops, 1)
        var finished: [UUID] = []
        playback.onFinish = { finished.append($0) }
        stale?()
        XCTAssertTrue(finished.isEmpty)
        let stop = cue(reason: .discomfort, kind: .coaching(.stop), expiry: nil)
        playback.speak(stop)
        XCTAssertEqual(second.stops, 1)
        XCTAssertTrue(local.spoken.isEmpty)
        second.onFinish?()
        XCTAssertEqual(finished, [stop.id])
    }

    func testEveryWorkoutReasonUsesItsArnoldClipIncludingImmediateStop() {
        let local = DemoSilentVoice(), output = DemoSilentAudio()
        var names: [String] = []
        let playback = DemoVoicePlayback(local: local, makeAudio: { names.append($0); return output },
            prepareAudioSession: {}, releaseAudioSession: {}, uptime: { 2 })
        let events = [cue(reason: .tracking, kind: .coaching(.form)),
            cue(reason: .alignment, kind: .coaching(.form)), cue(reason: .targetReached),
            cue(reason: .restReminder, kind: .coaching(.rest)),
            cue(reason: .discomfort, kind: .coaching(.stop), expiry: nil)]
        for event in events { playback.speak(event) }
        XCTAssertEqual(names, ["tracking", "alignment", "target", "rest", "stop"])
        XCTAssertEqual(output.plays, 5)
        XCTAssertTrue(local.spoken.isEmpty)
    }

    func testUnavailableArnoldSafetyClipStillSpeaksImmediateStop() {
        for missing in [true, false] {
            let local = DemoSilentVoice(), output = DemoSilentAudio()
            output.willPlay = false
            let playback = DemoVoicePlayback(local: local, makeAudio: { _ in
                if missing { throw DemoFailure.missing }
                return output
            }, prepareAudioSession: {}, releaseAudioSession: {}, uptime: { 2 })
            let stop = cue(reason: .discomfort, kind: .coaching(.stop), expiry: nil)
            playback.speak(stop)
            XCTAssertEqual(local.spoken, [stop])
        }
    }

    func testUnmappedOrdinaryCueNeverSwitchesToAppleOrInventsEncouragement() {
        let local = DemoSilentVoice()
        let playback = DemoVoicePlayback(local: local, makeAudio: { _ in
            XCTFail("No recording can be chosen for an unknown reason")
            throw DemoFailure.missing
        }, prepareAudioSession: {}, releaseAudioSession: {}, uptime: { 2 })
        let event = cue(reason: nil)
        var finished: [UUID] = []
        playback.onFinish = { finished.append($0) }
        playback.speak(event)
        XCTAssertEqual(finished, [event.id])
        XCTAssertTrue(local.spoken.isEmpty)
    }

    func testExpiredFutureAndMalformedCuesNeverStartAudio() {
        let local = DemoSilentVoice()
        let playback = DemoVoicePlayback(local: local, makeAudio: { _ in XCTFail("Invalid cue"); throw DemoFailure.missing }, prepareAudioSession: {}, releaseAudioSession: {}, uptime: { 2 })
        for event in [cue(expiry: 2), cue(expiry: nil), cue(expiry: .infinity), cue(issued: 3), cue(issued: .nan)] {
            playback.speak(event)
        }
        XCTAssertTrue(local.spoken.isEmpty)
    }

    func testMissingOrRejectedClipFinishesWithoutRetryOrClaimingCachedPlayback() {
        for failToLoad in [true, false] {
            let local = DemoSilentVoice(), output = DemoSilentAudio()
            output.willPlay = false
            var attempts = 0, finished: [UUID] = []
            let playback = DemoVoicePlayback(local: local, makeAudio: { _ in
                attempts += 1
                if failToLoad { throw DemoFailure.missing }
                return output
            }, prepareAudioSession: {}, releaseAudioSession: {}, uptime: { 2 })
            playback.onFinish = { finished.append($0) }
            let event = cue(); playback.speak(event)
            XCTAssertEqual(attempts, 1)
            XCTAssertEqual(finished, [event.id])
            XCTAssertTrue(local.spoken.isEmpty)
        }
    }

    func testControllerStillDropsLowerPriorityAndCancelsPreviewAudio() {
        let local = DemoSilentVoice(), output = DemoSilentAudio()
        let playback = DemoVoicePlayback(local: local, makeAudio: { _ in output }, prepareAudioSession: {}, releaseAudioSession: {}, uptime: { 2 })
        let controller = VoiceCuePlaybackController(playback: playback)
        let event = cue(), context = VoiceCueContext(sessionID: event.sessionID, generation: event.generation, phase: .active)
        controller.update(context: context, event: event, enabled: true, now: 2)
        let rest = VoiceCue(id: UUID(), sessionID: event.sessionID, generation: event.generation, text: "Rest", kind: .coaching(.rest), issuedAt: 0, expiresAt: 6, reason: .restReminder)
        controller.update(context: context, event: rest, enabled: true, now: 2)
        XCTAssertEqual(output.plays, 1)
        XCTAssertTrue(local.spoken.isEmpty)
        controller.cancel()
        XCTAssertEqual(output.stops, 1)
    }

    func testWorkoutSimulationGatesFreshAudioAndCancelsAcrossLifecycleChanges() {
        let local = DemoSilentVoice(), audio = DemoSilentAudio()
        var names: [String] = []
        let playback = DemoVoicePlayback(local: local, makeAudio: { names.append($0); return audio }, prepareAudioSession: {}, releaseAudioSession: {}, uptime: { 2 })
        let controller = VoiceCuePlaybackController(playback: playback)
        let session = UUID(), generation = UUID()
        let context = VoiceCueContext(sessionID: session, generation: generation, phase: .active)
        func event(_ reason: CoachingReason = .steadyRhythm, priority: CoachingPriority = .pacing,
                   expiry: Double? = 6) -> VoiceCue {
            .init(id: UUID(), sessionID: session, generation: generation, text: "Current workout event",
                  kind: .coaching(priority), issuedAt: 0, expiresAt: expiry, reason: reason)
        }
        let muted = event()
        controller.update(context: context, event: muted, enabled: false, now: 2)
        controller.update(context: context, event: muted, enabled: true, now: 2)
        XCTAssertTrue(names.isEmpty)
        let first = event()
        controller.update(context: context, event: first, enabled: true, now: 2)
        controller.update(context: context, event: first, enabled: true, now: 2)
        controller.update(context: context, event: event(.restReminder, priority: .rest), enabled: true, now: 2)
        controller.update(context: context, event: event(expiry: 2), enabled: true, now: 2)
        XCTAssertEqual(names, ["positive-1"])
        XCTAssertTrue(local.spoken.isEmpty)
        let staleCompletion = audio.onFinish
        let stop = event(.discomfort, priority: .stop, expiry: nil)
        controller.update(context: context, event: stop, enabled: true, now: 2)
        XCTAssertEqual(audio.stops, 1)
        XCTAssertTrue(local.spoken.isEmpty)
        staleCompletion?()
        controller.update(context: context, event: event(), enabled: true, now: 2)
        XCTAssertEqual(names, ["positive-1", "stop"], "A stale audio callback cannot clear the active stop")
        controller.cancel()
        controller.update(context: context, event: event(.slowerRep), enabled: true, now: 2)
        XCTAssertEqual(names.last, "slower-1")
        controller.update(context: .init(sessionID: session, generation: generation, phase: .paused), event: nil, enabled: true, now: 2)
        XCTAssertEqual(audio.stops, 3)
        controller.update(context: context, event: event(), enabled: true, now: 2)
        controller.update(context: context, event: nil, enabled: false, now: 2)
        XCTAssertEqual(audio.stops, 4)
        controller.update(context: context, event: event(), enabled: true, now: 2)
        controller.update(context: .init(sessionID: session, generation: UUID(), phase: .active), event: first, enabled: true, now: 2)
        XCTAssertEqual(audio.stops, 5)
        XCTAssertEqual(audio.plays, 5)
        XCTAssertEqual(names, ["positive-1", "stop", "slower-1", "positive-2", "positive-3"])
    }

    func testAudioSessionActivatesOnlyForMappedClipsAndReleasesAfterCompletion() {
        let local = DemoSilentVoice(), audio = DemoSilentAudio()
        var events: [String] = []
        audio.onPlay = { events.append("play") }
        let playback = DemoVoicePlayback(local: local, makeAudio: { _ in audio },
            prepareAudioSession: { events.append("activate") },
            releaseAudioSession: { events.append("release") }, uptime: { 2 })
        XCTAssertTrue(events.isEmpty)
        playback.speak(cue(expiry: 2))
        playback.speak(cue(reason: nil))
        XCTAssertTrue(events.isEmpty, "Expired and local fallback cues must not activate cached audio")
        let event = cue()
        var finished: [UUID] = []
        playback.onFinish = { finished.append($0) }
        playback.speak(event)
        XCTAssertEqual(events, ["activate", "play"])
        audio.onFinish?()
        XCTAssertEqual(events, ["activate", "play", "release"])
        XCTAssertEqual(finished, [event.id])
        playback.stop()
        XCTAssertEqual(events, ["activate", "play", "release"])
    }

    func testAudioSessionActivationFailureCannotPlayOrFallBackToSpeech() {
        let local = DemoSilentVoice(), audio = DemoSilentAudio()
        var activations = 0, releases = 0, finished: [UUID] = []
        let playback = DemoVoicePlayback(local: local, makeAudio: { _ in audio },
            prepareAudioSession: { activations += 1; throw DemoFailure.missing },
            releaseAudioSession: { releases += 1 }, uptime: { 2 })
        playback.onFinish = { finished.append($0) }
        let event = cue()
        playback.speak(event)
        XCTAssertEqual(activations, 1)
        XCTAssertEqual(audio.plays, 0)
        XCTAssertTrue(local.spoken.isEmpty)
        XCTAssertEqual(finished, [event.id])
        XCTAssertEqual(releases, 0, "A failed activation must not claim an acquired audio session")
    }

    func testPauseStopsCachedAudioAndReleasesOtherAudioOnce() {
        let audio = DemoSilentAudio()
        var activations = 0, releases = 0
        let playback = DemoVoicePlayback(local: DemoSilentVoice(), makeAudio: { _ in audio },
            prepareAudioSession: { activations += 1 },
            releaseAudioSession: { releases += 1 }, uptime: { 2 })
        let controller = VoiceCuePlaybackController(playback: playback)
        let event = cue()
        let context = VoiceCueContext(sessionID: event.sessionID, generation: event.generation, phase: .active)
        controller.update(context: context, event: event, enabled: true, now: 2)
        XCTAssertEqual(activations, 1)
        XCTAssertEqual(releases, 0)
        controller.update(context: .init(sessionID: event.sessionID, generation: event.generation, phase: .paused),
                          event: nil, enabled: true, now: 2)
        XCTAssertEqual(audio.stops, 1)
        XCTAssertEqual(releases, 1)
        controller.cancel()
        XCTAssertEqual(releases, 1)
    }

    private func cue(reason: CoachingReason? = .steadyRhythm, kind: VoiceCue.Kind = .coaching(.pacing), expiry: Double? = 6, issued: Double = 0) -> VoiceCue {
        .init(id: UUID(), sessionID: UUID(), generation: UUID(), text: "Original deterministic cue", kind: kind, issuedAt: issued, expiresAt: expiry, reason: reason)
    }
    private enum DemoFailure: Error { case missing }
}

@MainActor private final class DemoSilentVoice: VoicePlayback {
    var onFinish: ((UUID) -> Void)?
    var spoken: [VoiceCue] = []
    func speak(_ cue: VoiceCue) { spoken.append(cue) }
    func stop() {}
}

@MainActor private final class DemoSilentAudio: VoiceAudioOutput {
    var onFinish: (() -> Void)?
    var plays = 0, stops = 0
    var willPlay = true
    var onPlay: (() -> Void)?
    func play() -> Bool { plays += 1; onPlay?(); return willPlay }
    func stop() { stops += 1 }
}

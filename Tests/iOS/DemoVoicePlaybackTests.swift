import AVFoundation
import XCTest
@testable import Spottr

@MainActor
final class DemoVoicePlaybackTests: XCTestCase {
    func testBundledBankExistsAndDecodesWithoutPlayingAudio() throws {
        for name in ["positive-1", "positive-2", "slower-1", "slower-2", "recovery"] {
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
        XCTAssertNil(DemoVoicePlayback.clipName(reason: .tracking, priority: .form, variant: 0))
        XCTAssertNil(DemoVoicePlayback.clipName(reason: .alignment, priority: .form, variant: 0))
        XCTAssertNil(DemoVoicePlayback.clipName(reason: .targetReached, priority: .pacing, variant: 0))
        XCTAssertNil(DemoVoicePlayback.clipName(reason: .restReminder, priority: .rest, variant: 0))
        XCTAssertNil(DemoVoicePlayback.clipName(reason: .discomfort, priority: .stop, variant: 0))
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
            recoveryReason: { $0.id == ended.id ? .endedSet : nil }, uptime: { 2 })
        playback.speak(ended)
        XCTAssertEqual(names, ["recovery"])
        let stop = cue(reason: .discomfort, kind: .coaching(.stop), expiry: nil)
        playback.speak(stop)
        XCTAssertEqual(local.spoken, [stop])
        XCTAssertEqual(audio.stops, 1)
    }

    func testCachedPlaybackAlternatesAndStopInterruptsWithImmediateLocalSpeech() {
        let local = DemoSilentVoice(), first = DemoSilentAudio(), second = DemoSilentAudio()
        var names: [String] = []
        let playback = DemoVoicePlayback(local: local, makeAudio: { name in
            names.append(name); return names.count == 1 ? first : second
        }, uptime: { 2 })
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
        XCTAssertEqual(local.spoken, [stop])
        local.onFinish?(stop.id)
        XCTAssertEqual(finished, [stop.id])
    }

    func testUnknownTrackingAndRestUseOriginalLocalWordsAndNeverEncouragement() {
        let local = DemoSilentVoice()
        let playback = DemoVoicePlayback(local: local, makeAudio: { _ in XCTFail("Unsafe cached cue"); throw DemoFailure.missing }, uptime: { 2 })
        let events = [cue(reason: nil), cue(reason: .tracking, kind: .coaching(.form)),
                      cue(reason: .alignment, kind: .coaching(.form)), cue(reason: .restReminder, kind: .coaching(.rest)),
                      cue(reason: .targetReached)]
        for event in events { playback.speak(event) }
        XCTAssertEqual(local.spoken, events)
    }

    func testExpiredFutureAndMalformedCuesNeverStartAudio() {
        let local = DemoSilentVoice()
        let playback = DemoVoicePlayback(local: local, makeAudio: { _ in XCTFail("Invalid cue"); throw DemoFailure.missing }, uptime: { 2 })
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
            }, uptime: { 2 })
            playback.onFinish = { finished.append($0) }
            let event = cue(); playback.speak(event)
            XCTAssertEqual(attempts, 1)
            XCTAssertEqual(finished, [event.id])
            XCTAssertTrue(local.spoken.isEmpty)
        }
    }

    func testControllerStillDropsLowerPriorityAndCancelsPreviewAudio() {
        let local = DemoSilentVoice(), output = DemoSilentAudio()
        let playback = DemoVoicePlayback(local: local, makeAudio: { _ in output }, uptime: { 2 })
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
    func play() -> Bool { plays += 1; return willPlay }
    func stop() { stops += 1 }
}

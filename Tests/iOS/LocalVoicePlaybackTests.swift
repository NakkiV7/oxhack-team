import AVFoundation
import XCTest
@testable import Spottr

@MainActor
final class LocalVoicePlaybackTests: XCTestCase {
    func testLocalDriverSpeaksStandardTextAndStopsAtImmediateBoundary() {
        let synthesizer = RecordingSpeechSynthesizer()
        let playback = LocalVoicePlayback(synthesizer: synthesizer)
        let cue = event()
        playback.speak(cue)
        XCTAssertEqual(synthesizer.utterances.map(\.speechString), [cue.text])
        XCTAssertFalse(synthesizer.usesApplicationAudioSession)
        playback.stop()
        XCTAssertEqual(synthesizer.boundaries, [.immediate])
    }

    func testFinishingOldUtteranceDoesNotFinishItsReplacement() async throws {
        let synthesizer = RecordingSpeechSynthesizer()
        let playback = LocalVoicePlayback(synthesizer: synthesizer)
        let first = event(), second = event()
        var finished: [UUID] = []
        let completed = expectation(description: "Current speech completed")
        playback.onFinish = { id in
            finished.append(id)
            if id == second.id { completed.fulfill() }
        }
        playback.speak(first)
        let firstUtterance = try XCTUnwrap(synthesizer.utterances.first)
        playback.speak(second)
        XCTAssertEqual(synthesizer.boundaries, [.immediate])
        let secondUtterance = try XCTUnwrap(synthesizer.utterances.last)
        synthesizer.delegate?.speechSynthesizer?(synthesizer, didFinish: firstUtterance)
        synthesizer.delegate?.speechSynthesizer?(synthesizer, didFinish: secondUtterance)
        await fulfillment(of: [completed], timeout: 1)
        XCTAssertEqual(finished, [second.id])
    }

    private func event() -> VoiceCue {
        .init(id: UUID(), sessionID: UUID(), generation: UUID(), text: "Take your time.",
              kind: .coaching(.rest), issuedAt: 0, expiresAt: 6)
    }
}

@MainActor
private final class RecordingSpeechSynthesizer: AVSpeechSynthesizer {
    var utterances: [AVSpeechUtterance] = []
    var boundaries: [AVSpeechBoundary] = []
    override func speak(_ utterance: AVSpeechUtterance) { utterances.append(utterance) }
    override func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool {
        boundaries.append(boundary)
        return true
    }
}

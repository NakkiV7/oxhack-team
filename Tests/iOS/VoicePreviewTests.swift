import XCTest
import AVFoundation
import UIKit
@testable import Spottr

@MainActor final class VoicePreviewTests: XCTestCase {
    func testLatestSelectionWinsAndOldCompletionCannotStopNewPreview() throws {
        let fixture = PreviewFixture()
        let preview = VoicePreviewCoordinator(preferences: fixture.live, playback: fixture.samples)
        preview.select(.maya, tone: .gentle)
        let first = try XCTUnwrap(fixture.outputs.first)
        let completion = first.onFinish
        preview.select(.leo, tone: .direct)
        let second = try XCTUnwrap(fixture.outputs.last)
        XCTAssertEqual(fixture.outputs.count, 2)
        XCTAssertEqual(first.stops, 1)
        XCTAssertEqual(second.stops, 0)
        completion?()
        XCTAssertTrue(preview.isPlaying)
        XCTAssertEqual(preview.preference, .leo)
        XCTAssertNotEqual(fixture.audio.first, fixture.audio.last)
        preview.stop()
        XCTAssertEqual(second.stops, 1)
    }
    func testPreviewDoesNotInterruptLiveSentenceOrEnterMicrophoneAndNewWorkoutStopsIt() throws {
        let fixture = PreviewFixture()
        let store = TrainingStore(historyURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("history.json"), voicePlayback: fixture.live)
        let preview = try XCTUnwrap(store.voicePreviews)
        preview.select(.maya, tone: .gentle)
        XCTAssertTrue(preview.isPlaying)
        fixture.live.speak(.init(id: UUID(), sessionID: UUID(), generation: UUID(), text: "Keep a steady rhythm.", kind: .coaching(.pacing), issuedAt: 1, expiresAt: 6, reason: .steadyRhythm))
        store.beginAuthorizedSession()
        XCTAssertFalse(preview.isPlaying, "An authorized new workout deliberately cancels setup previews")
        preview.select(.leo, tone: .direct)
        XCTAssertFalse(preview.isPlaying)
        XCTAssertNotNil(preview.message)
        XCTAssertEqual(fixture.liveOutputs.first?.stops, 0, "Choosing future coaching must let an ordinary sentence finish")
        XCTAssertEqual(fixture.live.preference, .leo)
        store.cancelCoaching()
    }
    func testMissingNaturalAssetIsRecoverableAndMuteAndLifecycleStopPreview() async throws {
        let fixture = PreviewFixture()
        let preview = VoicePreviewCoordinator(preferences: fixture.live, playback: fixture.samples)
        fixture.fail = true
        preview.select(.maya, tone: .gentle)
        XCTAssertFalse(preview.isPlaying)
        XCTAssertNotNil(preview.message)
        fixture.fail = false
        preview.select(.maya, tone: .gentle)
        XCTAssertTrue(preview.isPlaying)
        preview.setEnabled(false)
        XCTAssertFalse(preview.isPlaying)
        preview.select(.leo, tone: .direct)
        XCTAssertEqual(fixture.outputs.count, 1)
        preview.setEnabled(true)
        preview.select(.david, tone: .direct)
        XCTAssertTrue(preview.isPlaying)
        NotificationCenter.default.post(name: AVAudioSession.routeChangeNotification, object: nil)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(preview.isPlaying)
        preview.select(.arnold, tone: .gentle)
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(preview.isPlaying)
        preview.select(.maya, tone: .gentle)
        preview.stop()
        XCTAssertFalse(preview.isPlaying)
    }
    func testJuniorCannotPreviewAdultPackAndRetiredPolicyCannotSelect() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let live = RemoteVoicePlayback(offlineOnly: true, defaults: defaults, gentleOnly: true)
        var valid = true
        let preview = VoicePreviewCoordinator(preferences: live, permitsSelection: { valid })
        preview.select(.david, tone: .direct)
        XCTAssertNotEqual(preview.preference, .david)
        XCTAssertFalse(preview.isPlaying)
        valid = false
        preview.select(.leo, tone: .gentle)
        XCTAssertEqual(preview.preference, .maya)
    }
}

@MainActor private final class PreviewFixture {
    var outputs: [PreviewOutput] = []
    var liveOutputs: [PreviewOutput] = []
    var audio: [Data] = []
    var fail = false
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    lazy var live = RemoteVoicePlayback(offlineOnly: true, defaults: defaults, makeAudio: { [unowned self] _ in
        let output = PreviewOutput(); liveOutputs.append(output); return output
    }, uptime: { 2 })
    lazy var samples = RemoteVoicePlayback(offlineOnly: true, defaults: defaults, makeAudio: { [unowned self] data in
        if fail { throw CocoaError(.fileNoSuchFile) }
        let output = PreviewOutput(); outputs.append(output); audio.append(data); return output
    }, uptime: { 2 })
}
@MainActor private final class PreviewOutput: VoiceAudioOutput {
    var onFinish: (() -> Void)?
    var stops = 0
    func play() -> Bool { true }
    func stop() { stops += 1 }
}

import XCTest
import AVFoundation
import UIKit
@testable import Spottr

@MainActor final class VoicePreviewTests: XCTestCase {
    func testProfileVoiceDestinationSharesClosingAndNewStartOwnership() throws {
        let f = try RoutePreviewFixture()
        defer { f.cleanUp() }
        // This is the exact destination factory used by the real Root settings sheet.
        let preview = f.root.profileSettings.voiceSettings.previews
        defer { preview.stop() }
        try assertRouteOwnsClosingAndNewStart(preview, fixture: f)
    }
    func testRootSetupVoiceSelectionSharesClosingAndRetirementOwnership() throws {
        let f = try RoutePreviewFixture()
        defer { f.cleanUp() }
        // The real Root setup destination's State initial coordinator, not a replacement SUT.
        let preview = f.root.setupView.previews
        defer { preview.stop() }
        try assertRouteOwnsClosingAndNewStart(preview, fixture: f)
        f.training.setAccountActive(false); f.profile.invalidatePolicy()
        let previous = preview.preference
        preview.select(.leo, tone: .direct)
        XCTAssertEqual(preview.preference, previous)
        XCTAssertFalse(preview.isPlaying)
    }
    private func assertRouteOwnsClosingAndNewStart(_ preview: VoicePreviewCoordinator, fixture f: RoutePreviewFixture) throws {
        f.training.beginAuthorizedSession(); f.training.setVoiceFeedback(true)
        f.training.switchToManualReps(); f.training.setManualReps(2); f.training.endSet(); f.training.finish()
        let closing = try XCTUnwrap(f.voice.spoken.first { $0.reason == .workoutCompleted })
        preview.select(.maya, tone: .gentle)
        XCTAssertFalse(preview.isPlaying, "The actual settings route must wait for the held live closing sentence")
        XCTAssertEqual(f.voice.stops, 0, "A settings selection must not cut ordinary closing speech")
        f.voice.onFinish?(closing.id)
        preview.select(.maya, tone: .gentle)
        XCTAssertTrue(preview.isPlaying, "Fresh selection remains functional after actual completion")
        f.training.beginAuthorizedSession()
        XCTAssertFalse(preview.isPlaying, "The real new-start owner must cancel this destination's sample")
        XCTAssertEqual(f.training.history.first?.sets.first?.reps, 2)
    }
    func testLatestSelectionWinsAndOldCompletionCannotStopNewPreview() throws {
        let fixture = PreviewFixture()
        let preview = VoicePreviewCoordinator(preferences: fixture.live, playback: fixture.samples, canPreview: { true })
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
        let preview = VoicePreviewCoordinator(preferences: fixture.live, playback: fixture.samples, canPreview: { true })
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
        preview.select(.leo, tone: .direct)
        XCTAssertTrue(preview.isPlaying)
        NotificationCenter.default.post(name: AVAudioSession.routeChangeNotification, object: nil)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(preview.isPlaying)
        preview.select(.maya, tone: .gentle)
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(preview.isPlaying)
        preview.select(.maya, tone: .gentle)
        preview.stop()
        XCTAssertFalse(preview.isPlaying)
    }
    func testJuniorKeepsGentleStyleAndRetiredPolicyCannotSelect() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let live = RemoteVoicePlayback(offlineOnly: true, defaults: defaults, gentleOnly: true)
        var valid = true
        var outputs: [PreviewOutput] = []
        let samples = RemoteVoicePlayback(offlineOnly: true, defaults: defaults, gentleOnly: true, makeAudio: { _ in
            let output = PreviewOutput(); outputs.append(output); return output
        })
        let preview = VoicePreviewCoordinator(preferences: live, playback: samples, permitsSelection: { valid }, canPreview: { true })
        preview.select(.leo, tone: .direct)
        XCTAssertEqual(preview.preference, .leo)
        XCTAssertEqual(live.tone, .gentle)
        XCTAssertEqual(outputs.count, 1)
        preview.stop()
        valid = false
        preview.select(.maya, tone: .gentle)
        XCTAssertEqual(preview.preference, .leo)
        XCTAssertEqual(preview.message, "Reopen this profile to choose your coaching voice.")
        XCTAssertFalse(preview.isPlaying)
        XCTAssertEqual(outputs.count, 1)
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

@MainActor private final class RoutePreviewFixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let suite = "Task9Route." + UUID().uuidString
    let defaults: UserDefaults
    let profile: NativeProfileStore
    let training: TrainingStore
    let voice = RouteHeldVoice()
    let membership: MembershipStore
    var root: SpottrRoot { SpottrRoot(store: training, profileStore: profile, membership: membership) }
    init() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defaults.set("arnold", forKey: "trainer.voice")
        profile = NativeProfileStore(url: directory.appendingPathComponent("profile.json"), preferencesDefaults: defaults)
        try profile.save(LocalProfile(name: "Alex", onboardingRevision: TrainingSetup.revision,
            programmePreferences: .init(goals: [.strength], weekdays: [1], ageContext: .init(ageYears: 30, guardianManaged: false))))
        training = TrainingStore(historyURL: directory.appendingPathComponent("history.json"),
            voicePlayback: RemoteVoicePlayback(offlineOnly: true, defaults: defaults, naturalPlayback: voice), defaults: defaults)
        membership = MembershipStore(root: directory, client: RouteNoPurchaseClient())
    }
    func cleanUp() {
        training.setAccountActive(false); profile.invalidatePolicy()
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
}
@MainActor private final class RouteHeldVoice: VoicePlayback {
    var onFinish: ((UUID) -> Void)?
    var spoken: [VoiceCue] = []
    var stops = 0
    func speak(_ cue: VoiceCue) { spoken.append(cue) }
    func stop() { stops += 1 }
}
@MainActor private final class RouteNoPurchaseClient: MembershipClient {
    func products() async throws -> [MembershipOffer] { [] }
    func currentEntitlements() async -> [MembershipVerification] { [] }
    func updates() -> AsyncStream<MembershipVerification> { AsyncStream { $0.finish() } }
    func purchase(_ plan: MembershipPlan, appAccountToken: UUID) async throws -> MembershipPurchaseResult { .cancelled }
    func restore() async throws {}
    func finish(transactionID: UInt64) async {}
}

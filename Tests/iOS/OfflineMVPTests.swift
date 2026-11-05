import XCTest
@testable import Spottr

@MainActor final class OfflineMVPTests: XCTestCase {
    func testConsumerVoicesNeverDiscoverOrSynthesizeThroughGateway() async throws {
        var attempts = 0
        let local = OfflineRecordingVoice()
        let playback = RemoteVoicePlayback(local: local, offlineOnly: true, defaults: UserDefaults(suiteName: UUID().uuidString)!, client: {
            attempts += 1; throw RemoteVoiceError.configuration
        }, uptime: { 1 })
        try await playback.refreshVoices()
        for voice in [VoiceCoachPreference.maya, .leo, .local, .david] {
            try playback.select(voice)
            playback.speak(.init(id: UUID(), sessionID: UUID(), generation: UUID(), text: "Keep moving", kind: .coaching(.pacing), issuedAt: 1, expiresAt: 5, reason: .steadyRhythm))
            playback.stop()
        }
        XCTAssertEqual(attempts, 0)
        XCTAssertFalse(local.spoken.isEmpty)
    }
    func testNewConfiguredSpeechStartsAtZeroAndManualCorrectionsStopListening() throws {
        let speech = FakeSpokenRepInput()
        let store = TrainingStore(historyURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("history.json"), spokenReps: speech)
        store.start(); store.switchToManualReps(); store.setManualReps(12); store.endSet(); store.finish()
        store.startPlan(try CoachSavedPlan.catalogue(exerciseID: "halfSquat", sets: 1, target: 10, restSeconds: 30), availableSupport: [])
        store.beginConfiguredSet(); store.startSpokenReps()
        XCTAssertEqual(speech.startingCount, 0)
        speech.onCount?(1)
        XCTAssertEqual(store.configured?.actualReps, 1)
        speech.onCount?(4); speech.stop()
        XCTAssertEqual(store.configured?.actualReps, 4)
        XCTAssertTrue(store.configured?.canEndSet(at: store.now) == true)
        store.startSpokenReps()
        store.setConfiguredReps(10)
        XCTAssertFalse(speech.isListening)
        speech.onCount?(2)
        XCTAssertEqual(store.configured?.actualReps, 10)
        store.finish()
    }
    func testOldProfileReopensOnboardingButMeasurementsPreservePlacement() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("profile.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = NativeProfileStore(url: url)
        try store.save(LocalProfile(comfortableExercises: ["wallPushup"], weightManagementGoal: true, onboardingRevision: 0))
        XCTAssertTrue(store.shouldShowIntroduction(environment: [:]))
        try store.saveMeasurements(LocalBodyMeasurements(heightCM: 170, weightKG: 70))
        XCTAssertEqual(store.profile?.comfortableExercises, ["wallPushup"])
        XCTAssertEqual(store.profile?.weightManagementGoal, true)
        XCTAssertEqual(store.profile?.onboardingRevision, 0)
    }
}

@MainActor private final class OfflineRecordingVoice: VoicePlayback {
    var onFinish: ((UUID) -> Void)?
    var spoken: [VoiceCue] = []
    func speak(_ cue: VoiceCue) { spoken.append(cue) }
    func stop() {}
}

@MainActor private final class FakeSpokenRepInput: SpokenRepListening {
    var isListening = false
    var message: String?
    var startingCount: Int?
    var onCount: (@MainActor (Int) -> Void)?
    func start(initialCount: Int, onCount: @escaping @MainActor (Int) -> Void) {
        startingCount = initialCount; self.onCount = onCount; isListening = true
    }
    func stop() { isListening = false }
}

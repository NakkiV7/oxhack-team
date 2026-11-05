import XCTest
import AVFoundation
@testable import Spottr

@MainActor
final class PhoneCaptureRecoveryTests: XCTestCase {
    func testRestFrontCameraNeedsExplicitEnableAndStopsWithoutRestartingTheSet() async throws {
        let camera = TrainingFrontCamera()
        let vision = VisionWorker(cameraAvailable: { true }, requestAccess: { $0(true) }, cameraDriver: camera)
        let store = TrainingStore(historyURL: historyURL(), vision: vision)
        defer { store.finish() }
        store.start()
        store.setRestCameraEnabled(true)
        XCTAssertFalse(store.restCameraEnabled)
        XCTAssertEqual(camera.starts, 0)
        store.endSet()
        let identity = store.session.id, generation = store.session.generation, ended = store.session.sets
        XCTAssertEqual(store.sessionPhase, .rest)
        store.setRestCameraEnabled(true)
        try await waitUntil {
            if case .camera = store.frontPreviewState { return camera.starts == 1 }
            return false
        }
        XCTAssertTrue(store.restCameraEnabled)
        XCTAssertEqual(store.session.id, identity)
        XCTAssertEqual(store.session.generation, generation)
        XCTAssertEqual(store.session.sets, ended)
        store.setRestCameraEnabled(false)
        XCTAssertFalse(store.restCameraEnabled)
        if case .idle = store.frontPreviewState {} else { XCTFail("Disabling must clear rest preview") }
        store.setRestCameraEnabled(true)
        try await waitUntil { camera.starts == 2 }
        store.setAppActive(false)
        XCTAssertFalse(store.restCameraEnabled)
        store.setAppActive(true)
        XCTAssertFalse(store.restCameraEnabled, "Foregrounding cannot reopen the camera")
        store.setRestCameraEnabled(true)
        try await waitUntil { camera.starts == 3 }
        store.next()
        XCTAssertFalse(store.restCameraEnabled)
        XCTAssertEqual(store.sessionPhase, .active)
        XCTAssertEqual(store.session.sets, ended)
    }

    private func historyURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("history.json")
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Camera state did not arrive")
    }

    func testUnavailablePhonePausesLegacyAndWaitingForConfirmationPreservesObservedCount() async throws {
        let vision = VisionWorker(cameraAvailable: { false }, requestAccess: { _ in XCTFail("Unavailable camera must not request access") })
        let store = TrainingStore(historyURL: historyURL(), vision: vision)
        store.start(); store.camera()
        try await waitUntil { store.session.phase == .paused }
        let identity = store.session.id
        store.resume()
        for (time, angle) in [(0.0, 170.0), (0.2, 170), (0.6, 90), (0.8, 90), (1.2, 170), (1.4, 170)] {
            store.session.consume(.init(time: time, angle: angle), generation: store.session.generation)
        }
        store.pause()
        let pausedGeneration = store.session.generation
        await Task.yield()
        XCTAssertEqual(store.session.id, identity)
        XCTAssertEqual(store.session.phase, .paused)
        XCTAssertEqual(store.session.counter.reps, 1)
        XCTAssertEqual(store.session.generation, pausedGeneration)
        XCTAssertTrue(store.session.sets.isEmpty)
        store.switchToManualReps()
        XCTAssertEqual(store.session.actualReps, 1)
        XCTAssertEqual(store.session.counter.reps, 1)
        store.setManualReps(2)
        store.endSet()
        XCTAssertEqual(store.session.sets.last?.source, .manual)
        XCTAssertEqual(store.session.sets.last?.reps, 2)
    }


    func testClearingManualQuantityThenFinishingFromWatchKeepsOnlyPriorEndedSets() async throws {
        let store = TrainingStore(historyURL: historyURL())
        store.start(); store.endSet(); store.next(); store.switchToManualReps()
        let identity = store.session.id
        let ended = store.session.sets
        store.setManualReps(4)
        store.setManualReps(nil)
        store.endSet()
        XCTAssertEqual(store.session.phase, .active)
        XCTAssertEqual(store.session.sets, ended)
        store.companion.onCommand?(.init(sessionID: identity, generation: store.session.generation, action: .finish))
        try await waitUntil { store.session.phase == .finished }
        XCTAssertEqual(store.session.sets, ended)
        XCTAssertEqual(store.history.first?.id, identity)
        XCTAssertEqual(store.history.first?.sets, ended)
    }

}

private final class TrainingFrontCamera: VisionCameraDriving, @unchecked Sendable {
    let capture = AVCaptureSession()
    private let lock = NSLock()
    private var count = 0
    private var stopCount = 0
    var starts: Int { lock.lock(); defer { lock.unlock() }; return count }
    var stops: Int { lock.lock(); defer { lock.unlock() }; return stopCount }
    func start(worker: VisionWorker, queue: DispatchQueue, captureID: UUID) throws {
        lock.lock(); count += 1; lock.unlock()
    }
    func stop() { lock.lock(); stopCount += 1; lock.unlock() }
}

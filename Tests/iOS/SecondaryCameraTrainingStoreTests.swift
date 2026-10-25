import XCTest
import AVFoundation
@testable import Spottr

@MainActor
final class SecondaryCameraTrainingStoreTests: XCTestCase {
    private func historyURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("history.json")
    }

    private func client(received: @escaping (String) -> Void = { _ in },
                        rejectFrames: @escaping () -> Bool = { false }) throws -> SecondaryCameraClient {
        let configuration = try SecondaryCameraConfig(url: "https://camera.local:8765", certificateSHA256: String(repeating: "c", count: 64))
        let captureID = String(repeating: "c", count: 32)
        var sequence = 0
        return try SecondaryCameraClient(configuration: configuration, token: "private-fixture", transport: { request in
            received(request.url!.path)
            var headers: [String: String] = [:]
            let data: Data
            if request.httpMethod == "POST" {
                data = Data((request.url!.path == "/camera/start" ? "{\"capture_id\":\"\(captureID)\",\"lease_seconds\":60}" : #"{"camera":"stopped"}"#).utf8)
            } else {
                if rejectFrames() {
                    return (Data("private-error".utf8), HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!)
                }
                sequence += 1
                data = Data([0xff, 0xd8, 0xff, 0xd9])
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                headers = ["Content-Type": "image/jpeg", "X-Frame-ID": "\(captureID):\(sequence)",
                           "X-Captured-At": formatter.string(from: Date()), "X-Frame-Age-Ms": "0"]
            }
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: headers)!)
        })
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Camera state did not arrive")
    }

    func testSideCameraOwnsFormWhileFrontPreviewFailureRemainsIndependentAndStopsOnPause() async throws {
        let camera = TrainingFrontCamera()
        let vision = VisionWorker(cameraAvailable: { true }, requestAccess: { $0(true) }, cameraDriver: camera,
            makePoseProcessor: { XCTFail("Side-camera preview must not create a second pose detector"); throw CocoaError(.featureUnsupported) })
        let worker = SecondaryCameraVisionWorker(infer: { _, time in
            (PoseFrame(time: time, width: 640, height: 480, points: []), UIImage())
        })
        let transport = try client()
        let store = TrainingStore(historyURL: historyURL(), secondaryVision: worker, secondaryCameraClient: { transport }, vision: vision)
        defer { store.finish() }
        store.start(); store.secondaryCamera()
        try await waitUntil { store.image != nil && camera.starts == 1 }
        if case .camera = store.frontPreviewState {} else { XCTFail("Front preview must be independently visible") }
        let generation = store.session.generation
        vision.onPreviewState?(.denied, generation)
        await Task.yield()
        if case .denied = store.frontPreviewState {} else { XCTFail("Front camera permission failure must be visible") }
        XCTAssertEqual(store.session.phase, .active, "A front preview failure must not stop valid side-camera form tracking")
        XCTAssertNotNil(store.image)
        store.pause()
        XCTAssertEqual(transport.status, .stopped)
        vision.onPreviewState?(.camera, generation)
        await Task.yield()
        if case .idle = store.frontPreviewState {} else { XCTFail("Paused or stale front-camera callbacks must not restore a preview") }
        store.resume()
        try await waitUntil { store.image != nil && camera.starts == 2 }
        store.setAppActive(false)
        XCTAssertEqual(store.session.phase, .paused, "Backgrounding must stop both camera streams until explicit resume")
        XCTAssertEqual(transport.status, .stopped)
        if case .idle = store.frontPreviewState {} else { XCTFail("Front preview must stop in the background") }
        store.resume()
        XCTAssertEqual(store.session.phase, .paused, "Resume must not reopen cameras while the phone is inactive")
        store.companion.onCommand?(.init(sessionID: store.session.id, generation: store.session.generation, action: .resume))
        await Task.yield()
        XCTAssertEqual(store.session.phase, .paused, "Watch Resume must also respect phone camera foreground ownership")
        XCTAssertEqual(transport.status, .stopped)
        XCTAssertEqual(camera.starts, 2)
        store.setAppActive(true)
        XCTAssertEqual(store.session.phase, .paused, "Returning to the app must not restart capture automatically")
        store.resume()
        try await waitUntil { store.image != nil && camera.starts == 3 }
    }

    func testSideCameraRequiresExplicitCaptureAndPauseClearsPreviewBeforeResumingAsCameraHistory() async throws {
        var requests: [String] = []
        let client = try client(received: { requests.append($0) })
        let worker = SecondaryCameraVisionWorker(infer: { _, time in
            (PoseFrame(time: time, width: 640, height: 480, points: []), UIImage())
        })
        defer { worker.stop() }
        let store = TrainingStore(historyURL: historyURL(), secondaryVision: worker, secondaryCameraClient: { client })
        XCTAssertFalse(store.usingSecondaryCamera)
        XCTAssertEqual(worker.state, .idle)
        store.start()
        XCTAssertTrue(requests.isEmpty)

        store.secondaryCamera()
        try await waitUntil { store.image != nil }
        XCTAssertTrue(store.usingSecondaryCamera)
        XCTAssertTrue(store.hasInput)
        XCTAssertEqual(store.source, .camera)
        XCTAssertNotNil(store.frame)
        XCTAssertEqual(store.session.cue, .tracking)
        let firstGeneration = store.session.generation

        store.pause()
        XCTAssertEqual(store.session.phase, .paused)
        XCTAssertNil(store.image)
        XCTAssertNil(store.frame)
        XCTAssertEqual(client.status, .stopped)
        XCTAssertEqual(worker.state, .idle)

        store.resume()
        try await waitUntil { store.image != nil }
        XCTAssertNotEqual(store.session.generation, firstGeneration)
        XCTAssertTrue(store.usingSecondaryCamera)
        store.endSet()
        XCTAssertEqual(store.session.sets.last?.source, .camera)
        XCTAssertNil(store.image)
        XCTAssertNil(store.frame)
        XCTAssertEqual(client.status, .stopped)
        XCTAssertEqual(worker.state, .idle)
    }

    func testReplacingSourceFinishingOrStartingAPlanStopsCaptureAndRejectsOldCallbacks() async throws {
        let plan = try JSONDecoder().decode(CoachSavedPlan.self, from: Data(#"{"items":[{"exerciseID":"wallPushup","sets":1,"target":8,"unit":"reps","restSeconds":30}],"approvedAt":0,"rationale":"Fixture"}"#.utf8))
        let video = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "blank", withExtension: "mp4"))
        let transitions: [(String, (TrainingStore) -> Void)] = [
            ("iPhone camera", { $0.camera() }),
            ("video", { $0.video(video) }),
            ("finish", { $0.finish() }),
            ("new session", { $0.start() }),
            ("manual plan", { $0.startPlan(plan, availableSupport: ["Wall"]) })
        ]
        for (name, transition) in transitions {
            let client = try client()
            let worker = SecondaryCameraVisionWorker(infer: { _, time in
                (PoseFrame(time: time, width: 640, height: 480, points: []), UIImage())
            })
            defer { worker.stop() }
            let store = TrainingStore(historyURL: historyURL(), secondaryVision: worker, secondaryCameraClient: { client })
            store.start(); store.secondaryCamera()
            try await waitUntil { store.image != nil }
            let generation = store.session.generation
            let lateFrame = worker.onFrame
            let lateState = worker.onState

            transition(store)

            XCTAssertEqual(client.status, .stopped, name)
            XCTAssertEqual(worker.state, .idle, name)
            XCTAssertNil(store.image, name)
            XCTAssertNil(store.frame, name)
            lateFrame?(PoseFrame(time: 1, width: 1, height: 1, points: []), UIImage(), generation)
            lateState?(.failed("Old camera failure"), generation)
            XCTAssertNil(store.image, name)
            XCTAssertNil(store.frame, name)
            if store.configured != nil { store.secondaryCamera(); XCTAssertEqual(client.status, .stopped) }
            store.finish()
        }
    }

    func testLostCameraClearsPreviewAndPosePausesAndCanOnlyRestartExplicitly() async throws {
        var reject = false
        let client = try client(rejectFrames: { reject })
        let worker = SecondaryCameraVisionWorker(infer: { _, time in
            (PoseFrame(time: time, width: 640, height: 480, points: []), UIImage())
        })
        defer { worker.stop() }
        let store = TrainingStore(historyURL: historyURL(), secondaryVision: worker, secondaryCameraClient: { client })
        store.start(); store.secondaryCamera()
        try await waitUntil { store.image != nil }
        reject = true
        try await waitUntil { store.session.phase == .paused }

        XCTAssertNil(store.image)
        XCTAssertNil(store.frame)
        XCTAssertEqual(client.status, .stopped)
        guard case .failed(let message) = store.visionState else { return XCTFail("Camera failure must stay visible") }
        XCTAssertFalse(message.contains("private-error"))
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(client.status, .stopped)
        reject = false
        store.resume()
        try await waitUntil { store.image != nil }
        store.finish()
    }

    func testConfirmedManualFallbackAfterPiFailurePreservesHistoryAndRejectsOldAndManualSourceCallbacks() async throws {
        var reject = false
        let client = try client(rejectFrames: { reject })
        let worker = SecondaryCameraVisionWorker(infer: { _, time in
            (PoseFrame(time: time, width: 640, height: 480, points: []), UIImage())
        })
        defer { worker.stop() }
        let store = TrainingStore(historyURL: historyURL(), secondaryVision: worker, secondaryCameraClient: { client })
        store.start(); store.endSet(); store.next(); store.secondaryCamera()
        try await waitUntil { store.image != nil }
        let identity = store.session.id
        let ended = store.session.sets
        let oldGeneration = store.session.generation
        let lateFrame = worker.onFrame
        let lateState = worker.onState
        for (time, angle) in [(0.0, 170.0), (0.2, 170), (0.6, 90), (0.8, 90), (1.2, 170), (1.4, 170)] {
            store.session.consume(.init(time: time, angle: angle), generation: oldGeneration)
        }
        XCTAssertEqual(store.session.counter.reps, 1)
        reject = true
        try await waitUntil { store.session.phase == .paused }
        let pausedGeneration = store.session.generation

        store.switchToManualReps()

        XCTAssertEqual(store.session.id, identity)
        XCTAssertEqual(store.session.sets, ended)
        XCTAssertNotEqual(store.session.generation, pausedGeneration)
        XCTAssertEqual(store.source, .manual)
        XCTAssertFalse(store.hasInput)
        XCTAssertFalse(store.usingSecondaryCamera)
        XCTAssertNil(store.session.actualReps)
        XCTAssertEqual(client.status, .stopped)
        XCTAssertEqual(worker.state, .idle)
        lateFrame?(PoseFrame(time: 2, width: 1, height: 1, points: []), UIImage(), oldGeneration)
        lateState?(.failed("Late camera failure"), oldGeneration)
        store.vision.onFrame?(PoseFrame(time: 3, width: 1, height: 1, points: []), UIImage(), store.session.generation)
        store.vision.onState?(.failed("Wrong source failure"), store.session.generation)
        await Task.yield()
        XCTAssertNil(store.image)
        XCTAssertNil(store.frame)
        XCTAssertEqual(store.session.phase, .active)
        store.endSet()
        XCTAssertEqual(store.session.sets, ended)
        store.setManualReps(4)
        store.endSet()
        store.finish()
        XCTAssertEqual(store.history.first?.id, identity)
        XCTAssertEqual(store.history.first?.sets.map(\.source), [.camera, .manual])
        XCTAssertEqual(store.history.first?.sets.last?.reps, 4)
        XCTAssertNil(store.history.first?.sets.last?.repDurations)
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
        XCTAssertNil(store.session.actualReps)
        XCTAssertEqual(store.session.counter.reps, 0)
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
    var starts: Int { lock.lock(); defer { lock.unlock() }; return count }
    func start(worker: VisionWorker, queue: DispatchQueue, captureID: UUID) throws {
        lock.lock(); count += 1; lock.unlock()
    }
    func stop() {}
}

import XCTest
import AVFoundation
@testable import Spottr

@MainActor
final class SecondaryCameraTrainingStoreTests: XCTestCase {
    func testExplicitLegacyPiReconnectPreservesEndedSetsCurrentRepsAndResetsOnlyUnfinishedMovement() async throws {
        for failure in [false, true] {
            let transport = try client()
            let worker = SecondaryCameraVisionWorker(infer: { _, time in
                (PoseFrame(time: time, width: 640, height: 480, points: []), UIImage())
            })
            let vision = VisionWorker(cameraAvailable: { true }, requestAccess: { _ in })
            let store = TrainingStore(historyURL: historyURL(), secondaryVision: worker, secondaryCameraClient: { transport }, vision: vision)
            defer { worker.stop(); store.cancelCoaching() }
            store.start(); store.switchToManualReps(); store.setManualReps(3); store.endSet(); store.next()
            store.secondaryCamera()
            try await waitUntil { store.image != nil }
            let identity = store.session.id, generation = store.session.generation
            let ended = store.session.sets
            injectSquatRep(worker, generation: generation, start: 0)
            injectSquat(worker, generation: generation, samples: [(2.2, 170), (2.4, 170), (2.8, 90), (3.0, 90)])
            XCTAssertEqual(store.session.counter.reps, 1)
            if failure { worker.onState?(.failed("Synthetic disconnect"), generation) }
            else { store.pause() }
            XCTAssertEqual(store.session.phase, .paused)
            let elapsed = store.session.elapsed(at: store.now)

            store.secondaryCamera()

            XCTAssertEqual(store.session.phase, .active)
            XCTAssertEqual(store.session.id, identity)
            XCTAssertEqual(store.session.sets, ended)
            XCTAssertEqual(store.session.exercise, .squat)
            XCTAssertEqual(store.session.counter.reps, 1, "Reconnect is not a fresh set")
            XCTAssertGreaterThanOrEqual(store.session.elapsed(at: store.now), elapsed)
            XCTAssertNotEqual(store.session.generation, generation)
            worker.onState?(.failed("Old failure"), generation)
            injectSquatRep(worker, generation: generation, start: 4)
            XCTAssertEqual(store.session.phase, .active)
            XCTAssertEqual(store.session.counter.reps, 1)
            let resumed = store.session.generation
            injectSquat(worker, generation: resumed, samples: [(4.0, 170), (4.2, 170)])
            XCTAssertEqual(store.session.counter.reps, 1, "Returning to the top cannot finish a pre-disconnect half-rep")
            injectSquatRep(worker, generation: resumed, start: 4.4)
            XCTAssertEqual(store.session.counter.reps, 2)
            store.endSet(); store.finish()
            XCTAssertEqual(store.history.first?.sets.first, ended.first)
            XCTAssertEqual(store.history.first?.sets.last?.reps, 2)
            XCTAssertEqual(store.history.first?.sets.last?.source, .camera)
            XCTAssertEqual(store.history.first?.sets.last?.repDurations?.count, 2)
        }
    }

    func testConfiguredPiResumePreservesCompletedWorkAndCurrentCounterAfterFailure() async throws {
        let transport = try client()
        let worker = SecondaryCameraVisionWorker(infer: { _, time in
            (PoseFrame(time: time, width: 640, height: 480, points: []), UIImage())
        })
        let vision = VisionWorker(cameraAvailable: { true }, requestAccess: { _ in })
        let store = TrainingStore(historyURL: historyURL(), secondaryVision: worker, secondaryCameraClient: { transport }, vision: vision)
        defer { worker.stop(); store.cancelCoaching() }
        store.startPlan(try CoachSavedPlan.catalogue(exerciseID: "squat", sets: 2, target: 8, restSeconds: 0), availableSupport: [])
        store.beginConfiguredSet(); store.setConfiguredReps(3); store.endSet(); store.next()
        XCTAssertTrue(store.selectConfiguredInput(.secondaryCamera)); store.beginConfiguredSet()
        try await waitUntil { store.image != nil }
        let identity = try XCTUnwrap(store.configured?.id), generation = try XCTUnwrap(store.configured?.generation)
        let ended = store.configured?.completed
        injectSquatRep(worker, generation: generation, start: 0)
        injectSquat(worker, generation: generation, samples: [(2.2, 170), (2.4, 170), (2.8, 90), (3.0, 90)])
        worker.onState?(.failed("Synthetic disconnect"), generation)
        XCTAssertEqual(store.configured?.phase, .paused)
        XCTAssertEqual(store.configured?.actualReps, 1)
        store.resume()
        XCTAssertEqual(store.configured?.id, identity)
        XCTAssertEqual(store.configured?.completed, ended)
        XCTAssertEqual(store.configured?.current.number, 2)
        XCTAssertEqual(store.configured?.actualReps, 1)
        XCTAssertEqual(store.configured?.phase, .active)
        let resumed = try XCTUnwrap(store.configured?.generation)
        XCTAssertNotEqual(resumed, generation)
        injectSquatRep(worker, generation: generation, start: 4)
        worker.onState?(.failed("Old failure"), generation)
        XCTAssertEqual(store.configured?.actualReps, 1)
        XCTAssertEqual(store.configured?.phase, .active)
        injectSquat(worker, generation: resumed, samples: [(4.0, 170), (4.2, 170)])
        XCTAssertEqual(store.configured?.actualReps, 1)
        injectSquatRep(worker, generation: resumed, start: 4.4)
        XCTAssertEqual(store.configured?.actualReps, 2)
        store.endSet(); store.finish()
        XCTAssertEqual(store.history.first?.loggedSets.map(\.reps), [3, 2])
        XCTAssertEqual(store.history.first?.loggedSets.map(\.source), [.manual, .camera])
        XCTAssertEqual(store.history.first?.loggedSets.last?.repDurations?.count, 2)
    }

    func testFrontPreviewToggleStopsOnlyFrontAndCannotRestartPausedSideCapture() async throws {
        let camera = TrainingFrontCamera()
        let vision = VisionWorker(cameraAvailable: { true }, requestAccess: { $0(true) }, cameraDriver: camera,
                                  makePoseProcessor: { throw CocoaError(.featureUnsupported) })
        let transport = try client()
        let worker = SecondaryCameraVisionWorker(infer: { _, time in
            (PoseFrame(time: time, width: 640, height: 480, points: []), UIImage())
        })
        let store = TrainingStore(historyURL: historyURL(), secondaryVision: worker, secondaryCameraClient: { transport }, vision: vision)
        defer { worker.stop(); store.cancelCoaching(); vision.stop() }
        XCTAssertTrue(store.frontCameraEnabled)
        store.start(); store.secondaryCamera()
        try await waitUntil { store.image != nil && camera.starts == 1 }
        let identity = store.session.id, generation = store.session.generation
        injectSquatRep(worker, generation: generation, start: 0)
        let stops = camera.stops
        store.setFrontCameraEnabled(false)
        try await waitUntil { camera.stops > stops }
        XCTAssertFalse(store.frontCameraEnabled)
        if case .idle = store.frontPreviewState {} else { XCTFail("Disabled front preview must be idle") }
        vision.onPreviewState?(.camera, generation)
        await Task.yield()
        if case .idle = store.frontPreviewState {} else { XCTFail("Queued front state cannot revive a disabled preview") }
        XCTAssertEqual(store.session.id, identity)
        XCTAssertEqual(store.session.generation, generation)
        XCTAssertEqual(store.session.phase, .active)
        XCTAssertTrue(store.usingSecondaryCamera)
        injectSquatRep(worker, generation: generation, start: 2.2)
        XCTAssertEqual(store.session.counter.reps, 2)
        store.setFrontCameraEnabled(true)
        try await waitUntil { camera.starts == 2 }
        XCTAssertEqual(store.session.generation, generation)
        XCTAssertEqual(store.session.counter.reps, 2)
        store.pause()
        store.setFrontCameraEnabled(false); store.setFrontCameraEnabled(true)
        await Task.yield()
        XCTAssertEqual(camera.starts, 2)
        XCTAssertEqual(transport.status, .stopped)
        XCTAssertEqual(store.session.phase, .paused)
    }

    private func injectSquatRep(_ worker: SecondaryCameraVisionWorker, generation: UUID, start: Double) {
        let samples: [(Double, Double)] = [(0, 170), (0.2, 170), (0.6, 90), (0.8, 90),
                                            (1.2, 90), (1.4, 90), (1.8, 170), (2, 170)]
        injectSquat(worker, generation: generation, samples: samples.map { (start + $0.0, $0.1) })
    }

    private func injectSquat(_ worker: SecondaryCameraVisionWorker, generation: UUID, samples: [(Double, Double)]) {
        for (time, angle) in samples {
            var points = Array(repeating: PosePoint(x: 0, y: 0, confidence: 0), count: 33)
            points[23] = .init(x: 0.5, y: 0.25, confidence: 1)
            points[25] = .init(x: 0.5, y: 0.5, confidence: 1)
            points[27] = .init(x: 0.5 + sin(angle * .pi / 180) * 0.25,
                               y: 0.5 - cos(angle * .pi / 180) * 0.25, confidence: 1)
            worker.onFrame?(.init(time: time, width: 640, height: 640, points: points), UIImage(), generation)
        }
    }

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
    private var stopCount = 0
    var starts: Int { lock.lock(); defer { lock.unlock() }; return count }
    var stops: Int { lock.lock(); defer { lock.unlock() }; return stopCount }
    func start(worker: VisionWorker, queue: DispatchQueue, captureID: UUID) throws {
        lock.lock(); count += 1; lock.unlock()
    }
    func stop() { lock.lock(); stopCount += 1; lock.unlock() }
}

import XCTest
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
}

import XCTest
@testable import Spottr

@MainActor
final class SecondaryCameraVisionWorkerTests: XCTestCase {
    private let captureID = String(repeating: "b", count: 32)
    private func jpeg() throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "pose", withExtension: "jpg"))
        return try Data(contentsOf: url)
    }
    private func client(jpeg: Data, uptime: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime },
                        received: @escaping (String) -> Void = { _ in }) throws -> SecondaryCameraClient {
        let config = try SecondaryCameraConfig(url: "https://camera.local:8765", certificateSHA256: String(repeating: "b", count: 64))
        var sequence = 0
        return try SecondaryCameraClient(configuration: config, token: "private-fixture", uptime: uptime, transport: { request in
            received(request.url!.path)
            let data: Data
            var headers: [String: String] = [:]
            if request.httpMethod == "POST" {
                data = Data((request.url?.path == "/camera/start" ? "{\"capture_id\":\"\(self.captureID)\",\"lease_seconds\":60}" : #"{"camera":"stopped"}"#).utf8)
            } else {
                sequence += 1; data = jpeg
                let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                headers = ["Content-Type": "image/jpeg", "X-Frame-ID": self.captureID + ":\(sequence)", "X-Captured-At": formatter.string(from: Date()), "X-Frame-Age-Ms": "0"]
            }
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: headers)!)
        })
    }
    func testExplicitStartRunsTheBundledPoseModelOnReceivedJPEGAndPreservesGeneration() async throws {
        let client = try client(jpeg: jpeg())
        let worker = SecondaryCameraVisionWorker()
        let generation = UUID()
        let delivered = expectation(description: "Actual JPEG pose")
        worker.onFrame = { frame, image, token in
            XCTAssertEqual(token, generation)
            XCTAssertEqual(frame.points.count, 33)
            XCTAssertGreaterThan(frame.width, 0)
            XCTAssertGreaterThan(image.size.height, 0)
            delivered.fulfill(); worker.stop()
        }
        XCTAssertEqual(worker.state, .idle)
        worker.start(client: client, generation: generation)
        await fulfillment(of: [delivered], timeout: 10)
        XCTAssertEqual(worker.state, .idle)
        XCTAssertNil(worker.image)
        XCTAssertEqual(client.status, .stopped)
    }
    func testOneInferenceAtATimeAndStopRejectsItsLateResult() async throws {
        var requests = 0
        let client = try client(jpeg: jpeg(), received: { if $0 == "/frame.jpg" { requests += 1 } })
        let entered = expectation(description: "Inference entered")
        var pending: CheckedContinuation<(PoseFrame, UIImage), Error>?
        let worker = SecondaryCameraVisionWorker(infer: { _, time in
            return try await withCheckedThrowingContinuation { pending = $0; entered.fulfill() }
        })
        var delivered = 0
        worker.onFrame = { _, _, _ in delivered += 1 }
        worker.start(client: client, generation: UUID())
        await fulfillment(of: [entered], timeout: 2)
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(requests, 1)
        worker.stop()
        pending?.resume(returning: (PoseFrame(time: 1, width: 1, height: 1, points: []), UIImage()))
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(delivered, 0)
        XCTAssertNil(worker.image)
        XCTAssertEqual(worker.state, .idle)
    }
    func testExpiredFrameDuringInferenceClearsPreviewAndReportsTrackingFailure() async throws {
        var uptime = 100.0
        let client = try client(jpeg: jpeg(), uptime: { uptime })
        let entered = expectation(description: "Inference entered")
        let failed = expectation(description: "Tracking paused")
        var pending: CheckedContinuation<(PoseFrame, UIImage), Error>?
        let worker = SecondaryCameraVisionWorker(infer: { _, _ in
            try await withCheckedThrowingContinuation { pending = $0; entered.fulfill() }
        })
        var delivered = 0
        worker.onFrame = { _, _, _ in delivered += 1 }
        worker.onState = { state, _ in if case .failed = state { failed.fulfill() } }
        worker.start(client: client, generation: UUID())
        await fulfillment(of: [entered], timeout: 2)
        uptime = 103
        await fulfillment(of: [failed], timeout: 2)
        pending?.resume(returning: (PoseFrame(time: 100, width: 1, height: 1, points: []), UIImage()))
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertNil(worker.image)
        XCTAssertEqual(client.status, .stopped)
        XCTAssertEqual(delivered, 0)
        worker.stop()
    }
    func testActiveLoopRenewsTheSameLeaseAndStopsRenewingOnExit() async throws {
        var starts = 0
        let renewed = expectation(description: "Lease renewed")
        let client = try client(jpeg: jpeg(), received: { path in
            if path == "/camera/start" { starts += 1; if starts == 2 { renewed.fulfill() } }
        })
        let worker = SecondaryCameraVisionWorker(renewInterval: 1, infer: { _, time in
            (PoseFrame(time: time, width: 1, height: 1, points: []), UIImage())
        })
        worker.start(client: client, generation: UUID())
        await fulfillment(of: [renewed], timeout: 3)
        worker.stop()
        let stoppedCount = starts
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(starts, stoppedCount)
        XCTAssertEqual(client.status, .stopped)
    }
    func testDecoderFailurePausesTrackingAndStopsCapture() async throws {
        let client = try client(jpeg: Data([0xff, 0xd8, 0xff, 0xd9]))
        let worker = SecondaryCameraVisionWorker()
        let failed = expectation(description: "Invalid JPEG rejected")
        worker.onState = { state, _ in if case .failed = state { failed.fulfill() } }
        worker.start(client: client, generation: UUID())
        await fulfillment(of: [failed], timeout: 3)
        XCTAssertNil(worker.image)
        XCTAssertEqual(client.status, .stopped)
        worker.stop()
    }

    func testReplacingPendingCaptureWaitsForItsReceiptAndMatchingStopBeforeStartingAgain() async throws {
        let oldID = String(repeating: "c", count: 32)
        let entered = expectation(description: "Old capture accepted, receipt pending")
        let stopping = expectation(description: "Old capture stop pending")
        let delivered = expectation(description: "Replacement capture delivered")
        var receipt: CheckedContinuation<(Data, URLResponse), Never>?
        var stop: CheckedContinuation<(Data, URLResponse), Never>?
        var cleanupFinished = false
        var replacementStarts = 0
        let configuration = try SecondaryCameraConfig(url: "https://camera.local:8765", certificateSHA256: String(repeating: "b", count: 64))
        let original = try SecondaryCameraClient(configuration: configuration, token: "private-fixture", transport: { request in
            if request.url?.path == "/camera/start" {
                let result = await withCheckedContinuation { receipt = $0; entered.fulfill() }
                try Task.checkCancellation()
                return result
            }
            XCTAssertEqual(request.url?.path, "/camera/stop")
            XCTAssertEqual((try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: String])?["capture_id"], oldID)
            let result = await withCheckedContinuation { stop = $0; stopping.fulfill() }
            try Task.checkCancellation()
            cleanupFinished = true
            return result
        })
        let replacement = try client(jpeg: jpeg(), received: { path in
            if path == "/camera/start" {
                replacementStarts += 1
                XCTAssertTrue(cleanupFinished)
            }
        })
        let worker = SecondaryCameraVisionWorker(infer: { _, time in
            (PoseFrame(time: time, width: 640, height: 480, points: []), UIImage())
        })
        defer { worker.stop() }
        let generation = UUID()
        worker.onFrame = { _, _, token in
            XCTAssertEqual(token, generation)
            delivered.fulfill()
            worker.stop()
        }
        worker.start(client: original, generation: UUID())
        await fulfillment(of: [entered], timeout: 2)
        worker.start(client: replacement, generation: generation)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(replacementStarts, 0)
        let startURL = URL(string: "https://camera.local:8765/camera/start")!
        receipt?.resume(returning: (Data("{\"capture_id\":\"\(oldID)\",\"lease_seconds\":60}".utf8), HTTPURLResponse(url: startURL, statusCode: 200, httpVersion: nil, headerFields: nil)!))
        await fulfillment(of: [stopping], timeout: 2)
        XCTAssertEqual(replacementStarts, 0)
        XCTAssertEqual(worker.state, .starting)
        let stopURL = URL(string: "https://camera.local:8765/camera/stop")!
        stop?.resume(returning: (Data(#"{"camera":"stopped"}"#.utf8), HTTPURLResponse(url: stopURL, statusCode: 200, httpVersion: nil, headerFields: nil)!))
        await fulfillment(of: [delivered], timeout: 2)
        XCTAssertEqual(replacementStarts, 1)
        XCTAssertEqual(original.status, .stopped)
    }
}

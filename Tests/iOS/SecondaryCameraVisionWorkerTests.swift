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
                        received: @escaping (String) -> Void = { _ in },
                        age: @escaping (Int) -> String = { _ in "0" },
                        repeatFirstFrame: Bool = false,
                        frameFailure: @escaping (Int) throws -> Void = { _ in }) throws -> SecondaryCameraClient {
        let config = try SecondaryCameraConfig(url: "https://camera.local:8765", certificateSHA256: String(repeating: "b", count: 64))
        var sequence = 0
        var frameRequests = 0
        return try SecondaryCameraClient(configuration: config, token: "private-fixture", uptime: uptime, transport: { request in
            received(request.url!.path)
            let data: Data
            var headers: [String: String] = [:]
            if request.httpMethod == "POST" {
                data = Data((request.url?.path == "/camera/start" ? "{\"capture_id\":\"\(self.captureID)\",\"lease_seconds\":60}" : #"{"camera":"stopped"}"#).utf8)
            } else {
                frameRequests += 1
                try frameFailure(frameRequests)
                if !repeatFirstFrame || sequence == 0 { sequence += 1 }; data = jpeg
                let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                headers = ["Content-Type": "image/jpeg", "X-Frame-ID": self.captureID + ":\(sequence)", "X-Captured-At": formatter.string(from: Date()), "X-Frame-Age-Ms": age(sequence)]
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
    func testExpiredInferenceIsDiscardedAndNextFreshFrameRecoversSameLease() async throws {
        var starts = 0
        let client = try client(jpeg: jpeg(), received: { if $0 == "/camera/start" { starts += 1 } },
                                age: { $0 == 1 ? "1950" : "0" })
        let entered = expectation(description: "First inference entered")
        let recovered = expectation(description: "Next fresh frame published")
        var pending: CheckedContinuation<(PoseFrame, UIImage), Error>?
        var inferenceCount = 0
        var failures = 0
        var delivered = 0
        let generation = UUID()
        let worker = SecondaryCameraVisionWorker(infer: { _, time in
            inferenceCount += 1
            if inferenceCount == 1 {
                return try await withCheckedThrowingContinuation { pending = $0; entered.fulfill() }
            }
            return (PoseFrame(time: time, width: 640, height: 360, points: []), UIImage())
        })
        defer { worker.stop() }
        worker.onFrame = { frame, _, token in
            XCTAssertEqual(token, generation)
            XCTAssertNotEqual(frame.time, -1)
            delivered += 1; recovered.fulfill(); worker.stop()
        }
        worker.onState = { state, _ in if case .failed = state { failures += 1 } }
        worker.start(client: client, generation: generation)
        await fulfillment(of: [entered], timeout: 2)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertNil(worker.image)
        XCTAssertNil(worker.frame)
        pending?.resume(returning: (PoseFrame(time: -1, width: 1, height: 1, points: []), UIImage()))
        await fulfillment(of: [recovered], timeout: 2)
        XCTAssertEqual(delivered, 1)
        XCTAssertEqual(failures, 0)
        XCTAssertEqual(starts, 1)
    }

    func testExpiredPublishedPreviewClearsAndPersistentOutageStopsWithinFiveSeconds() async throws {
        let client = try client(jpeg: jpeg(), repeatFirstFrame: true)
        let published = expectation(description: "Initial preview published")
        let failed = expectation(description: "Bounded outage stops capture")
        let worker = SecondaryCameraVisionWorker(infer: { _, time in
            (PoseFrame(time: time, width: 640, height: 360, points: []), UIImage())
        })
        defer { worker.stop() }
        var deliveries = 0
        var failedAt: TimeInterval?
        let began = ProcessInfo.processInfo.systemUptime
        worker.onFrame = { _, _, _ in deliveries += 1; published.fulfill() }
        worker.onState = { state, _ in
            if case .failed = state { failedAt = ProcessInfo.processInfo.systemUptime; failed.fulfill() }
        }
        worker.start(client: client, generation: UUID())
        await fulfillment(of: [published], timeout: 2)
        try await Task.sleep(for: .milliseconds(2300))
        XCTAssertNil(worker.image)
        XCTAssertNil(worker.frame)
        XCTAssertNil(failedAt)
        XCTAssertEqual(client.status, .streaming)
        await fulfillment(of: [failed], timeout: 4)
        XCTAssertLessThan(try XCTUnwrap(failedAt) - began, 6)
        XCTAssertEqual(deliveries, 1)
        XCTAssertEqual(client.status, .stopped)
        XCTAssertNil(worker.image)
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
    func testTransientNetworkLossClearsPublishedPoseAndRecoversWithoutRestartingCapture() async throws {
        for code in [URLError.Code.timedOut, .networkConnectionLost] {
            var starts = 0
            let client = try client(jpeg: jpeg(), received: { if $0 == "/camera/start" { starts += 1 } },
                                    frameFailure: { if $0 == 2 { throw URLError(code) } })
            let recovered = expectation(description: "Fresh frame after transient network failure")
            let cleared = expectation(description: "Previous pose removed during recovery")
            let worker = SecondaryCameraVisionWorker(infer: { _, time in
                (PoseFrame(time: time, width: 640, height: 360, points: []), UIImage())
            })
            var deliveries = 0
            var failures = 0
            worker.onState = { state, _ in
                if state == .starting, deliveries == 1 {
                    XCTAssertNil(worker.image); XCTAssertNil(worker.frame); XCTAssertNil(client.frame)
                    cleared.fulfill()
                }
                if case .failed = state { failures += 1 }
            }
            worker.onFrame = { _, _, _ in
                deliveries += 1
                if deliveries == 2 { recovered.fulfill(); worker.stop() }
            }
            worker.start(client: client, generation: UUID())
            await fulfillment(of: [cleared, recovered], timeout: 3)
            XCTAssertEqual(deliveries, 2)
            XCTAssertEqual(failures, 0)
            XCTAssertEqual(starts, 1)
            worker.stop()
        }
    }

    func testPersistentNetworkTimeoutStopsWithinFiveSecondsWithSanitizedCause() async throws {
        let client = try client(jpeg: jpeg(), frameFailure: { count in
            if count > 1 {
                throw URLError(.timedOut, userInfo: [NSURLErrorFailingURLErrorKey: URL(string: "https://private-camera.local/private-credential")!])
            }
        })
        let failed = expectation(description: "Persistent network outage bounded")
        let worker = SecondaryCameraVisionWorker(infer: { _, time in
            (PoseFrame(time: time, width: 640, height: 360, points: []), UIImage())
        })
        defer { worker.stop() }
        let began = ProcessInfo.processInfo.systemUptime
        var failureMessage: String?
        worker.onState = { state, _ in
            if case .failed(let message) = state { failureMessage = message; failed.fulfill() }
        }
        worker.start(client: client, generation: UUID())
        await fulfillment(of: [failed], timeout: 7)
        let elapsed = ProcessInfo.processInfo.systemUptime - began
        XCTAssertGreaterThan(elapsed, 4.5)
        XCTAssertLessThan(elapsed, 6)
        let message = try XCTUnwrap(failureMessage)
        XCTAssertTrue(message.localizedCaseInsensitiveContains("timed out"))
        XCTAssertFalse(message.contains("private"))
        XCTAssertFalse(message.contains("https"))
        XCTAssertEqual(client.status, .stopped)
        XCTAssertNil(worker.image)
        XCTAssertNil(worker.frame)
    }

}

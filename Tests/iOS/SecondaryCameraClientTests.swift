import XCTest
import Security
import CryptoKit
@testable import Spottr

@MainActor
final class SecondaryCameraClientTests: XCTestCase {
    private let captureID = String(repeating: "a", count: 32)
    private func configuration() throws -> SecondaryCameraConfig {
        try SecondaryCameraConfig(url: "https://camera.local:8765", certificateSHA256: String(repeating: "a", count: 64))
    }
    private func reply(_ request: URLRequest, body: String, status: Int = 200, headers: [String: String] = [:]) -> (Data, URLResponse) {
        (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!)
    }
    func testCaptureOnlyStartsExplicitlyAndStopSendsTheMatchingIdentity() async throws {
        var paths: [String] = []
        let client = try SecondaryCameraClient(configuration: configuration(), token: "private-fixture", transport: { request in
            paths.append(request.url!.path)
            XCTAssertEqual(request.url?.scheme, "https")
            XCTAssertNil(request.url?.query)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer private-fixture")
            XCTAssertEqual(request.httpMethod, "POST")
            if request.url?.path == "/camera/start" {
                XCTAssertEqual(try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: String], [:])
                return self.reply(request, body: "{\"capture_id\":\"\(self.captureID)\",\"lease_seconds\":60}")
            }
            XCTAssertEqual(try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: String], ["capture_id": self.captureID])
            return self.reply(request, body: #"{"camera":"stopped"}"#)
        })
        XCTAssertEqual(client.status, .stopped)
        XCTAssertTrue(paths.isEmpty)
        try await client.start()
        XCTAssertEqual(client.status, .streaming)
        await client.stop()
        XCTAssertEqual(client.status, .stopped)
        XCTAssertEqual(paths, ["/camera/start", "/camera/stop"])
    }
    func testUnauthorizedOrRedirectedStartCannotLeaveCaptureActiveOrExposeBackendBody() async throws {
        for code in [401, 503, 302, 200] {
            let client = try SecondaryCameraClient(configuration: configuration(), token: "private-fixture", transport: { request in
                if code == 200 {
                    return (Data("{\"capture_id\":\"\(self.captureID)\",\"lease_seconds\":60}".utf8),
                            HTTPURLResponse(url: URL(string: "https://another.local/camera/start")!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
                }
                return self.reply(request, body: "private-backend-details", status: code)
            })
            do { try await client.start(); XCTFail("Unsafe response accepted") }
            catch { XCTAssertTrue(error is SecondaryCameraError) }
            XCTAssertEqual(client.status, .unavailable)
            XCTAssertNil(client.captureID)
            XCTAssertFalse(client.errorMessage?.contains("private-backend-details") == true)
        }
    }
    func testStopDuringPendingStartRejectsLateActivationAndClosesThatLease() async throws {
        let entered = expectation(description: "Start entered transport")
        var pending: CheckedContinuation<(Data, URLResponse), Never>?
        var stopIdentity: String?
        let client = try SecondaryCameraClient(configuration: configuration(), token: "private-fixture", transport: { request in
            if request.url?.path == "/camera/start" {
                return await withCheckedContinuation { continuation in pending = continuation; entered.fulfill() }
            }
            stopIdentity = (try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: String])?["capture_id"]
            return self.reply(request, body: #"{"camera":"stopped"}"#)
        })
        let task = Task { try await client.start() }
        await fulfillment(of: [entered], timeout: 2)
        let stop = Task { await client.stop() }
        for _ in 0..<200 {
            if client.status == .stopped { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(client.status, .stopped)
        let request = URLRequest(url: URL(string: "https://camera.local:8765/camera/start")!)
        pending?.resume(returning: reply(request, body: "{\"capture_id\":\"\(captureID)\",\"lease_seconds\":60}"))
        do { try await task.value; XCTFail("Stopped start was revived") }
        catch { XCTAssertTrue(error is CancellationError) }
        await stop.value
        XCTAssertEqual(client.status, .stopped)
        XCTAssertNil(client.captureID)
        XCTAssertEqual(stopIdentity, captureID)
    }
    func testFreshSnapshotsEmitOncePerFrameIdentityAndStopClearsPreview() async throws {
        let now = Date(timeIntervalSince1970: 1792864800.3)
        let jpeg = Data([0xff, 0xd8, 0xff, 0xd9])
        let client = try SecondaryCameraClient(configuration: configuration(), token: "private-fixture", now: { now }, uptime: { 100 }, transport: { request in
            if request.httpMethod == "POST" {
                return self.reply(request, body: request.url?.path == "/camera/start" ? "{\"capture_id\":\"\(self.captureID)\",\"lease_seconds\":60}" : #"{"camera":"stopped"}"#)
            }
            XCTAssertEqual(request.url?.path, "/frame.jpg")
            return (jpeg, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: [
                "Content-Type": "image/jpeg", "X-Frame-ID": self.captureID + ":1", "X-Captured-At": "2026-10-24T18:00:00.000+00:00", "X-Frame-Age-Ms": "100"
            ])!)
        })
        try await client.start()
        let first = try await client.fetchLatestFrame()
        XCTAssertEqual(first?.data, jpeg)
        XCTAssertEqual(first?.metadata.sequence, 1)
        let duplicate = try await client.fetchLatestFrame()
        XCTAssertNil(duplicate)
        XCTAssertNotNil(client.frame)
        await client.stop()
        XCTAssertNil(client.frame)
    }
    func testUnavailableFrameClearsPreviewAndStopsTheMatchingCameraLease() async throws {
        let now = Date(timeIntervalSince1970: 1792864800.3)
        var fetches = 0
        let stopped = expectation(description: "Failed capture cleaned up")
        let client = try SecondaryCameraClient(configuration: configuration(), token: "private-fixture", now: { now }, uptime: { 100 }, transport: { request in
            if request.url?.path == "/camera/start" { return self.reply(request, body: "{\"capture_id\":\"\(self.captureID)\",\"lease_seconds\":60}") }
            if request.url?.path == "/camera/stop" { stopped.fulfill(); return self.reply(request, body: #"{"camera":"stopped"}"#) }
            fetches += 1
            if fetches > 1 { return self.reply(request, body: "private-camera-error", status: 503) }
            return (Data([0xff, 0xd8, 0xff, 0xd9]), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: [
                "Content-Type": "image/jpeg", "X-Frame-ID": self.captureID + ":1", "X-Captured-At": "2026-10-24T18:00:00.000+00:00", "X-Frame-Age-Ms": "100"
            ])!)
        })
        try await client.start()
        _ = try await client.fetchLatestFrame()
        XCTAssertNotNil(client.frame)
        do { _ = try await client.fetchLatestFrame(); XCTFail("Unavailable frame accepted") }
        catch { XCTAssertEqual(error as? SecondaryCameraError, .rejected(503)) }
        XCTAssertNil(client.frame)
        XCTAssertNil(client.captureID)
        XCTAssertEqual(client.status, .unavailable)
        XCTAssertFalse(client.errorMessage?.contains("private-camera-error") == true)
        await fulfillment(of: [stopped], timeout: 2)
    }

    func testExpiredPreviewClearsWithoutEndingLeaseAndNextFreshFrameRecovers() async throws {
        let now = Date(timeIntervalSince1970: 1792864800.3)
        var fetches = 0
        var stops = 0
        let client = try SecondaryCameraClient(configuration: configuration(), token: "private-fixture", now: { now }, transport: { request in
            if request.url?.path == "/camera/start" { return self.reply(request, body: "{\"capture_id\":\"\(self.captureID)\",\"lease_seconds\":60}") }
            if request.url?.path == "/camera/stop" { stops += 1; return self.reply(request, body: #"{"camera":"stopped"}"#) }
            fetches += 1
            return (Data([0xff, 0xd8, 0xff, 0xd9]), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: [
                "Content-Type": "image/jpeg", "X-Frame-ID": self.captureID + ":\(fetches)", "X-Captured-At": "2026-10-24T18:00:00.000+00:00", "X-Frame-Age-Ms": fetches == 1 ? "1950" : "0"
            ])!)
        })
        try await client.start()
        let firstFetch = try await client.fetchLatestFrame()
        let first = try XCTUnwrap(firstFetch)
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertNil(client.frame)
        XCTAssertFalse(client.isCurrent(first))
        XCTAssertEqual(client.captureID, captureID)
        XCTAssertEqual(client.status, .streaming)
        XCTAssertNil(client.errorMessage)
        XCTAssertEqual(stops, 0)
        guard client.status == .streaming else { await client.stop(); return }
        let recoveredFetch = try await client.fetchLatestFrame()
        let recovered = try XCTUnwrap(recoveredFetch)
        XCTAssertEqual(recovered.metadata.sequence, 2)
        XCTAssertTrue(client.isCurrent(recovered))
        XCTAssertFalse(client.isCurrent(first))
        await client.stop()
        XCTAssertEqual(stops, 1)
    }

    func testRenewUsesCurrentCaptureAndRejectsChangedLeaseIdentity() async throws {
        var requests = 0
        let client = try SecondaryCameraClient(configuration: configuration(), token: "private-fixture", transport: { request in
            if request.url?.path == "/camera/stop" { return self.reply(request, body: #"{"camera":"stopped"}"#) }
            requests += 1
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: String]
            XCTAssertEqual(body, requests == 1 ? [:] : ["capture_id": self.captureID])
            let id = requests < 4 ? self.captureID : String(repeating: "b", count: 32)
            return self.reply(request, body: "{\"capture_id\":\"\(id)\",\"lease_seconds\":60}")
        })
        try await client.start()
        try await client.start()
        try await client.renew()
        XCTAssertEqual(client.status, .streaming)
        do { try await client.renew(); XCTFail("Changed capture identity accepted") }
        catch { XCTAssertTrue(error is SecondaryCameraError) }
        XCTAssertEqual(client.status, .unavailable)
        XCTAssertNil(client.frame)
        XCTAssertNil(client.captureID)
    }

    func testDefaultTransportStaysIdleAndRejectsTokensThatCouldInjectHeaders() throws {
        let idle = try SecondaryCameraClient(configuration: configuration(), token: "private-fixture")
        XCTAssertEqual(idle.status, .stopped)
        XCTAssertNil(idle.frame)
        for invalid in ["", "contains space", "fixture\r\nHeader: injected"] {
            XCTAssertThrowsError(try SecondaryCameraClient(configuration: configuration(), token: invalid))
        }
    }

    func testDisconnectRejectsALateFrameAfterAReplacementCaptureStarts() async throws {
        let now = Date(timeIntervalSince1970: 1792864800.3)
        let entered = expectation(description: "Old frame request entered")
        let stopped = expectation(description: "Both leases cleaned up")
        stopped.expectedFulfillmentCount = 2
        var starts = 0
        var pending: CheckedContinuation<(Data, URLResponse), Never>?
        var pendingRequest: URLRequest?
        let replacement = String(repeating: "b", count: 32)
        let client = try SecondaryCameraClient(configuration: configuration(), token: "private-fixture", now: { now }, transport: { request in
            if request.url?.path == "/camera/start" {
                starts += 1
                return self.reply(request, body: "{\"capture_id\":\"\(starts == 1 ? self.captureID : replacement)\",\"lease_seconds\":60}")
            }
            if request.url?.path == "/camera/stop" { stopped.fulfill(); return self.reply(request, body: #"{"camera":"stopped"}"#) }
            pendingRequest = request
            return await withCheckedContinuation { pending = $0; entered.fulfill() }
        })
        try await client.start()
        let old = Task { try await client.fetchLatestFrame() }
        await fulfillment(of: [entered], timeout: 2)
        client.disconnect()
        XCTAssertNil(client.frame)
        XCTAssertEqual(client.status, .stopped)
        try await client.start()
        pending?.resume(returning: (Data([0xff,0xd8,0xff,0xd9]), HTTPURLResponse(url: pendingRequest!.url!, statusCode: 200, httpVersion: nil, headerFields: [
            "Content-Type":"image/jpeg", "X-Frame-ID": captureID + ":1", "X-Captured-At":"2026-10-24T18:00:00.000+00:00", "X-Frame-Age-Ms":"0"
        ])!))
        do { _ = try await old.value; XCTFail("Obsolete frame accepted") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(client.status, .streaming)
        XCTAssertEqual(client.captureID, replacement)
        XCTAssertNil(client.frame)
        await client.stop()
        await fulfillment(of: [stopped], timeout: 2)
    }

    func testInferenceEligibilityUsesLocalFreshnessAndExplicitConnectionState() async throws {
        let now = Date(timeIntervalSince1970: 1792864800.3)
        var uptime: TimeInterval = 100
        let client = try SecondaryCameraClient(configuration: configuration(), token: "private-fixture", now: { now }, uptime: { uptime }, transport: { request in
            if request.httpMethod == "POST" { return self.reply(request, body: request.url?.path == "/camera/start" ? "{\"capture_id\":\"\(self.captureID)\",\"lease_seconds\":60}" : #"{"camera":"stopped"}"#) }
            return (Data([0xff,0xd8,0xff,0xd9]), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: [
                "Content-Type":"image/jpeg", "X-Frame-ID": self.captureID + ":1", "X-Captured-At":"2026-10-24T18:00:00.000+00:00", "X-Frame-Age-Ms":"0"
            ])!)
        })
        try await client.start()
        let fetched = try await client.fetchLatestFrame()
        let snapshot = try XCTUnwrap(fetched)
        XCTAssertTrue(client.isCurrent(snapshot))
        uptime += 2
        XCTAssertFalse(client.isCurrent(snapshot))
        client.disconnect()
        XCTAssertFalse(client.isCurrent(snapshot))
        XCTAssertNil(client.frame)
    }

    func testCancellingPendingStartClosesReturnedLeaseAndLeavesNoError() async throws {
        let entered = expectation(description: "Start pending")
        var pending: CheckedContinuation<(Data, URLResponse), Never>?
        var stopped: String?
        let client = try SecondaryCameraClient(configuration: configuration(), token: "private-fixture", transport: { request in
            if request.url?.path == "/camera/start" {
                return await withCheckedContinuation { pending = $0; entered.fulfill() }
            }
            stopped = (try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: String])?["capture_id"]
            return self.reply(request, body: #"{"camera":"stopped"}"#)
        })
        let task = Task { try await client.start() }
        await fulfillment(of: [entered], timeout: 2)
        task.cancel()
        let request = URLRequest(url: URL(string: "https://camera.local:8765/camera/start")!)
        pending?.resume(returning: reply(request, body: "{\"capture_id\":\"\(captureID)\",\"lease_seconds\":60}"))
        do { try await task.value; XCTFail("Cancelled start accepted") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(stopped, captureID)
        XCTAssertEqual(client.status, .stopped)
        XCTAssertNil(client.errorMessage)
        XCTAssertNil(client.frame)
    }
    func testCancelledPendingFrameCannotRevivePreview() async throws {
        let entered = expectation(description: "Frame pending")
        var pending: CheckedContinuation<(Data, URLResponse), Never>?
        let client = try SecondaryCameraClient(configuration: configuration(), token: "private-fixture", now: { Date(timeIntervalSince1970: 1792864800.3) }, uptime: { 100 }, transport: { request in
            if request.httpMethod == "POST" {
                return self.reply(request, body: request.url?.path == "/camera/start" ? "{\"capture_id\":\"\(self.captureID)\",\"lease_seconds\":60}" : #"{"camera":"stopped"}"#)
            }
            return await withCheckedContinuation { pending = $0; entered.fulfill() }
        })
        try await client.start()
        let task = Task { try await client.fetchLatestFrame() }
        await fulfillment(of: [entered], timeout: 2)
        task.cancel()
        let request = URLRequest(url: URL(string: "https://camera.local:8765/frame.jpg")!)
        pending?.resume(returning: (Data([0xff, 0xd8, 0xff, 0xd9]), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: [
            "Content-Type": "image/jpeg", "X-Frame-ID": captureID + ":1", "X-Captured-At": "2026-10-24T18:00:00.000+00:00", "X-Frame-Age-Ms": "100"
        ])!))
        do { _ = try await task.value; XCTFail("Cancelled frame displayed") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(client.status, .stopped)
        XCTAssertNil(client.frame)
        XCTAssertNil(client.captureID)
    }
    func testDisconnectClearsImmediatelyAndExposesBoundedStopCompletion() async throws {
        let entered = expectation(description: "Stop request pending")
        var pending: CheckedContinuation<(Data, URLResponse), Never>?
        let client = try SecondaryCameraClient(configuration: configuration(), token: "private-fixture", transport: { request in
            if request.url?.path == "/camera/start" {
                return self.reply(request, body: "{\"capture_id\":\"\(self.captureID)\",\"lease_seconds\":60}")
            }
            return await withCheckedContinuation { pending = $0; entered.fulfill() }
        })
        try await client.start()
        let cleanup = client.disconnect()
        XCTAssertEqual(client.status, .stopped)
        XCTAssertNil(client.captureID)
        XCTAssertNotNil(cleanup)
        await fulfillment(of: [entered], timeout: 2)
        let request = URLRequest(url: URL(string: "https://camera.local:8765/camera/stop")!)
        pending?.resume(returning: reply(request, body: #"{"camera":"stopped"}"#))
        await cleanup?.value
        XCTAssertNil(client.disconnect())
    }
    func testCancelledStartNeverContactsThePi() async throws {
        var requests = 0
        let client = try SecondaryCameraClient(configuration: configuration(), token: "private-fixture", transport: { request in
            requests += 1
            return self.reply(request, body: "{\"capture_id\":\"\(self.captureID)\",\"lease_seconds\":60}")
        })
        let task = Task { try await client.start() }
        task.cancel()
        do { try await task.value; XCTFail("Cancelled capture started") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(requests, 0)
        XCTAssertEqual(client.status, .stopped)
        XCTAssertNil(client.errorMessage)
    }

    func testCancelledPendingStartPreservesReceiptAndExposesItsScopedCleanup() async throws {
        let entered = expectation(description: "Server accepted start, response pending")
        var pending: CheckedContinuation<(Data, URLResponse), Never>?
        var stopped: [String] = []
        let client = try SecondaryCameraClient(configuration: configuration(), token: "private-fixture", transport: { request in
            if request.url?.path == "/camera/start" {
                XCTAssertLessThanOrEqual(request.timeoutInterval, 5)
                let result = await withCheckedContinuation { pending = $0; entered.fulfill() }
                try Task.checkCancellation()
                return result
            }
            try Task.checkCancellation()
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: String]
            stopped.append(try XCTUnwrap(body?["capture_id"]))
            return self.reply(request, body: #"{"camera":"stopped"}"#)
        })
        let start = Task { try await client.start() }
        await fulfillment(of: [entered], timeout: 2)
        start.cancel()
        let cleanup = client.disconnect()
        XCTAssertNotNil(cleanup)
        XCTAssertEqual(client.status, .stopped)
        XCTAssertNil(client.captureID)

        let request = URLRequest(url: URL(string: "https://camera.local:8765/camera/start")!)
        pending?.resume(returning: reply(request, body: "{\"capture_id\":\"\(captureID)\",\"lease_seconds\":60}"))
        await cleanup?.value
        do { try await start.value; XCTFail("Cancelled start accepted") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(stopped, [captureID])
        XCTAssertEqual(client.status, .stopped)
        XCTAssertNil(client.errorMessage)
    }

}

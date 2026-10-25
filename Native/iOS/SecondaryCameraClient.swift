import Foundation
import Observation

struct SecondaryCameraFrame: Equatable {
    let data: Data
    let metadata: SecondaryCameraFrameMetadata
    let receivedUptime: TimeInterval
}

@MainActor @Observable
final class SecondaryCameraClient {
    enum Status: Equatable { case stopped, starting, streaming, unavailable }
    typealias Transport = @MainActor (URLRequest) async throws -> (Data, URLResponse)
    private(set) var status: Status = .stopped
    private(set) var captureID: String?
    private(set) var errorMessage: String?
    private(set) var frame: SecondaryCameraFrame?
    @ObservationIgnored private let configuration: SecondaryCameraConfig
    @ObservationIgnored private let token: String
    @ObservationIgnored private let transport: Transport
    @ObservationIgnored private let session: URLSession?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let uptime: () -> TimeInterval
    @ObservationIgnored private var lastSequence: Int64?
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    @ObservationIgnored private var pendingStart: Task<StartReply, Error>?
    @ObservationIgnored private var pendingCleanup: (id: UUID, task: Task<Void, Never>)?

    init(configuration: SecondaryCameraConfig, token: String,
         now: @escaping () -> Date = Date.init,
         uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         transport: Transport? = nil) throws {
        try SecondaryCameraConfig.validateAccessToken(token)
        self.configuration = configuration; self.token = token
        if let transport { self.transport = transport; self.session = nil }
        else {
            let session = SecondaryCameraSessionDelegate.session(configuration: configuration)
            self.session = session
            self.transport = { request in try await session.data(for: request) }
        }
        self.now = now; self.uptime = uptime
    }
    deinit { expiryTask?.cancel(); session?.invalidateAndCancel() }
    func start() async throws {
        try Task.checkCancellation()
        if status == .streaming { try await renew(); return }
        while pendingStart != nil || pendingCleanup != nil {
            if pendingStart != nil { disconnect() }
            await pendingCleanup?.task.value
            try Task.checkCancellation()
        }
        expiryTask?.cancel()
        generation = UUID()
        let attempt = generation
        status = .starting; errorMessage = nil; frame = nil; lastSequence = nil
        let receipt = Task {
            let data = try await self.control("camera/start", body: [:])
            let reply = try JSONDecoder().decode(StartReply.self, from: data)
            guard self.valid(reply) else { throw SecondaryCameraError.invalidResponse }
            return reply
        }
        pendingStart = receipt
        do {
            let reply = try await receipt.value
            guard generation == attempt else {
                await pendingCleanup?.task.value
                throw CancellationError()
            }
            guard !Task.isCancelled else {
                await disconnect()?.value
                throw CancellationError()
            }
            pendingStart = nil
            captureID = reply.capture_id
            status = .streaming
        } catch {
            guard generation == attempt else { throw CancellationError() }
            pendingStart = nil
            if Task.isCancelled || error is CancellationError {
                await disconnect()?.value
                throw CancellationError()
            }
            let failure = (error as? SecondaryCameraError) ?? .invalidResponse
            status = .unavailable; captureID = nil; errorMessage = failure.localizedDescription
            throw failure
        }
    }
    func renew() async throws {
        guard let captureID, status == .streaming else { throw SecondaryCameraError.configuration }
        let attempt = generation
        do {
            let data = try await control("camera/start", body: ["capture_id": captureID])
            guard generation == attempt else { throw CancellationError() }
            let reply = try JSONDecoder().decode(StartReply.self, from: data)
            guard valid(reply), reply.capture_id == captureID else { throw SecondaryCameraError.invalidResponse }
        } catch {
            guard generation == attempt else { throw CancellationError() }
            let failure = (error as? SecondaryCameraError) ?? .invalidResponse
            fail(failure); throw failure
        }
    }
    private func valid(_ reply: StartReply) -> Bool {
        reply.capture_id.count == 32 && reply.capture_id.allSatisfy { "0123456789abcdef".contains($0) }
            && reply.lease_seconds.isFinite && (1...120).contains(reply.lease_seconds)
    }
    func stop() async {
        await disconnect()?.value
    }
    @discardableResult
    func disconnect() -> Task<Void, Never>? {
        let receipt = pendingStart
        pendingStart = nil
        let previous = clear()
        guard previous != nil || receipt != nil else { return pendingCleanup?.task }
        let previousCleanup = pendingCleanup?.task
        let cleanupID = UUID()
        let cleanup = Task {
            await previousCleanup?.value
            defer { if self.pendingCleanup?.id == cleanupID { self.pendingCleanup = nil } }
            let reply = try? await receipt?.value
            guard let identity = previous ?? reply?.capture_id else { return }
            _ = try? await self.control("camera/stop", body: ["capture_id": identity])
        }
        pendingCleanup = (cleanupID, cleanup)
        return cleanup
    }
    func isCurrent(_ candidate: SecondaryCameraFrame) -> Bool {
        status == .streaming && frame?.metadata.frameID == candidate.metadata.frameID
            && uptime() >= candidate.receivedUptime
            && uptime() < candidate.receivedUptime + candidate.metadata.validFor
    }
    private func clear() -> String? {
        expiryTask?.cancel(); expiryTask = nil
        generation = UUID()
        let previous = captureID
        captureID = nil; status = .stopped; frame = nil; lastSequence = nil
        errorMessage = nil
        return previous
    }
    func fetchLatestFrame() async throws -> SecondaryCameraFrame? {
        guard let captureID, status == .streaming else { throw SecondaryCameraError.configuration }
        let attempt = generation
        do {
            try Task.checkCancellation()
            return try await snapshot(captureID: captureID, attempt: attempt)
        } catch {
            guard generation == attempt else { throw CancellationError() }
            if Task.isCancelled || error is CancellationError {
                disconnect()
                throw CancellationError()
            }
            let failure = (error as? SecondaryCameraError) ?? .invalidResponse
            fail(failure)
            throw failure
        }
    }
    private func fail(_ error: SecondaryCameraError) {
        disconnect()
        status = .unavailable; errorMessage = error.localizedDescription
    }
    private func snapshot(captureID: String, attempt: UUID) async throws -> SecondaryCameraFrame? {
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent("frame.jpg"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 2; request.cachePolicy = .reloadIgnoringLocalCacheData
        let began = uptime()
        let (data, response) = try await transport(request)
        try Task.checkCancellation()
        guard generation == attempt else { throw CancellationError() }
        let http = try validated(response, request: request, data: data, limit: 4 * 1024 * 1024)
        guard http.value(forHTTPHeaderField: "Content-Type") == "image/jpeg",
              data.starts(with: [0xff, 0xd8]), data.suffix(2) == Data([0xff, 0xd9]),
              let frameID = http.value(forHTTPHeaderField: "X-Frame-ID"),
              let timestamp = http.value(forHTTPHeaderField: "X-Captured-At"),
              let age = http.value(forHTTPHeaderField: "X-Frame-Age-Ms") else { throw SecondaryCameraError.invalidResponse }
        let metadata = try SecondaryCameraFrameMetadata(frameID: frameID, capturedAt: timestamp,
            serverAgeMilliseconds: age, expectedCaptureID: captureID, receivedAt: now(),
            requestDuration: uptime() - began, afterSequence: lastSequence)
        guard metadata.sequence != lastSequence else { return nil }
        let snapshot = SecondaryCameraFrame(data: data, metadata: metadata, receivedUptime: uptime())
        lastSequence = metadata.sequence; frame = snapshot
        expiryTask?.cancel()
        expiryTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(metadata.validFor * 1_000_000_000)) }
            catch { return }
            guard let self, self.generation == attempt, self.frame?.metadata.frameID == metadata.frameID else { return }
            self.fail(.staleFrame)
        }
        return snapshot
    }
    private func control(_ path: String, body: [String: String]) async throws -> Data {
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"; request.timeoutInterval = 5
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await transport(request)
        _ = try validated(response, request: request, data: data, limit: 4096)
        return data
    }
    private func validated(_ response: URLResponse, request: URLRequest, data: Data, limit: Int) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse, http.url == request.url else { throw SecondaryCameraError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw SecondaryCameraError.rejected(http.statusCode) }
        guard !data.isEmpty, data.count <= limit else { throw SecondaryCameraError.invalidResponse }
        return http
    }
    private struct StartReply: Decodable { let capture_id: String; let lease_seconds: Double }
}

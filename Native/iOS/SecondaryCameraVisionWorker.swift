import UIKit
import Observation

@MainActor @Observable
final class SecondaryCameraVisionWorker {
    enum State: Equatable { case idle, starting, tracking, failed(String) }
    typealias Inference = @MainActor (Data, TimeInterval) async throws -> (PoseFrame, UIImage)
    private(set) var state: State = .idle
    private(set) var image: UIImage?
    private(set) var frame: PoseFrame?
    @ObservationIgnored var onFrame: ((PoseFrame, UIImage, UUID) -> Void)?
    @ObservationIgnored var onState: ((State, UUID) -> Void)?
    @ObservationIgnored private let infer: Inference?
    @ObservationIgnored private let renewInterval: TimeInterval
    @ObservationIgnored private var client: SecondaryCameraClient?
    @ObservationIgnored private var runID: UUID?
    @ObservationIgnored private var generation: UUID?
    @ObservationIgnored private var lastPublished: SecondaryCameraFrame?
    @ObservationIgnored private var lastFreshResultAt: TimeInterval?
    @ObservationIgnored private var lastNetworkFailure: String?
    @ObservationIgnored private var loopTask: Task<Void, Never>?
    @ObservationIgnored private var renewTask: Task<Void, Never>?
    @ObservationIgnored private var watchdogTask: Task<Void, Never>?
    @ObservationIgnored private var pendingStop: Task<Void, Never>?

    init(renewInterval: TimeInterval = 30, infer: Inference? = nil) {
        self.renewInterval = renewInterval.isFinite ? min(30, max(1, renewInterval)) : 30
        self.infer = infer
    }
    deinit { loopTask?.cancel(); renewTask?.cancel(); watchdogTask?.cancel() }

    func start(client: SecondaryCameraClient, generation: UUID) {
        stop()
        let run = UUID(), cleanup = pendingStop
        self.client = client; self.generation = generation; runID = run
        state = .starting; onState?(state, generation)
        guard runID == run else { return }
        let engine = infer == nil ? SecondaryCameraPoseEngine() : nil
        let detect: Inference = infer ?? { data, time in try await engine!.detect(data, at: time) }
        loopTask = Task { [weak self] in
            await cleanup?.value
            guard let self, self.runID == run, !Task.isCancelled else { return }
            do {
                // Fresh video-mode detector per run; model loading precedes camera capture.
                try await engine?.prepare()
                try Task.checkCancellation()
                guard self.runID == run else { return }
                try await client.start()
                guard self.runID == run, !Task.isCancelled else { return }
                self.lastFreshResultAt = ProcessInfo.processInfo.systemUptime
                self.state = .tracking; self.onState?(self.state, generation)
                guard self.runID == run else { return }
                self.watch(client: client, run: run, generation: generation)
                while self.runID == run, !Task.isCancelled {
                    do {
                        if let snapshot = try await client.fetchLatestFrame(), client.isCurrent(snapshot) {
                            let (pose, image) = try await detect(snapshot.data, snapshot.receivedUptime)
                            guard self.runID == run, !Task.isCancelled else { return }
                            if client.isCurrent(snapshot) {
                                self.frame = pose; self.image = image; self.lastPublished = snapshot
                                self.lastFreshResultAt = ProcessInfo.processInfo.systemUptime
                                self.lastNetworkFailure = nil
                                if self.state != .tracking {
                                    self.state = .tracking; self.onState?(self.state, generation)
                                }
                                guard self.runID == run else { return }
                                self.onFrame?(pose, image, generation)
                            } else { self.clearPreview(generation: generation) }
                        }
                    } catch SecondaryCameraError.staleFrame {
                        self.clearPreview(generation: generation)
                    } catch let network as URLError where network.code == .timedOut || network.code == .networkConnectionLost {
                        self.lastNetworkFailure = network.code == .timedOut
                            ? "Pi camera frame requests timed out."
                            : "The Pi camera connection was interrupted."
                        self.clearPreview(generation: generation)
                    }
                    // No backlog: each request waits for its inference, then yields at least 100 ms.
                    try await Task.sleep(for: .milliseconds(100))
                }
            } catch {
                guard self.runID == run else { return }
                self.fail("Pi camera tracking stopped. Check the camera connection and restart capture.", run: run, generation: generation)
            }
        }
    }
    func stop() { clear(emitIdle: true) }
    private func clear(emitIdle: Bool) {
        let previousGeneration = generation
        runID = nil; generation = nil
        loopTask?.cancel(); renewTask?.cancel(); watchdogTask?.cancel()
        loopTask = nil; renewTask = nil; watchdogTask = nil
        image = nil; frame = nil; lastPublished = nil; lastFreshResultAt = nil; lastNetworkFailure = nil
        if let cleanup = client?.disconnect() {
            let previous = pendingStop
            pendingStop = Task { await previous?.value; await cleanup.value }
        }
        client = nil; state = .idle
        if emitIdle, let previousGeneration { onState?(.idle, previousGeneration) }
    }
    private func clearPreview(generation: UUID) {
        image = nil; frame = nil; lastPublished = nil
        guard state != .starting else { return }
        state = .starting; onState?(state, generation)
    }
    private func fail(_ message: String, run: UUID, generation: UUID) {
        guard runID == run else { return }
        clear(emitIdle: false)
        state = .failed(message); onState?(state, generation)
    }
    private func watch(client: SecondaryCameraClient, run: UUID, generation: UUID) {
        renewTask = Task { [weak self] in
            do {
                while let self, self.runID == run {
                    try await Task.sleep(for: .seconds(self.renewInterval))
                    guard self.runID == run, !Task.isCancelled else { return }
                    try await client.renew()
                }
            } catch {
                guard let self, self.runID == run else { return }
                self.fail("Pi camera connection was lost. Restart capture to continue.", run: run, generation: generation)
            }
        }
        watchdogTask = Task { [weak self] in
            do {
                while let self, self.runID == run {
                    try await Task.sleep(for: .milliseconds(100))
                    guard self.runID == run, !Task.isCancelled else { return }
                    let now = ProcessInfo.processInfo.systemUptime
                    guard client.status == .streaming,
                          let lastFreshResultAt = self.lastFreshResultAt,
                          now - lastFreshResultAt < 5 else {
                        let cause = self.lastNetworkFailure ?? "Pi camera has not provided a current result."
                        self.fail(cause + " No current result arrived within 5 seconds. Check the connection and restart capture.", run: run, generation: generation)
                        return
                    }
                    if let preview = self.lastPublished, now >= preview.receivedUptime + preview.metadata.validFor {
                        self.clearPreview(generation: generation)
                    }

                }
            } catch { return }
        }
    }
}

// UIKit decoding and the existing MediaPipe mapping stay off the main actor.
private final class SecondaryCameraPoseEngine: @unchecked Sendable {
    private let queue = DispatchQueue(label: "spottr.secondary-camera.pose", qos: .userInitiated)
    private var detector: PoseDetector?
    func prepare() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do { self.detector = try PoseDetector(); continuation.resume() }
                catch { continuation.resume(throwing: error) }
            }
        }
    }
    func detect(_ data: Data, at time: TimeInterval) async throws -> (PoseFrame, UIImage) {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    guard let image = UIImage(data: data), let detector = self.detector else { throw SecondaryCameraError.invalidResponse }
                    let result = try detector.detect(image, at: time)
                    continuation.resume(returning: (result, image))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
}

import Foundation

public struct WatchCaptureLifecycle: Sendable {
    private enum Stage: Sendable { case authorizing, collecting, ended }
    private var run: UUID?
    private var stage = Stage.ended
    private var motionStream: UUID?
    private var samplesSince = Date.distantPast
    public private(set) var isPaused = false

    public init() {}

    public mutating func start(at date: Date = Date()) -> UUID {
        let token = UUID()
        run = token; stage = .authorizing; isPaused = false; motionStream = nil
        samplesSince = date
        return token
    }

    public func isCurrent(_ token: UUID) -> Bool { run == token }

    public mutating func beginCollection(for token: UUID) -> Bool {
        guard isCurrent(token), stage == .authorizing else { return false }
        stage = .collecting
        return true
    }

    public func acceptsSamples(for token: UUID, measuredAt date: Date? = nil) -> Bool {
        isCurrent(token) && stage == .collecting && !isPaused
            && (date.map { $0.timeIntervalSince1970.isFinite && $0 >= samplesSince } ?? true)
    }

    public mutating func startMotion(for token: UUID) -> UUID? {
        guard acceptsSamples(for: token) else { return nil }
        let stream = UUID()
        motionStream = stream
        return stream
    }

    public func acceptsMotion(for token: UUID, stream: UUID, measuredAt date: Date? = nil) -> Bool {
        acceptsSamples(for: token, measuredAt: date) && motionStream == stream
    }

    public mutating func pause() {
        guard stage != .ended else { return }
        isPaused = true; motionStream = nil
    }

    public mutating func resume(at date: Date = Date()) {
        guard stage != .ended, isPaused else { return }
        isPaused = false
        samplesSince = date
    }

    public mutating func end() {
        stage = .ended; motionStream = nil
    }
}

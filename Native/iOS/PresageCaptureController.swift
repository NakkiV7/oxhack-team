import CoreMedia
import Foundation
import Observation

struct PresageUpdate {
    let samples: [CameraVitalSample]
    let validationOK: Bool
    var failed = false
    var guidance: String? = nil
}

struct PresageFailure: Error { let guidance: String }

@MainActor
protocol PresageDriving: AnyObject {
    var onUpdate: ((PresageUpdate) -> Void)? { get set }
    func start() async throws
    func stop() async
    func submit(_ sample: CMSampleBuffer) -> Bool
}

/// One owner serializes Presage's process-global runtime. Construction never starts capture.
@Observable @MainActor
final class PresageCaptureController {
    enum State: Equatable { case idle, disclosureRequired, stationaryRequired, starting, measuring, completed, unavailable }
    private(set) var state: State = .idle
    private(set) var vitals: CameraVitalsRun?
    private(set) var completedAt: Date?
    private(set) var guidance: String?
    var measurementID: UUID? { vitals?.measurementID }
    private let now: () -> Date
    private let waitForDeadline: () async throws -> Void
    private let makeDriver: (UUID, UUID) throws -> any PresageDriving
    private var driver: (any PresageDriving)?
    private var generation: UUID?
    private var operation: Task<Void, Never>?
    private var deadline: Task<Void, Never>?

    init(now: @escaping () -> Date = Date.init,
         waitForDeadline: @escaping () async throws -> Void = { try await Task.sleep(for: .seconds(30)) },
         makeDriver: @escaping (UUID, UUID) throws -> any PresageDriving) {
        self.now = now; self.waitForDeadline = waitForDeadline; self.makeDriver = makeDriver
    }

    func start(sessionID: UUID, allowAutomaticInsights: Bool, stationary: Bool) async {
        guard state != .starting && state != .measuring else { return }
        completedAt = nil; vitals = nil; guidance = nil
        guard allowAutomaticInsights else { state = .disclosureRequired; return }
        guard stationary else { state = .stationaryRequired; return }
        let id = UUID(), measurement = UUID()
        generation = id
        vitals = .init(sessionID: sessionID, measurementID: measurement, startedAt: now())
        state = .starting
        deadline?.cancel()
        deadline = Task { [weak self, waitForDeadline] in
            do { try await waitForDeadline() } catch { return }
            guard let self, generation == id else { return }
            await complete(generation: id)
        }
        let previous = operation
        let work = Task { [weak self] in
            await previous?.value
            guard let self, generation == id else { return }
            do {
                let next = try makeDriver(sessionID, measurement)
                driver = next
                next.onUpdate = { [weak self] update in
                    guard let self, generation == id else { return }
                    guidance = update.guidance
                    if update.failed {
                        _ = invalidate(as: .unavailable)
                    } else {
                        vitals?.ingest(update.samples, validationOK: update.validationOK,
                                       stationary: true, now: now())
                    }
                }
                try await next.start()
                guard generation == id else {
                    await next.stop()
                    driver = nil
                    return
                }
                state = .measuring
            } catch {
                guard generation == id else {
                    if let driver { await driver.stop(); self.driver = nil }
                    return
                }
                generation = nil; deadline?.cancel(); vitals = nil; completedAt = nil; state = .unavailable
                guidance = (error as? PresageFailure)?.guidance ?? "The camera check couldn’t start."
                if let driver { await driver.stop(); self.driver = nil }
            }
        }
        operation = work
        await work.value
    }

    func submit(_ sample: CMSampleBuffer) -> Bool {
        guard state == .measuring, generation != nil else { return false }
        return driver?.submit(sample) ?? false
    }

    /// Invalidate synchronously before waiting for an in-flight SDK start/stop to settle.
    func stop() async { await invalidate(as: .idle).value }

    private func complete(generation id: UUID) async {
        guard generation == id, state == .starting || state == .measuring else { return }
        generation = nil; deadline = nil; completedAt = now(); state = .completed
        await enqueueStop().value
    }

    private func invalidate(as nextState: State) -> Task<Void, Never> {
        generation = nil; deadline?.cancel(); deadline = nil; vitals = nil; completedAt = nil; state = nextState
        if nextState != .unavailable { guidance = nil }
        return enqueueStop()
    }

    private func enqueueStop() -> Task<Void, Never> {
        let previous = operation
        let work = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            if let driver { await driver.stop(); self.driver = nil }
        }
        operation = work
        return work
    }
}

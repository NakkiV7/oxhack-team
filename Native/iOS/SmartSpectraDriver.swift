import CoreMedia
import Foundation
#if SPOTTR_EXPERIMENTAL_PRESAGE && canImport(SmartSpectra)
import Observation
import SmartSpectra

/// Caller owns the front camera and preview; Pi side-view frames never enter this adapter.
@MainActor
final class SmartSpectraDriver: PresageDriving {
    static let isAvailable = true
    var onUpdate: ((PresageUpdate) -> Void)?
    private let sdk: SmartSpectraSDK
    private let sessionID: UUID
    private let measurementID: UUID
    private var input: CustomInput?
    private var observing = false

    init(apiKey: String, sessionID: UUID, measurementID: UUID) throws {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ConfigurationError.missingKey
        }
        let config = SmartSpectraConfig()
        config.enableTelemetry = false
        config.imageOutputEnabled = false
        config.logLevel = .none
        config.requestedMetrics = [.pulseRate, .breathingRate]
        config.apiKey = apiKey
        sdk = SmartSpectraSDK(config: config)
        self.sessionID = sessionID; self.measurementID = measurementID
    }

    func start() async throws {
        input = try sdk.useCustomInput(frameTransform: .none)
        try await sdk.start()
        observing = true
        observe()
    }

    func stop() async {
        observing = false; input = nil
        try? await sdk.stop()
    }

    func submit(_ sample: CMSampleBuffer) -> Bool {
        guard observing, let input else { return false }
        if case .accepted = input.sendFrame(sample) { return true }
        return false
    }

    private func observe() {
        guard observing else { return }
        let update = withObservationTracking {
            (sdk.metrics,
             sdk.processingStatus == .running && sdk.validationStatus?.code == .ok,
             sdk.error != nil || sdk.processingStatus == .error)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observe() }
        }
        let pulse = update.0?.cardio.pulseRate.suffix(128).map { convert($0, metric: .pulse) } ?? []
        let breathing = update.0?.breathing.rate.suffix(128).map { convert($0, metric: .breathing) } ?? []
        onUpdate?(.init(samples: pulse + breathing, validationOK: update.1, failed: update.2))
    }

    private func convert(_ sample: MeasurementWithConfidence, metric: CameraVitalMetric) -> CameraVitalSample {
        .init(sessionID: sessionID, measurementID: measurementID, metric: metric,
              value: Double(sample.value), date: Date(timeIntervalSince1970: Double(sample.timestamp) / 1_000_000),
              confidence: Double(sample.confidence), stable: sample.stable)
    }

    private enum ConfigurationError: Error { case missingKey }
}

#else
/// Default MVP keeps MediaPipe pose tracking without loading the colliding Presage runtime.
@MainActor
final class SmartSpectraDriver: PresageDriving {
    static let isAvailable = false
    var onUpdate: ((PresageUpdate) -> Void)?
    init(apiKey: String, sessionID: UUID, measurementID: UUID) throws {
        throw PresageBuildUnavailable()
    }
    func start() async throws { throw PresageBuildUnavailable() }
    func stop() async {}
    func submit(_ sample: CMSampleBuffer) -> Bool { false }
}

private struct PresageBuildUnavailable: LocalizedError {
    var errorDescription: String? { "Presage is not included in this build." }
    var recoverySuggestion: String? { "Use Apple Watch readings or continue without camera estimates." }
}
#endif

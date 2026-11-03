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
        config.requestedMetrics = [.pulseRate, .breathingRate, .hrv]
        config.apiKey = apiKey
        sdk = SmartSpectraSDK(config: config)
        self.sessionID = sessionID; self.measurementID = measurementID
    }

    func start() async throws {
        input = try sdk.useCustomInput(frameTransform: .none)
        do { try await sdk.start() }
        catch {
            let code = (error as? SmartSpectraError).map { Int($0.code.rawValue) } ?? 0
            throw PresageFailure(guidance: Self.failureGuidance(code: code))
        }
        observing = true
        observe()
    }

    func stop() async {
        observing = false; input = nil
        try? await sdk.stop()
    }

    func submit(_ sample: CMSampleBuffer) -> Bool {
        guard observing, let input else { return false }
        switch input.sendFrame(sample) {
        case .accepted: return true
        case .rejected(let error):
            onUpdate?(.init(samples: [], validationOK: false, failed: true,
                            guidance: Self.failureGuidance(code: Int(error.code.rawValue))))
            return false
        @unknown default:
            onUpdate?(.init(samples: [], validationOK: false, failed: true,
                            guidance: Self.failureGuidance(code: 0)))
            return false
        }
    }

    private func observe() {
        guard observing else { return }
        let update = withObservationTracking {
            (sdk.metrics,
             sdk.processingStatus == .running && sdk.validationStatus?.code == .ok,
             sdk.error.map { Int($0.code.rawValue) },
             sdk.validationStatus.map { Int($0.code.rawValue) })
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observe() }
        }
        let samples = update.0.map { Self.samples(from: $0, sessionID: sessionID, measurementID: measurementID) } ?? []
        let guidance = update.2.map { Self.failureGuidance(code: $0) } ?? Self.validationGuidance(code: update.3)
        onUpdate?(.init(samples: samples, validationOK: update.1, failed: update.2 != nil, guidance: guidance))
    }

    static func samples(from metrics: Metrics, sessionID: UUID, measurementID: UUID) -> [CameraVitalSample] {
        func sample(_ metric: CameraVitalMetric, _ value: Double, _ timestamp: Int64,
                    _ confidence: Double, _ stable: Bool) -> CameraVitalSample {
            .init(sessionID: sessionID, measurementID: measurementID, metric: metric, value: value,
                  date: Date(timeIntervalSince1970: Double(timestamp) / 1_000_000),
                  confidence: confidence, stable: stable)
        }
        let pulse = metrics.cardio.pulseRate.suffix(64).map {
            sample(.pulse, Double($0.value), $0.timestamp, Double($0.confidence), $0.stable)
        }
        let breathing = metrics.breathing.rate.suffix(64).map {
            sample(.breathing, Double($0.value), $0.timestamp, Double($0.confidence), $0.stable)
        }
        let hrv = metrics.cardio.hrv.suffix(16).flatMap { value in
            [(CameraVitalMetric.hrvRMSSD, value.rmssd), (.hrvSDNN, value.sdnn),
             (.meanNN, value.meanNn), (.stressIndex, value.baevsky)].map {
                sample($0.0, $0.1, value.timestamp, Double(value.confidence), value.stable)
            }
        }
        return pulse + breathing + hrv
    }

    static func failureGuidance(code: Int) -> String {
        switch code {
        case 2: return "Presage authentication failed. Check the API key and connection."
        case 3: return "Presage setup failed. Restart the camera check."
        case 4: return "Presage credits are exhausted. Add credits before trying again."
        case 5, 6: return "Presage could not reach its service. Check the internet connection."
        case 7: return "Presage cannot access camera input. Turn the rest camera off and on."
        case 9: return "Presage could not read the camera frames. Restart the camera check."
        case 10, 11: return "Camera timing was interrupted. Restart the check to begin a fresh measurement."
        default: return "Presage could not complete this check. Continue resting or explicitly try again."
        }
    }
    private static func validationGuidance(code: Int?) -> String {
        switch code {
        case 0: return "Camera signal is valid. Stay still while the measurement warms up."
        case 1: return "Bring your face into view."
        case 2: return "Only one person should be visible."
        case 3, 15, 16: return "Center your face with your upper chest visible."
        case 5: return "Add even light to your face and chest."
        case 6: return "Reduce bright light on your face."
        case 7: return "Move back until your face and upper chest are visible."
        case 10: return "The camera is adjusting. Keep it still."
        case 11: return "Camera frames are arriving too slowly. Close other camera tasks and try again."
        case 12: return "Stay still and avoid talking during this check."
        case 13: return "Move slightly farther from the camera."
        case 14: return "Move slightly closer to the camera."
        case 17: return "Face the camera directly."
        default: return "Looking for a steady face and chest signal."
        }
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

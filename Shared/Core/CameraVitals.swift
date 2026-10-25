import Foundation

public enum CameraVitalMetric: String, Equatable, Sendable { case pulse, breathing }

/// Derived Presage estimates only. Never a Watch reading or a claim of medical readiness.
public struct CameraVitalSample: Equatable, Sendable {
    public let sessionID: UUID
    public let measurementID: UUID
    public let metric: CameraVitalMetric
    public let value: Double
    public let date: Date
    public let confidence: Double
    public let stable: Bool
    public init(sessionID: UUID, measurementID: UUID, metric: CameraVitalMetric,
                value: Double, date: Date, confidence: Double, stable: Bool) {
        self.sessionID = sessionID; self.measurementID = measurementID; self.metric = metric
        self.value = value; self.date = date; self.confidence = confidence; self.stable = stable
    }
}

public struct CameraVitalsRun: Equatable, Sendable {
    public let sessionID: UUID
    public let measurementID: UUID
    public let startedAt: Date
    private var active = true
    private var samples: [CameraVitalMetric: CameraVitalSample] = [:]
    public init(sessionID: UUID, measurementID: UUID = UUID(), startedAt: Date) {
        self.sessionID = sessionID; self.measurementID = measurementID; self.startedAt = startedAt
    }

    /// Called only for an explicit stationary measurement. SDK confidence alone cannot rule out motion errors.
    public mutating func ingest(_ updates: [CameraVitalSample], validationOK: Bool,
                                stationary: Bool, now: Date) {
        guard active, validationOK, stationary else { samples = [:]; return }
        for sample in updates.prefix(256) where qualified(sample, at: now) {
            if let previous = samples[sample.metric], previous.date >= sample.date { continue }
            samples[sample.metric] = sample
        }
    }

    public mutating func stop() { active = false; samples = [:] }
    public func pulse(at date: Date) -> CameraVitalSample? { reading(.pulse, at: date) }
    public func breathing(at date: Date) -> CameraVitalSample? { reading(.breathing, at: date) }

    private func reading(_ metric: CameraVitalMetric, at date: Date) -> CameraVitalSample? {
        guard active, let sample = samples[metric], qualified(sample, at: date) else { return nil }
        return sample
    }

    private func qualified(_ sample: CameraVitalSample, at now: Date) -> Bool {
        let age = now.timeIntervalSince(sample.date)
        let elapsed = sample.date.timeIntervalSince(startedAt)
        let isPulse = sample.metric == .pulse
        return sample.sessionID == sessionID && sample.measurementID == measurementID
            && sample.value.isFinite && sample.confidence.isFinite && sample.stable
            && ((isPulse ? 40.0 : 45.0)...100).contains(sample.confidence)
            && ((isPulse ? 40.0 : 5.0)...(isPulse ? 110.0 : 40.0)).contains(sample.value)
            && age.isFinite && age >= -2 && age <= 5
            && elapsed.isFinite && elapsed >= (isPulse ? 12 : 30)
    }
}

public enum VitalSource: String, Equatable, Sendable { case watch, presage }
public struct DisplayVital: Equatable, Sendable {
    public let value: Double
    public let date: Date
    public let source: VitalSource
}

public struct VitalsDisplay: Equatable, Sendable {
    public let heartRate: DisplayVital?
    public let breathingRate: DisplayVital?
    public init(sessionID: UUID, watch: WatchTelemetry?, camera: CameraVitalsRun?, now: Date) {
        let currentCamera = camera?.sessionID == sessionID ? camera : nil
        if let watch, watch.sessionID == sessionID, let sample = watch.heartRate,
           let value = sample.heartRate(at: now) {
            heartRate = .init(value: value, date: sample.date, source: .watch)
        } else if let pulse = currentCamera?.pulse(at: now) {
            heartRate = .init(value: pulse.value, date: pulse.date, source: .presage)
        } else { heartRate = nil }
        breathingRate = currentCamera?.breathing(at: now).map {
            .init(value: $0.value, date: $0.date, source: .presage)
        }
    }
}

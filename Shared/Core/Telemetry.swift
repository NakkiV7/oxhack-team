import Foundation

public struct SensorReading: Codable, Equatable, Sendable {
    public let value: Double
    public let date: Date
    public init(value: Double, date: Date = Date()) { self.value = value; self.date = date }
    public func heartRate(at now: Date) -> Double? {
        let age = now.timeIntervalSince(date)
        guard value.isFinite, (1...300).contains(value), age >= -2, age <= 12 else { return nil }
        return value
    }
}

public struct ActiveEnergy: Codable, Equatable, Sendable {
    public let recordingID: UUID
    public let kilocalories: Double
    public let asOf: Date
    public init(recordingID: UUID, kilocalories: Double, asOf: Date) {
        self.recordingID = recordingID; self.kilocalories = kilocalories; self.asOf = asOf
    }
    public func isValid(at date: Date) -> Bool {
        kilocalories.isFinite && kilocalories >= 0 && asOf.timeIntervalSince1970.isFinite
            && date.timeIntervalSince1970.isFinite && asOf.timeIntervalSince(date) <= 2
    }
}

public struct WatchMotionWindow: Codable, Equatable, Sendable {
    public let recordingID: UUID
    public let start: Date
    public let end: Date
    public let sampleCount: Int
    public let rmsAccelerationG: Double
    public let peakAccelerationG: Double
    public let meanRotationRadiansPerSecond: Double
    public let peakRotationRadiansPerSecond: Double
    public init(recordingID: UUID, start: Date, end: Date, sampleCount: Int, rmsAccelerationG: Double,
                peakAccelerationG: Double, meanRotationRadiansPerSecond: Double, peakRotationRadiansPerSecond: Double) {
        self.recordingID = recordingID; self.start = start; self.end = end; self.sampleCount = sampleCount
        self.rmsAccelerationG = rmsAccelerationG; self.peakAccelerationG = peakAccelerationG
        self.meanRotationRadiansPerSecond = meanRotationRadiansPerSecond
        self.peakRotationRadiansPerSecond = peakRotationRadiansPerSecond
    }
}

public struct WatchTelemetry: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let sentAt: Date
    public let heartRate: SensorReading?
    public let accelerationG: SensorReading?
    public let rotationRadiansPerSecond: SensorReading?
    public let activeEnergy: ActiveEnergy?
    public let motionWindow: WatchMotionWindow?
    public init(sessionID: UUID, sentAt: Date = Date(), heartRate: SensorReading?, accelerationG: SensorReading?, rotationRadiansPerSecond: SensorReading?, activeEnergy: ActiveEnergy? = nil, motionWindow: WatchMotionWindow? = nil) {
        self.sessionID = sessionID; self.sentAt = sentAt; self.heartRate = heartRate
        self.accelerationG = accelerationG; self.rotationRadiansPerSecond = rotationRadiansPerSecond
        self.activeEnergy = activeEnergy; self.motionWindow = motionWindow
    }
}

public struct WatchTelemetryDeliveryStatus: Equatable, Sendable {
    public let pendingSamples: Int
    public let droppedSamples: Int
    public let message: String?
    public init(pendingSamples: Int = 0, droppedSamples: Int = 0, message: String? = nil) {
        self.pendingSamples = pendingSamples; self.droppedSamples = droppedSamples; self.message = message
    }
}

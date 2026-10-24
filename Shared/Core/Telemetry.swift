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

public struct WatchTelemetry: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let sentAt: Date
    public let heartRate: SensorReading?
    public let accelerationG: SensorReading?
    public let rotationRadiansPerSecond: SensorReading?
    public init(sessionID: UUID, sentAt: Date = Date(), heartRate: SensorReading?, accelerationG: SensorReading?, rotationRadiansPerSecond: SensorReading?) {
        self.sessionID = sessionID; self.sentAt = sentAt; self.heartRate = heartRate
        self.accelerationG = accelerationG; self.rotationRadiansPerSecond = rotationRadiansPerSecond
    }
}

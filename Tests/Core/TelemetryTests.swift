import Foundation
import Testing
@testable import SpottrCore

@Test func heartRateExpiresAndRejectsInvalidValues() {
    let now = Date(timeIntervalSince1970: 100)
    let valid = SensorReading(value: 125, date: now)
    #expect(valid.heartRate(at: now.addingTimeInterval(5)) == 125)
    #expect(valid.heartRate(at: now.addingTimeInterval(20)) == nil)
    #expect(valid.heartRate(at: now.addingTimeInterval(-30)) == nil)
    #expect(SensorReading(value: .nan, date: now).heartRate(at: now) == nil)
    #expect(SensorReading(value: -10, date: now).heartRate(at: now) == nil)
}

@Test func keepsOnlyFreshTelemetryFromThisSession() {
    var session = TrainingSession()
    session.start(at: 0)
    let now = Date()
    let current = WatchTelemetry(sessionID: session.id, sentAt: now, heartRate: .init(value: 125, date: now), accelerationG: nil, rotationRadiansPerSecond: nil)
    session.receiveTelemetry(current, now: now)
    session.receiveTelemetry(current, now: now)
    session.receiveTelemetry(.init(sessionID: UUID(), sentAt: now, heartRate: nil, accelerationG: nil, rotationRadiansPerSecond: nil), now: now)
    session.receiveTelemetry(.init(sessionID: session.id, sentAt: now.addingTimeInterval(-30), heartRate: nil, accelerationG: nil, rotationRadiansPerSecond: nil), now: now)
    #expect(session.record.telemetry.count == 1)
    session.finish(at: 1)
    session.receiveTelemetry(.init(sessionID: session.id, sentAt: now.addingTimeInterval(1), heartRate: nil, accelerationG: nil, rotationRadiansPerSecond: nil), now: now.addingTimeInterval(1))
    #expect(session.record.telemetry.count == 1)
}

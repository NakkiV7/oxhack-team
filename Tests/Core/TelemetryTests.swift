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

@Test func activeEnergyKeepsCumulativeTimingWithoutUsingHeartRateExpiry() {
    let sent = Date(timeIntervalSince1970: 100)
    let run = UUID()
    #expect(ActiveEnergy(recordingID: run, kilocalories: 0, asOf: sent.addingTimeInterval(-60)).isValid(at: sent))
    #expect(ActiveEnergy(recordingID: run, kilocalories: 7, asOf: sent.addingTimeInterval(2)).isValid(at: sent))
    for invalid in [-1, Double.nan, .infinity, -.infinity] {
        #expect(!ActiveEnergy(recordingID: run, kilocalories: invalid, asOf: sent).isValid(at: sent))
    }
    for invalidDate in [sent.addingTimeInterval(3), Date(timeIntervalSince1970: .nan), Date(timeIntervalSince1970: .infinity)] {
        #expect(!ActiveEnergy(recordingID: run, kilocalories: 5, asOf: invalidDate).isValid(at: sent))
    }
    #expect(!ActiveEnergy(recordingID: run, kilocalories: 5, asOf: sent).isValid(at: Date(timeIntervalSince1970: .nan)))
}

@Test func legacyTelemetryStillDecodesAndEnergySurvivesActualLocalHistoryAndExport() throws {
    let id = UUID()
    let legacy = Data("{\"sessionID\":\"\(id.uuidString)\",\"sentAt\":0}".utf8)
    let old = try JSONDecoder().decode(WatchTelemetry.self, from: legacy)
    #expect(old.activeEnergy == nil)
    let energy = ActiveEnergy(recordingID: UUID(), kilocalories: 7.25, asOf: old.sentAt)
    let sample = WatchTelemetry(sessionID: id, sentAt: old.sentAt, heartRate: nil,
                                accelerationG: nil, rotationRadiansPerSecond: nil, activeEnergy: energy)
    let record = SessionRecord(id: id, date: old.sentAt, sets: [], telemetry: [sample])
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = HistoryStore(url: directory.appendingPathComponent("history.json"))
    try store.save(record)
    #expect(try store.load() == [record])
    let export = directory.appendingPathComponent("export.json")
    try store.export(to: export)
    #expect(try JSONDecoder().decode([SessionRecord].self, from: Data(contentsOf: export)) == [record])
    let encodedOld = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any]
    #expect(encodedOld?["activeEnergy"] == nil)
}

@Test func trackingSessionRejectsInvalidOrPriorSessionEnergyWithoutLosingAcceptedHistory() {
    var session = TrainingSession()
    session.start(at: 0)
    let now = session.date.addingTimeInterval(10)
    let run = UUID()
    func message(_ sent: Date, _ energy: ActiveEnergy?) -> WatchTelemetry {
        .init(sessionID: session.id, sentAt: sent, heartRate: nil, accelerationG: nil,
              rotationRadiansPerSecond: nil, activeEnergy: energy)
    }
    let accepted = message(now, .init(recordingID: run, kilocalories: 5, asOf: session.date))
    session.receiveTelemetry(accepted, now: now)
    for energy in [ActiveEnergy(recordingID: run, kilocalories: -1, asOf: now),
                   .init(recordingID: run, kilocalories: .nan, asOf: now),
                   .init(recordingID: run, kilocalories: 8, asOf: now.addingTimeInterval(3)),
                   .init(recordingID: run, kilocalories: 8, asOf: now.addingTimeInterval(10)),
                   .init(recordingID: run, kilocalories: 9, asOf: session.date.addingTimeInterval(-3))] {
        session.receiveTelemetry(message(now.addingTimeInterval(1), energy), now: now)
    }
    #expect(session.record.telemetry == [accepted])
    let later = message(now.addingTimeInterval(2), .init(recordingID: run, kilocalories: 0, asOf: now))
    session.receiveTelemetry(later, now: now.addingTimeInterval(2))
    #expect(session.record.telemetry == [accepted, later])
}

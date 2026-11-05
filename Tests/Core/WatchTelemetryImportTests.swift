import Foundation
import Testing
@testable import SpottrCore
private let importDate=Date(timeIntervalSince1970:1_800_000_000)
private func importPacket(_ id:UUID,offset:Double,value:Double=100) -> WatchTelemetry {
    .init(sessionID:id,sentAt:importDate.addingTimeInterval(offset),heartRate:.init(value:value,date:importDate.addingTimeInterval(offset)),accelerationG:nil,rotationRadiansPerSecond:nil)
}
@Test func lateWatchMergePreservesCountsAndAcceptsOnlyItsKnownRecordedLifetime() throws {
    let id=UUID()
    let record=SessionRecord(id:id,date:importDate,sets:[],telemetry:[importPacket(id,offset:5)],endedAt:importDate.addingTimeInterval(40))
    let merged=try WatchTelemetryImporter.merge([importPacket(id,offset:20),importPacket(id,offset:5)],into:record,through:importDate.addingTimeInterval(100))
    #expect(merged.telemetry.count==2)
    #expect(merged.reps==record.reps)
    #expect(merged.endedAt==record.endedAt)
    #expect(throws:(any Error).self) { try WatchTelemetryImporter.merge([importPacket(UUID(),offset:10)],into:record,through:importDate.addingTimeInterval(100)) }
    #expect(throws:(any Error).self) { try WatchTelemetryImporter.merge([importPacket(id,offset:50)],into:record,through:importDate.addingTimeInterval(100)) }
    let legacy=SessionRecord(id:id,date:importDate,sets:[])
    #expect(throws:(any Error).self) { try WatchTelemetryImporter.merge([importPacket(id,offset:5)],into:legacy,through:importDate.addingTimeInterval(100)) }
}
@Test func partialLatePacketsMergeFieldsAndInvalidSensorsDoNotPoisonOtherReadings() throws {
    let id=UUID(),date=importDate.addingTimeInterval(5)
    let base=SessionRecord(id:id,date:importDate,sets:[],telemetry:[importPacket(id,offset:5)],endedAt:importDate.addingTimeInterval(40))
    let partial=WatchTelemetry(sessionID:id,sentAt:date,heartRate:.init(value:.nan,date:date),accelerationG:.init(value:0.3,date:date),rotationRadiansPerSecond:nil)
    let merged=try WatchTelemetryImporter.merge([partial],into:base,through:importDate.addingTimeInterval(100))
    #expect(merged.telemetry.count==1)
    #expect(merged.telemetry.first?.heartRate?.value==100)
    #expect(merged.telemetry.first?.accelerationG?.value==0.3)
}
@Test func phoneTelemetryInboxSurvivesRestartAndFailedWritesNeverAcknowledgeLoss() throws {
    let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:folder) }
    let inbox=WatchTelemetryInbox(url:folder.appendingPathComponent("inbox.json")),id=UUID(),batch=UUID()
    try inbox.store(id:batch,samples:[importPacket(id,offset:5)])
    try inbox.store(id:batch,samples:[importPacket(id,offset:5)])
    let reopened=WatchTelemetryInbox(url:inbox.url)
    #expect(try reopened.samples(for:id).count==1)
    try reopened.remove(sessionID:id)
    #expect(try reopened.samples(for:id).isEmpty)
    let blocked=folder.appendingPathComponent("blocked")
    try Data("keep".utf8).write(to:blocked)
    let failing=WatchTelemetryInbox(url:blocked.appendingPathComponent("inbox.json"))
    #expect(throws:(any Error).self) { try failing.store(id:batch,samples:[importPacket(id,offset:5)]) }
    #expect(try String(contentsOf:blocked,encoding:.utf8)=="keep")
}
@Test func legacyRecordDecodingKeepsMissingTimelineOptional() throws {
    let old=SessionRecord(id:UUID(),date:importDate,sets:[])
    let roundtrip=try JSONDecoder().decode(SessionRecord.self,from:JSONEncoder().encode(old))
    #expect(roundtrip.endedAt==nil)
    #expect(roundtrip.timeline.isEmpty)
}
@Test func aDelayedBatchKeepsValidReadingsWhenItsTailContinuedPastPhoneFinish() throws {
    let id=UUID(),record=SessionRecord(id:UUID(),date:importDate,sets:[])
    let known=SessionRecord(id:id,date:record.date,sets:[],endedAt:importDate.addingTimeInterval(40))
    let mixed=try WatchTelemetryImporter.merge([importPacket(id,offset:35),importPacket(id,offset:50)],into:known,through:importDate.addingTimeInterval(100))
    #expect(mixed.telemetry.count==1)
    #expect(mixed.telemetry.first?.sentAt==importDate.addingTimeInterval(35))
}

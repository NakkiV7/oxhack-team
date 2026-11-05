import XCTest
@testable import Spottr

@MainActor final class LateWatchTelemetryTests: XCTestCase {
    func testLateDataEnrichesOnlyKnownFinishedHistoryAndDoesNotChangeRecordedWork() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let url=folder.appendingPathComponent("history.json"),start=Date().addingTimeInterval(-120),id=UUID()
        let set=SetRecord(id:UUID(),exercise:.squat,number:1,reps:3,target:3,activeSeconds:6,source:.camera,reserve:nil,reason:.target,repDurations:[2,2,2])
        let record=SessionRecord(id:id,date:start,sets:[set],endedAt:start.addingTimeInterval(60))
        try HistoryStore(url:url).save(record)
        let store=TrainingStore(historyURL:url)
        let packet=WatchTelemetry(sessionID:id,sentAt:start.addingTimeInterval(10),heartRate:.init(value:100,date:start.addingTimeInterval(10)),accelerationG:nil,rotationRadiansPerSecond:nil)
        store.receiveDurableTelemetry(id:UUID(),samples:[packet])
        XCTAssertEqual(store.history.first?.sets,[set])
        XCTAssertEqual(store.history.first?.telemetry.count,1)
        XCTAssertEqual(try HistoryStore(url:url).load().first?.telemetry.count,1)
        store.receiveDurableTelemetry(id:UUID(),samples:[packet])
        XCTAssertEqual(store.history.first?.telemetry.count,1)
    }
    func testFailedLateSaveKeepsOriginalEvidenceAndInboxForRetry() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let url=folder.appendingPathComponent("history.json"),start=Date().addingTimeInterval(-120),id=UUID()
        let record=SessionRecord(id:id,date:start,sets:[],endedAt:start.addingTimeInterval(60))
        try HistoryStore(url:url).save(record)
        let store=TrainingStore(historyURL:url)
        try FileManager.default.removeItem(at:url)
        try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
        let packet=WatchTelemetry(sessionID:id,sentAt:start.addingTimeInterval(10),heartRate:.init(value:100,date:start.addingTimeInterval(10)),accelerationG:nil,rotationRadiansPerSecond:nil)
        store.receiveDurableTelemetry(id:UUID(),samples:[packet])
        XCTAssertEqual(store.history.first,record)
        XCTAssertNotNil(store.archiveDataWarning)
        XCTAssertEqual(try WatchTelemetryInbox(url:folder.appendingPathComponent("watch-inbox.json")).samples(for:id).count,1)
    }
    func testSavedWorkHasAFinishedLifetimeAndPauseTimeline() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let store=TrainingStore(historyURL:folder.appendingPathComponent("history.json"))
        store.start();store.switchToManualReps();store.setManualReps(3);store.pause();store.resume();store.endSet();store.finish()
        let saved=try XCTUnwrap(store.history.first)
        XCTAssertNotNil(saved.endedAt)
        XCTAssertTrue(saved.timeline.contains { $0.phase == .paused })
        XCTAssertEqual(saved.reps,3)
    }
}

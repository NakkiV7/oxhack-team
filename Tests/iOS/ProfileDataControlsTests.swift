import XCTest
@testable import Spottr

@MainActor
final class ProfileDataControlsTests: XCTestCase {
    func testExportAndResetUseSavedHistoryAndResetRejectsUnfinishedWorkouts() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("history.json")
        let store = TrainingStore(historyURL: url)
        let record = try LoggedWorkout.make(exerciseID: "wallPushup", count: 4, sets: 1)
        store.persist(record)
        let original = try Data(contentsOf: url)
        let export = try store.exportHistory()
        defer { try? FileManager.default.removeItem(at: export.deletingLastPathComponent()) }
        XCTAssertEqual(try JSONDecoder().decode([SessionRecord].self, from: Data(contentsOf: export)), [record])
        let externalCopy = folder.appendingPathComponent("saved-copy.json")
        try FileManager.default.copyItem(at: export, to: externalCopy)
        let otherStore = TrainingStore(historyURL: folder.appendingPathComponent("other-profile/history.json"))
        otherStore.persist(record)
        let otherExport = try otherStore.exportHistory()
        defer { try? FileManager.default.removeItem(at: otherExport.deletingLastPathComponent()) }
        store.start()
        XCTAssertThrowsError(try store.clearHistory())
        XCTAssertTrue(FileManager.default.fileExists(atPath: export.path))
        store.pause()
        XCTAssertThrowsError(try store.clearHistory())
        XCTAssertTrue(FileManager.default.fileExists(atPath: export.path))
        store.endSet()
        XCTAssertThrowsError(try store.clearHistory())
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertEqual(store.history, [record])
        store.finish()
        try store.clearHistory()
        XCTAssertTrue(store.history.isEmpty)
        XCTAssertTrue(try HistoryStore(url: url).load().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: export.path))
        XCTAssertEqual(try JSONDecoder().decode([SessionRecord].self, from: Data(contentsOf: externalCopy)), [record])
        XCTAssertEqual(try JSONDecoder().decode([SessionRecord].self, from: Data(contentsOf: otherExport)), [record])
        try store.clearHistory()
        XCTAssertTrue(FileManager.default.fileExists(atPath: externalCopy.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: otherExport.path))
    }
}

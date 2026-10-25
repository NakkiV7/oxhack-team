import XCTest
@testable import Spottr

@MainActor final class TrainingRewardsDataRemovalTests: XCTestCase {
    func testHistoryDeletionRemovesPreparedExportsEvenWhenRewardsResetCannotWrite() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let blocked = folder.appendingPathComponent("blocked")
        try Data("file blocks rewards parent".utf8).write(to: blocked)
        let date = Date(timeIntervalSince1970: 1_792_800_000)
        let rewards = NativeRewardsStore(url: blocked.appendingPathComponent("rewards.json"), createdAt: date)
        let historyURL = folder.appendingPathComponent("history.json")
        let store = TrainingStore(historyURL: historyURL, rewardsStore: rewards)
        let record = try LoggedWorkout.make(exerciseID: "wallPushup", count: 20, sets: 1, date: date)
        store.persist(record, completedAt: date)
        let exported = try store.exportHistory()
        let exportDirectory = historyURL.appendingPathExtension("exports")
        XCTAssertTrue(FileManager.default.fileExists(atPath: exported.path))
        XCTAssertEqual(try HistoryStore(url: historyURL).load(), [record])

        XCTAssertThrowsError(try store.clearHistory(), "The rewards reset failure must remain visible.")

        XCTAssertTrue(store.history.isEmpty)
        XCTAssertTrue(try HistoryStore(url: historyURL).load().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: exportDirectory.path),
                       "Deleting local history must also remove prepared exports when a separate rewards reset fails.")
    }
}

import XCTest
@testable import Spottr

@MainActor
final class TrainingRewardsFlowTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private let start = Date(timeIntervalSince1970: 1_792_800_000)

    func testSavedNewSessionRewardsActualCompletionDayExactlyOnce() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let historyURL = folder.appendingPathComponent("history.json")
        let rewards = NativeRewardsStore(url: folder.appendingPathComponent("rewards.json"), createdAt: start, calendar: calendar)
        try rewards.schedule(startHour: 10, at: start)
        let completion = calendar.startOfDay(for: start).addingTimeInterval(86_400 + 36_001)
        let record = try LoggedWorkout.make(exerciseID: "wallPushup", count: 20, sets: 1, date: start)
        let store = TrainingStore(historyURL: historyURL, rewardsStore: rewards)

        store.persist(record, completedAt: completion)
        store.persist(record, completedAt: completion.addingTimeInterval(86_400))

        XCTAssertNil(store.error)
        XCTAssertEqual(store.history, [record])
        XCTAssertEqual(try HistoryStore(url: historyURL).load(), [record])
        XCTAssertTrue(store.rewards === rewards)
        XCTAssertEqual(rewards.ledger.events.count, 1)
        XCTAssertEqual(rewards.ledger.events.first?.completedAt, completion)
        XCTAssertEqual(rewards.ledger.events.first?.day, calendar.startOfDay(for: completion))
        XCTAssertEqual(rewards.totalXP(history: store.history), 20)
        XCTAssertEqual(rewards.summary(history: store.history, at: completion).actualTrainingDays, 1)
    }

    func testHistoryWriteFailureDoesNotAwardOrPublishSavedHistory() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let rewardsURL = folder.appendingPathComponent("rewards.json")
        let rewards = NativeRewardsStore(url: rewardsURL, createdAt: start, calendar: calendar)
        try rewards.schedule(startHour: 10, at: start)
        let savedRewards = try Data(contentsOf: rewardsURL)
        let blocked = folder.appendingPathComponent("blocked")
        try Data("file blocks history parent".utf8).write(to: blocked)
        let historyURL = blocked.appendingPathComponent("history.json")
        let store = TrainingStore(historyURL: historyURL, rewardsStore: rewards)
        let record = try LoggedWorkout.make(exerciseID: "wallPushup", count: 20, sets: 1, date: start)

        store.persist(record, completedAt: start)

        XCTAssertTrue(store.history.isEmpty)
        XCTAssertNotNil(store.error)
        XCTAssertTrue(rewards.ledger.events.isEmpty)
        XCTAssertEqual(try Data(contentsOf: rewardsURL), savedRewards)
        XCTAssertFalse(FileManager.default.fileExists(atPath: historyURL.path))
    }

    func testRewardsWriteFailureKeepsSavedWorkoutAndExplainsPartialSuccess() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let blocked = folder.appendingPathComponent("blocked")
        try Data("file blocks rewards parent".utf8).write(to: blocked)
        let rewards = NativeRewardsStore(url: blocked.appendingPathComponent("rewards.json"), createdAt: start, calendar: calendar)
        let historyURL = folder.appendingPathComponent("history.json")
        let store = TrainingStore(historyURL: historyURL, rewardsStore: rewards)
        let record = try LoggedWorkout.make(exerciseID: "wallPushup", count: 20, sets: 1, date: start)

        store.persist(record, completedAt: start)

        XCTAssertEqual(store.history, [record])
        XCTAssertEqual(try HistoryStore(url: historyURL).load(), [record])
        XCTAssertTrue(rewards.ledger.events.isEmpty)
        let message = try XCTUnwrap(store.error).lowercased()
        XCTAssertTrue(message.contains("saved"), message)
        XCTAssertTrue(message.contains("reward"), message)
    }

    func testExplicitHistoryClearResetsRewardsIncludingCorruptionButUnfinishedWorkoutBlocksBoth() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let historyURL = folder.appendingPathComponent("history.json")
        let rewardsURL = folder.appendingPathComponent("rewards.json")
        let rewards = NativeRewardsStore(url: rewardsURL, createdAt: start, calendar: calendar)
        let store = TrainingStore(historyURL: historyURL, rewardsStore: rewards)
        let record = try LoggedWorkout.make(exerciseID: "wallPushup", count: 20, sets: 1, date: start)
        store.persist(record, completedAt: start)
        let savedHistory = try Data(contentsOf: historyURL)
        let savedRewards = try Data(contentsOf: rewardsURL)

        store.session.start(at: 0)
        XCTAssertThrowsError(try store.clearHistory())
        store.session.pause(at: 1)
        XCTAssertThrowsError(try store.clearHistory())
        XCTAssertEqual(try Data(contentsOf: historyURL), savedHistory)
        XCTAssertEqual(try Data(contentsOf: rewardsURL), savedRewards)
        store.session.finish(at: 2)
        try store.clearHistory()
        XCTAssertTrue(store.history.isEmpty)
        XCTAssertTrue(rewards.ledger.events.isEmpty)
        XCTAssertEqual(rewards.ledger.remainingFreezes, 2)

        try HistoryStore(url: historyURL).save(record)
        try Data("unreadable rewards".utf8).write(to: rewardsURL)
        let corrupt = NativeRewardsStore(url: rewardsURL, createdAt: start, calendar: calendar)
        XCTAssertNotNil(corrupt.loadError)
        let recovery = TrainingStore(historyURL: historyURL, rewardsStore: corrupt)
        XCTAssertEqual(recovery.history, [record])
        try recovery.clearHistory()
        XCTAssertNil(corrupt.loadError)
        XCTAssertTrue(recovery.history.isEmpty)
        XCTAssertTrue(try HistoryStore(url: historyURL).load().isEmpty)
        let reloaded = NativeRewardsStore(url: rewardsURL, createdAt: start, calendar: calendar)
        XCTAssertNil(reloaded.loadError)
        XCTAssertTrue(reloaded.ledger.events.isEmpty)
        XCTAssertEqual(reloaded.ledger.remainingFreezes, 2)
    }
}

import XCTest
@testable import Spottr

@MainActor
final class TrainingRewardsLoadFailureTests: XCTestCase {
    func testRecoveredHistoryUsesPersistedBeforeStateForTheRemainingDailyBonus() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "RewardsRecovery-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let created = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-25T10:00:00Z"))
        let completion = created.addingTimeInterval(86_401)
        let previous = try LoggedWorkout.make(exerciseID: "wallPushup", count: 20, sets: 2, date: completion.addingTimeInterval(-1_800))
        let record = try LoggedWorkout.make(exerciseID: "wallPushup", count: 20, sets: 3, date: completion)
        let historyURL = folder.appendingPathComponent("history.json")
        try HistoryStore(url: historyURL).save(previous)
        let savedHistory = try Data(contentsOf: historyURL)
        let rewards = NativeRewardsStore(url: folder.appendingPathComponent("rewards.json"), createdAt: created, calendar: calendar)
        try rewards.schedule(startHour: 10, at: created)
        try Data("temporarily unreadable history".utf8).write(to: historyURL)
        let store = TrainingStore(historyURL: historyURL, rewardsStore: rewards, defaults: defaults)
        XCTAssertNotNil(store.error)
        XCTAssertTrue(store.history.isEmpty)
        try savedHistory.write(to: historyURL, options: .atomic)

        store.persist(record, completedAt: completion)

        XCTAssertNil(store.error)
        XCTAssertTrue(store.historyAvailable)
        XCTAssertEqual(store.history, [record, previous])
        XCTAssertEqual(try HistoryStore(url: historyURL).load(), [previous, record])
        XCTAssertEqual(rewards.ledger.events.map(\.sessionID), [record.id])
        XCTAssertEqual(rewards.ledger.events.first?.baseXP, 10)
        XCTAssertEqual(rewards.ledger.totalBonusXP, 10)
        XCTAssertEqual(rewards.totalXP(history: store.history), 40)
    }

    func testUnreadableHistoryRefreshPreservesEarnedRewardsUntilHistoryIsRestored() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "RewardsLoadFailure-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let created = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-25T10:00:00Z"))
        let completedAt = created.addingTimeInterval(86_401)
        let record = try LoggedWorkout.make(exerciseID: "wallPushup", count: 20, sets: 1, date: created)
        let historyURL = folder.appendingPathComponent("history.json")
        let rewardsURL = folder.appendingPathComponent("rewards.json")
        try HistoryStore(url: historyURL).save(record)
        let savedHistory = try Data(contentsOf: historyURL)
        let rewards = NativeRewardsStore(url: rewardsURL, createdAt: created, calendar: calendar)
        try rewards.schedule(startHour: 10, at: created)
        try rewards.award(record: record, before: [], history: [record], completedAt: completedAt)
        let savedRewards = try Data(contentsOf: rewardsURL)
        XCTAssertEqual(rewards.ledger.totalBonusXP, 10)
        let unreadable = Data("unreadable saved history".utf8)
        try unreadable.write(to: historyURL)
        let store = TrainingStore(historyURL: historyURL, rewardsStore: rewards, defaults: defaults)
        XCTAssertNotNil(store.error)
        XCTAssertTrue(store.history.isEmpty)

        store.refreshRewards(at: completedAt)

        XCTAssertEqual(try Data(contentsOf: rewardsURL), savedRewards)
        XCTAssertEqual(rewards.ledger.events.map(\.sessionID), [record.id])
        XCTAssertEqual(rewards.ledger.totalBonusXP, 10)
        XCTAssertEqual(try Data(contentsOf: historyURL), unreadable)
        XCTAssertNotNil(store.error)

        try savedHistory.write(to: historyURL, options: .atomic)
        let restoredRewards = NativeRewardsStore(url: rewardsURL, createdAt: completedAt, calendar: calendar)
        let restored = TrainingStore(historyURL: historyURL, rewardsStore: restoredRewards, defaults: defaults)
        XCTAssertNil(restored.error)
        XCTAssertEqual(restored.history, [record])
        XCTAssertEqual(restoredRewards.ledger.events.first?.completedAt, completedAt)
        XCTAssertEqual(restoredRewards.totalXP(history: restored.history), 20)
        XCTAssertEqual(restoredRewards.summary(history: restored.history, at: completedAt).actualTrainingDays, 1)
    }
}

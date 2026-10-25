import XCTest
@testable import Spottr

@MainActor final class NativeRewardsTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private let start = Date(timeIntervalSince1970: 1_792_800_000)

    func testNextDayWindowAndCompletionBonusSurviveReloadWithoutBackfillingHistory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("rewards.json")
        let store = NativeRewardsStore(url: url, createdAt: start, calendar: calendar)
        try store.schedule(startHour: 10, at: start)
        XCTAssertNil(store.ledger.window(at: start))
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: start)))
        let completedAt = tomorrow.addingTimeInterval(10 * 3_600 + 1)
        let record = try LoggedWorkout.make(exerciseID: "wallPushup", count: 20, sets: 1, date: completedAt)
        try store.award(record: record, before: [], history: [record], completedAt: completedAt)
        try store.award(record: record, before: [record], history: [record], completedAt: completedAt)
        let reloaded = NativeRewardsStore(url: url, createdAt: completedAt, calendar: calendar)
        XCTAssertEqual(reloaded.ledger.events.count, 1)
        XCTAssertEqual(reloaded.ledger.totalBonusXP, 10)
        XCTAssertEqual(reloaded.totalXP(history: [record]), 20)
        XCTAssertTrue(reloaded.summary(history: [record], at: completedAt).trainedToday)
        let historic = try LoggedWorkout.make(exerciseID: "wallPushup", count: 20, sets: 1, date: start.addingTimeInterval(-86_400))
        try reloaded.award(record: historic, before: [historic, record], history: [historic, record], completedAt: completedAt)
        XCTAssertEqual(reloaded.ledger.events.count, 1)
        XCTAssertEqual(reloaded.ledger.totalBonusXP, 10)
    }

    func testCorruptRewardsArePreservedAndCannotBeSilentlyOverwritten() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("rewards.json")
        let original = Data("unreadable rewards".utf8)
        try original.write(to: url)
        let store = NativeRewardsStore(url: url, createdAt: start, calendar: calendar)
        XCTAssertNotNil(store.loadError)
        XCTAssertThrowsError(try store.schedule(startHour: 10, at: start))
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertTrue(store.ledger.windowChanges.isEmpty)
    }

    func testFailedSaveLeavesTheActiveWindowUnchangedAndCanBeRetried() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let blocked = directory.appendingPathComponent("blocked")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("file blocks parent folder".utf8).write(to: blocked)
        let store = NativeRewardsStore(url: blocked.appendingPathComponent("rewards.json"), createdAt: start, calendar: calendar)
        XCTAssertThrowsError(try store.schedule(startHour: 10, at: start))
        XCTAssertTrue(store.ledger.windowChanges.isEmpty)
        try FileManager.default.removeItem(at: blocked)
        try store.schedule(startHour: 10, at: start)
        XCTAssertEqual(store.ledger.windowChanges.first?.window.startHour, 10)
    }

    func testFailedAwardDoesNotPublishAndRetryUsesOriginalCompletion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let backup = directory.appendingPathExtension("backup")
        defer { try? FileManager.default.removeItem(at: directory); try? FileManager.default.removeItem(at: backup) }
        let url = directory.appendingPathComponent("rewards.json")
        let store = NativeRewardsStore(url: url, createdAt: start, calendar: calendar)
        try store.schedule(startHour: 10, at: start)
        let saved = try Data(contentsOf: url)
        let completion = calendar.startOfDay(for: start).addingTimeInterval(86_400 + 36_001)
        let record = try LoggedWorkout.make(exerciseID: "wallPushup", count: 20, sets: 1, date: completion)
        try FileManager.default.moveItem(at: directory, to: backup)
        try Data("blocked parent".utf8).write(to: directory)
        XCTAssertThrowsError(try store.award(record: record, before: [], history: [record], completedAt: completion))
        XCTAssertTrue(store.ledger.events.isEmpty)
        XCTAssertEqual(store.ledger.totalBonusXP, 0)
        XCTAssertEqual(try Data(contentsOf: backup.appendingPathComponent("rewards.json")), saved)
        try FileManager.default.removeItem(at: directory)
        try FileManager.default.moveItem(at: backup, to: directory)
        try store.award(record: record, before: [], history: [record], completedAt: completion)
        XCTAssertEqual(store.ledger.events.map(\.completedAt), [completion])
        XCTAssertEqual(store.ledger.totalBonusXP, 10)
    }

    func testReloadKeepsOriginalCalendarAndCreationDate() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("rewards.json")
        var pinned = calendar
        pinned.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let store = NativeRewardsStore(url: url, createdAt: start, calendar: pinned)
        try store.schedule(startHour: 10, at: start)
        let reloaded = NativeRewardsStore(url: url, createdAt: start.addingTimeInterval(86_400), calendar: calendar)
        XCTAssertEqual(reloaded.ledger.calendar.timeZone, pinned.timeZone)
        XCTAssertEqual(reloaded.ledger.createdAt, start)
        XCTAssertEqual(reloaded.ledger.windowChanges, store.ledger.windowChanges)
    }

    func testExistingDailyCapRecordsActivityWithoutExtraBaseOrBonus() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NativeRewardsStore(url: directory.appendingPathComponent("rewards.json"), createdAt: start, calendar: calendar)
        try store.schedule(startHour: 10, at: start)
        let completion = calendar.startOfDay(for: start).addingTimeInterval(86_400 + 36_001)
        let prior = try LoggedWorkout.make(exerciseID: "wallPushup", count: 20, sets: 3, date: completion.addingTimeInterval(-1))
        let record = try LoggedWorkout.make(exerciseID: "wallPushup", count: 20, sets: 1, date: completion)
        try store.award(record: record, before: [prior], history: [prior, record], completedAt: completion)
        XCTAssertEqual(store.ledger.events.first?.baseXP, 0)
        XCTAssertEqual(store.ledger.events.first?.bonusXP, 0)
        XCTAssertEqual(store.totalXP(history: [prior, record]), 30)
        XCTAssertTrue(store.summary(history: [prior, record], at: completion).trainedToday)
    }

    func testAwardRequiresTheExactSuccessfullySavedNewRecord() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NativeRewardsStore(url: directory.appendingPathComponent("rewards.json"), createdAt: start, calendar: calendar)
        let record = try LoggedWorkout.make(exerciseID: "wallPushup", count: 20, sets: 1, date: start)
        XCTAssertThrowsError(try store.award(record: record, before: [], history: [], completedAt: start))
        let different = SessionRecord(id: record.id, date: start, sets: [])
        XCTAssertThrowsError(try store.award(record: record, before: [], history: [different], completedAt: start))
        XCTAssertTrue(store.ledger.events.isEmpty)
    }

    func testOvernightCompletionUsesCompletionDayWithoutDuplicatingStartDay() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NativeRewardsStore(url: directory.appendingPathComponent("rewards.json"), createdAt: start, calendar: calendar)
        let completion = calendar.startOfDay(for: start).addingTimeInterval(86_401)
        let record = try LoggedWorkout.make(exerciseID: "wallPushup", count: 20, sets: 1, date: start)
        try store.award(record: record, before: [], history: [record], completedAt: completion)
        let summary = store.summary(history: [record], at: completion)
        XCTAssertEqual(summary.actualTrainingDays, 1)
        XCTAssertEqual(summary.protectedStreak, 1)
        XCTAssertTrue(summary.trainedToday)
        XCTAssertEqual(store.ledger.events.first?.day, calendar.startOfDay(for: completion))
    }

    func testRemovedHistoryCannotLeavePhantomRewardsAndReadsDoNotRewriteLedger() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("rewards.json")
        let store = NativeRewardsStore(url: url, createdAt: start, calendar: calendar)
        try store.schedule(startHour: 10, at: start)
        let firstTime = calendar.startOfDay(for: start).addingTimeInterval(86_400 + 36_001)
        let secondTime = firstTime.addingTimeInterval(86_400)
        let first = try LoggedWorkout.make(exerciseID: "wallPushup", count: 20, sets: 1, date: firstTime)
        let second = try LoggedWorkout.make(exerciseID: "wallPushup", count: 20, sets: 1, date: secondTime)
        try store.award(record: first, before: [], history: [first], completedAt: firstTime)
        try store.award(record: second, before: [first], history: [first, second], completedAt: secondTime)
        let saved = try Data(contentsOf: url)
        XCTAssertEqual(store.totalXP(history: [second]), 20)
        XCTAssertEqual(store.summary(history: [second], at: secondTime).protectedStreak, 1)
        XCTAssertEqual(store.totalXP(history: []), 0)
        XCTAssertEqual(store.summary(history: [], at: secondTime).actualTrainingDays, 0)
        XCTAssertEqual(store.ledger.events.count, 2)
        XCTAssertEqual(try Data(contentsOf: url), saved)
    }

    func testExplicitResetClearsCorruptionOnlyAfterSuccessfulWrite() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let backup = directory.appendingPathExtension("backup")
        defer { try? FileManager.default.removeItem(at: directory); try? FileManager.default.removeItem(at: backup) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("rewards.json")
        let corrupt = Data("unreadable rewards".utf8)
        try corrupt.write(to: url)
        let store = NativeRewardsStore(url: url, createdAt: start, calendar: calendar)
        try FileManager.default.moveItem(at: directory, to: backup)
        try Data("blocked parent".utf8).write(to: directory)
        XCTAssertThrowsError(try store.reset(at: start))
        XCTAssertNotNil(store.loadError)
        XCTAssertEqual(try Data(contentsOf: backup.appendingPathComponent("rewards.json")), corrupt)
        try FileManager.default.removeItem(at: directory)
        try FileManager.default.moveItem(at: backup, to: directory)
        try store.reset(at: start)
        XCTAssertNil(store.loadError)
        let reloaded = NativeRewardsStore(url: url, createdAt: start, calendar: calendar)
        XCTAssertNil(reloaded.loadError)
        XCTAssertTrue(reloaded.ledger.events.isEmpty)
        XCTAssertTrue(reloaded.ledger.windowChanges.isEmpty)
        XCTAssertEqual(reloaded.ledger.remainingFreezes, 2)
    }

    func testAdvanceProtectsExistingHistoryWithoutBackfillingRewardsAndPersistsOnce() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("rewards.json")
        let store = NativeRewardsStore(url: url, createdAt: start, calendar: calendar)
        let record = try LoggedWorkout.make(exerciseID: "wallPushup", count: 20, sets: 1, date: start)
        let today = calendar.startOfDay(for: start).addingTimeInterval(3 * 86_400)
        let rest = calendar.startOfDay(for: start).addingTimeInterval(86_400)
        try store.advance(history: [record], at: today, plannedRestDays: [rest])
        XCTAssertTrue(store.ledger.events.isEmpty)
        XCTAssertEqual(store.ledger.totalBonusXP, 0)
        XCTAssertEqual(store.summary(history: [record], at: today).protectedStreak, 3)
        XCTAssertEqual(store.ledger.remainingFreezes, 1)
        let saved = try Data(contentsOf: url)
        try store.advance(history: [record], at: today, plannedRestDays: [rest])
        XCTAssertEqual(try Data(contentsOf: url), saved)
        let reloaded = NativeRewardsStore(url: url, createdAt: today, calendar: calendar)
        XCTAssertEqual(reloaded.ledger.frozenDays, store.ledger.frozenDays)
        XCTAssertEqual(reloaded.ledger.restDays, [rest])
    }
}

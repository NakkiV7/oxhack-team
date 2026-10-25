import XCTest
@testable import Spottr

@MainActor
final class TrainingRewardsRefreshTests: XCTestCase {
    func testRefreshUsesExplicitApprovedRestAndDoesNotInventWorkOrRepeatWrites() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "RewardsRefresh-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
        let created = instant("2026-10-25T10:00:00Z")
        let now = instant("2026-10-28T12:00:00Z")
        let record = try LoggedWorkout.make(exerciseID: "wallPushup", count: 20, sets: 1, date: created)
        let historyURL = folder.appendingPathComponent("history.json")
        try HistoryStore(url: historyURL).save(record)
        let rewardsURL = folder.appendingPathComponent("rewards.json")
        let rewards = NativeRewardsStore(url: rewardsURL, createdAt: created, calendar: calendar)
        let week = try savedWeekData(restDates: ["2026-10-26"], approvedAt: created)
        defaults.set(week, forKey: "coach.approvedWeek")
        let store = TrainingStore(historyURL: historyURL, rewardsStore: rewards, defaults: defaults)

        store.refreshRewards(at: now)

        XCTAssertNil(store.error)
        XCTAssertEqual(rewards.ledger.restDays, [instant("2026-10-26T00:00:00Z")])
        XCTAssertEqual(rewards.ledger.frozenDays, [instant("2026-10-27T00:00:00Z")])
        XCTAssertEqual(rewards.ledger.remainingFreezes, 1)
        XCTAssertEqual(rewards.summary(history: store.history, at: now).protectedStreak, 3)
        XCTAssertTrue(rewards.ledger.events.isEmpty)
        XCTAssertEqual(rewards.ledger.totalBonusXP, 0)
        XCTAssertEqual(rewards.totalXP(history: store.history), 10)
        XCTAssertEqual(store.history, [record])
        let saved = try Data(contentsOf: rewardsURL)
        store.refreshRewards(at: now)
        XCTAssertEqual(try Data(contentsOf: rewardsURL), saved)
        XCTAssertEqual(defaults.data(forKey: "coach.approvedWeek"), week)
    }

    func testLegacyOrCorruptWeekCannotTurnMissingWorkoutsIntoRestProtection() throws {
        let created = instant("2026-10-25T10:00:00Z")
        for week in [try savedWeekData(restDates: nil, approvedAt: created), Data("unreadable saved week".utf8)] {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let suite = "RewardsRefresh-\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
            let record = try LoggedWorkout.make(exerciseID: "wallPushup", count: 20, sets: 1, date: created)
            let historyURL = folder.appendingPathComponent("history.json")
            try HistoryStore(url: historyURL).save(record)
            let rewards = NativeRewardsStore(url: folder.appendingPathComponent("rewards.json"), createdAt: created, calendar: calendar)
            defaults.set(week, forKey: "coach.approvedWeek")
            let store = TrainingStore(historyURL: historyURL, rewardsStore: rewards, defaults: defaults)

            store.refreshRewards(at: instant("2026-10-28T12:00:00Z"))

            XCTAssertTrue(rewards.ledger.restDays.isEmpty)
            XCTAssertEqual(rewards.ledger.frozenDays, [26, 27].map { instant("2026-10-\($0)T00:00:00Z") })
            XCTAssertEqual(rewards.ledger.remainingFreezes, 0)
            XCTAssertTrue(rewards.ledger.events.isEmpty)
            XCTAssertEqual(rewards.totalXP(history: store.history), 10)
            XCTAssertEqual(defaults.data(forKey: "coach.approvedWeek"), week)
        }
    }

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/London")!
        return value
    }
    private func instant(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private func savedWeekData(restDates: [String]?, approvedAt: Date) throws -> Data {
        let plan = try CoachSavedPlan.catalogue(exerciseID: "squat", sets: 1, target: 8, restSeconds: 60, createdAt: approvedAt)
        var json: [String: Any] = [
            "version": 1, "weekStart": "2026-10-25", "timeZone": "Europe/London",
            "days": [["date": "2026-10-25", "plan": try JSONSerialization.jsonObject(with: JSONEncoder().encode(plan))]],
            "guidanceIDs": ["nhs-strength"], "approvedAt": approvedAt.timeIntervalSinceReferenceDate
        ]
        if let restDates { json["restDates"] = restDates }
        let data = try JSONSerialization.data(withJSONObject: json)
        _ = try CoachSavedWeek.decode(data) // Fixture is valid before exercising the missing TrainingStore integration.
        return data
    }
}

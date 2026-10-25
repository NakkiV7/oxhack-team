import Foundation
import XCTest
@testable import SpottrCore

private func gameDate(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
private func gameCalendar(_ zone: String = "UTC") -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: zone)!
    return calendar
}
private func gameRecord(_ date: Date, reps: Int = 12, sets: Int = 1, source: InputSource = .camera,
                        reason: StopReason = .voluntary, id: UUID = UUID()) -> SessionRecord {
    .init(id: id, date: date, sets: (0..<sets).map { number in
        .init(id: UUID(), exercise: .squat, number: number + 1, reps: reps, target: 12,
              activeSeconds: 10, source: source, reason: reason)
    })
}

final class GamificationTests: XCTestCase {
    func testBaselineDaysPreserveHistoricalStreakWithoutCreatingCompletionEventsOrXP() {
        let now = gameDate("2026-10-26T12:00:00Z")
        let ledger = GamificationLedger(createdAt: now, calendar: gameCalendar("Europe/London"))
        let baseline = ["2026-10-23T23:30:00Z", "2026-10-24T23:30:00Z", "2026-10-26T08:00:00Z",
                        "2026-10-23T23:30:00Z", "2026-10-27T12:00:00Z"].map(gameDate) + [Date(timeIntervalSince1970: .nan)]
        let summary = ledger.summary(at: now, baselineActivityDays: baseline)
        XCTAssertEqual(summary.protectedStreak, 3)
        XCTAssertEqual(summary.actualTrainingDays, 3)
        XCTAssertTrue(summary.trainedToday)
        XCTAssertTrue(ledger.events.isEmpty && ledger.frozenDays.isEmpty)
        XCTAssertEqual(ledger.totalBonusXP, 0)
        XCTAssertEqual(ledger.remainingFreezes, 2)
        XCTAssertEqual(ledger.summary(at: now, baselineActivityDays: []).protectedStreak, 0)
    }

    func testBaselineCanAnchorNewFreezesWithoutBackfillingBonusOrDuplicatingActivityDays() throws {
        let created = gameDate("2026-10-24T12:00:00Z"), now = gameDate("2026-10-26T12:00:00Z")
        var ledger = GamificationLedger(createdAt: created, calendar: gameCalendar())
        let baseline = ["2026-10-22T00:00:00Z", "2026-10-23T00:00:00Z"].map(gameDate)
        XCTAssertEqual(ledger.advance(to: now, baselineActivityDays: baseline),
                       [gameDate("2026-10-24T00:00:00Z"), gameDate("2026-10-25T00:00:00Z")])
        XCTAssertTrue(ledger.advance(to: now, baselineActivityDays: baseline).isEmpty)
        XCTAssertEqual(ledger.summary(at: now, baselineActivityDays: baseline).protectedStreak, 4)
        XCTAssertEqual(ledger.summary(at: now, baselineActivityDays: baseline).actualTrainingDays, 2)
        XCTAssertEqual(ledger.remainingFreezes, 0)
        XCTAssertTrue(ledger.events.isEmpty)
        XCTAssertEqual(ledger.totalBonusXP, 0)
        _ = try ledger.awardCompletion(record: gameRecord(now), completedAt: now, eligibleBaseXP: 0, now: now)
        XCTAssertEqual(ledger.summary(at: now, baselineActivityDays: baseline + [now, now]).actualTrainingDays, 3)
    }

    func testOldBrokenBaselineDoesNotSpendNewFreezesOrStartARestOnlyStreak() {
        let created = gameDate("2026-10-24T12:00:00Z"), now = gameDate("2026-10-27T12:00:00Z")
        var ledger = GamificationLedger(createdAt: created, calendar: gameCalendar())
        let baseline = [gameDate("2026-10-20T00:00:00Z")]
        let rest = [gameDate("2026-10-25T00:00:00Z"), gameDate("2026-10-26T00:00:00Z")]
        XCTAssertTrue(ledger.advance(to: now, plannedRestDays: rest, baselineActivityDays: baseline).isEmpty)
        XCTAssertTrue(ledger.frozenDays.isEmpty)
        XCTAssertEqual(ledger.remainingFreezes, 2)
        XCTAssertEqual(ledger.summary(at: now, baselineActivityDays: baseline).protectedStreak, 0)
        XCTAssertEqual(ledger.summary(at: now, baselineActivityDays: baseline).actualTrainingDays, 1)
        XCTAssertEqual(ledger.totalBonusXP, 0)
    }

    func testRestDaysAfterABrokenChainDoNotPrependTheNextActualActivity() throws {
        let first = gameDate("2026-10-20T12:00:00Z"), resumed = gameDate("2026-10-27T12:00:00Z")
        var ledger = GamificationLedger(createdAt: first, calendar: gameCalendar())
        _ = try ledger.awardCompletion(record: gameRecord(first), completedAt: first, eligibleBaseXP: 0, now: first)
        _ = ledger.advance(to: resumed, plannedRestDays: [gameDate("2026-10-25T00:00:00Z"), gameDate("2026-10-26T00:00:00Z")])
        XCTAssertEqual(ledger.summary(at: resumed).protectedStreak, 0)
        _ = try ledger.awardCompletion(record: gameRecord(resumed), completedAt: resumed, eligibleBaseXP: 0, now: resumed)
        XCTAssertEqual(ledger.summary(at: resumed).protectedStreak, 1)
        let later = gameDate("2026-10-29T12:00:00Z")
        _ = ledger.advance(to: later, plannedRestDays: [gameDate("2026-10-28T00:00:00Z")])
        XCTAssertEqual(ledger.summary(at: later).protectedStreak, 2)
        XCTAssertEqual(ledger.summary(at: later).actualTrainingDays, 2)
        XCTAssertEqual(ledger.totalBonusXP, 0)
    }

    func testWindowIsValidatedAndLegacyMissingStateStartsWithoutAwards() throws {
        XCTAssertThrowsError(try DailyXPWindow(startHour: -1))
        XCTAssertThrowsError(try DailyXPWindow(startHour: 23))
        XCTAssertEqual(try DailyXPWindow(startHour: 0).startHour, 0)
        XCTAssertEqual(try DailyXPWindow(startHour: 22).startHour, 22)
        XCTAssertThrowsError(try JSONDecoder().decode(DailyXPWindow.self, from: Data(#"{"startHour":99}"#.utf8)))
        let ledger = try JSONDecoder().decode(GamificationLedger.self, from: Data("{}".utf8))
        XCTAssertEqual(ledger.remainingFreezes, 2)
        XCTAssertEqual(ledger.totalBonusXP, 0)
        XCTAssertTrue(ledger.events.isEmpty)
        XCTAssertTrue(ledger.windowChanges.isEmpty)
    }

    func testWindowChangesBeginNextLocalDayAndCannotRepriceStoredRewards() throws {
        var ledger = GamificationLedger(createdAt: gameDate("2026-10-23T00:00:00Z"), calendar: gameCalendar("Europe/London"))
        let window = try DailyXPWindow(startHour: 18)
        try ledger.scheduleWindow(window, at: gameDate("2026-10-24T12:00:00Z"))
        XCTAssertEqual(ledger.windowChanges.last?.effectiveAt, gameDate("2026-10-24T23:00:00Z"))
        let today = gameDate("2026-10-24T17:30:00Z")
        let ordinary = try XCTUnwrap(ledger.awardCompletion(record: gameRecord(today), completedAt: today, eligibleBaseXP: 10, now: today))
        XCTAssertEqual(ordinary.bonusXP, 0)
        let tomorrow = gameDate("2026-10-25T18:30:00Z"), record = gameRecord(gameDate("2026-10-25T16:00:00Z"))
        let doubled = try XCTUnwrap(ledger.awardCompletion(record: record, completedAt: tomorrow, eligibleBaseXP: 10, now: tomorrow))
        XCTAssertEqual(doubled.baseXP, 10)
        XCTAssertEqual(doubled.bonusXP, 10)
        XCTAssertEqual(doubled.completedAt, tomorrow)
        try ledger.scheduleWindow(DailyXPWindow(startHour: 20), at: tomorrow)
        let replay = try ledger.awardCompletion(record: record, completedAt: tomorrow, eligibleBaseXP: 0, now: tomorrow.addingTimeInterval(60))
        XCTAssertEqual(replay, doubled)
        XCTAssertEqual(ledger.totalBonusXP, 10)
        XCTAssertEqual(ledger.window(at: tomorrow)?.startHour, 18)
        XCTAssertEqual(ledger.window(at: gameDate("2026-10-26T12:00:00Z"))?.startHour, 20)
    }

    func testWindowUsesTwoElapsedHoursAcrossMissingAndRepeatedLocalHours() throws {
        let calendar = gameCalendar("Europe/London"), window = try DailyXPWindow(startHour: 1)
        let spring = try XCTUnwrap(window.interval(on: gameDate("2026-03-29T12:00:00Z"), calendar: calendar))
        XCTAssertEqual(spring.start, gameDate("2026-03-29T01:00:00Z"))
        XCTAssertEqual(spring.end, gameDate("2026-03-29T03:00:00Z"))
        XCTAssertEqual(spring.duration, 7200)
        let autumn = try XCTUnwrap(window.interval(on: gameDate("2026-10-25T12:00:00Z"), calendar: calendar))
        XCTAssertEqual(autumn.start, gameDate("2026-10-25T00:00:00Z"))
        XCTAssertEqual(autumn.end, gameDate("2026-10-25T02:00:00Z"))
        XCTAssertEqual(autumn.duration, 7200)
        XCTAssertNil(window.interval(on: Date(timeIntervalSince1970: .nan), calendar: calendar))
    }

    func testEditingThePendingWindowLeavesTodayUnchanged() throws {
        var ledger = GamificationLedger(createdAt: gameDate("2026-10-23T00:00:00Z"), calendar: gameCalendar())
        try ledger.scheduleWindow(DailyXPWindow(startHour: 14), at: gameDate("2026-10-23T12:00:00Z"))
        let now = gameDate("2026-10-24T12:00:00Z")
        try ledger.scheduleWindow(DailyXPWindow(startHour: 18), at: now)
        try ledger.scheduleWindow(DailyXPWindow(startHour: 20), at: now.addingTimeInterval(60))
        XCTAssertEqual(ledger.window(at: now)?.startHour, 14)
        XCTAssertEqual(ledger.window(at: gameDate("2026-10-25T12:00:00Z"))?.startHour, 20)
    }

    func testPinnedTimezoneSurvivesReopenAndWindowEndIsExclusive() throws {
        var ledger = GamificationLedger(createdAt: gameDate("2026-10-24T00:00:00Z"), calendar: gameCalendar("America/Los_Angeles"))
        try ledger.scheduleWindow(DailyXPWindow(startHour: 1), at: gameDate("2026-10-25T06:30:00Z"))
        XCTAssertEqual(ledger.windowChanges.last?.effectiveAt, gameDate("2026-10-25T07:00:00Z"))
        ledger = try JSONDecoder().decode(GamificationLedger.self, from: JSONEncoder().encode(ledger))
        XCTAssertEqual(ledger.calendar.timeZone.identifier, "America/Los_Angeles")
        let inside = gameDate("2026-10-25T08:00:00Z"), end = gameDate("2026-10-25T10:00:00Z")
        XCTAssertEqual(try ledger.awardCompletion(record: gameRecord(inside), completedAt: inside, eligibleBaseXP: 10, now: inside)?.bonusXP, 10)
        XCTAssertEqual(try ledger.awardCompletion(record: gameRecord(end), completedAt: end, eligibleBaseXP: 10, now: end)?.bonusXP, 0)
    }

    func testBaseXPRemainsTheExistingGoalAndDailyCapDelta() throws {
        let date = gameDate("2026-10-25T12:00:00Z")
        var ledger = GamificationLedger(createdAt: date.addingTimeInterval(-3600), calendar: gameCalendar())
        let fiveSets = gameRecord(date, sets: 5)
        for invalid in [-10, 1, 40] {
            XCTAssertThrowsError(try ledger.awardCompletion(record: fiveSets, completedAt: date, eligibleBaseXP: invalid, now: date))
        }
        XCTAssertTrue(ledger.events.isEmpty)
        let reward = try XCTUnwrap(ledger.awardCompletion(record: fiveSets, completedAt: date, eligibleBaseXP: 30, now: date))
        XCTAssertEqual(reward.baseXP, 30)
        XCTAssertEqual(reward.completedSetCount, 5)
        let partial = gameRecord(date, reps: 1)
        XCTAssertThrowsError(try ledger.awardCompletion(record: partial, completedAt: date, eligibleBaseXP: 10, now: date))
        XCTAssertEqual(try ledger.awardCompletion(record: partial, completedAt: date, eligibleBaseXP: 0, now: date)?.bonusXP, 0)
        XCTAssertTrue(ledger.summary(at: date).trainedToday)
    }

    func testZeroVideoAndSkippedStepsNeverCreateRewardsOrTrainingDaysButManualHoldsDo() throws {
        let date = gameDate("2026-10-25T12:00:00Z")
        var ledger = GamificationLedger(createdAt: date.addingTimeInterval(-3600), calendar: gameCalendar())
        XCTAssertNil(try ledger.awardCompletion(record: gameRecord(date, reps: 0), completedAt: date, eligibleBaseXP: 0, now: date))
        XCTAssertNil(try ledger.awardCompletion(record: gameRecord(date, source: .video), completedAt: date, eligibleBaseXP: 0, now: date))
        let skipped = SkippedSet(id: UUID(), exerciseID: "squat", number: 1, target: 12, unit: .reps, source: .manual, reason: .userChoice)
        XCTAssertNil(try ledger.awardCompletion(record: .init(id: UUID(), date: date, sets: [], skippedSets: [skipped]), completedAt: date, eligibleBaseXP: 0, now: date))
        XCTAssertEqual(ledger.summary(at: date).actualTrainingDays, 0)
        let hold = LoggedSet(id: UUID(), exerciseID: "plank", reps: 0, seconds: 20, source: .manual, reason: .voluntary)
        let record = SessionRecord(id: UUID(), date: date, sets: [], loggedSets: [hold, hold])
        let reward = try XCTUnwrap(ledger.awardCompletion(record: record, completedAt: date, eligibleBaseXP: 10, now: date))
        XCTAssertEqual(reward.completedSetCount, 1)
        XCTAssertEqual(reward.baseXP, 10)
        XCTAssertEqual(ledger.summary(at: date).actualTrainingDays, 1)
    }

    func testInvalidFutureAndPreLedgerCompletionsCannotBackfillOrAward() throws {
        let now = gameDate("2026-10-25T12:00:00Z"), created = gameDate("2026-10-24T00:00:00Z")
        var ledger = GamificationLedger(createdAt: created, calendar: gameCalendar())
        for invalid in [now.addingTimeInterval(1), Date(timeIntervalSince1970: .nan), created.addingTimeInterval(-1)] {
            XCTAssertThrowsError(try ledger.awardCompletion(record: gameRecord(created.addingTimeInterval(-3600)), completedAt: invalid, eligibleBaseXP: 10, now: now))
        }
        XCTAssertThrowsError(try ledger.scheduleWindow(DailyXPWindow(startHour: 18), at: Date(timeIntervalSince1970: .nan)))
        XCTAssertTrue(ledger.events.isEmpty)
        XCTAssertTrue(ledger.windowChanges.isEmpty)
        XCTAssertEqual(ledger.remainingFreezes, 2)
    }

    func testTwoStarterFreezesCoverOnlyElapsedMissedDaysAndNeverAwardExerciseOrXP() throws {
        let first = gameDate("2026-10-20T12:00:00Z")
        var ledger = GamificationLedger(createdAt: first, calendar: gameCalendar())
        _ = try ledger.awardCompletion(record: gameRecord(first), completedAt: first, eligibleBaseXP: 10, now: first)
        XCTAssertTrue(ledger.advance(to: first.addingTimeInterval(3600)).isEmpty)
        XCTAssertEqual(ledger.remainingFreezes, 2)
        let now = gameDate("2026-10-23T12:00:00Z")
        XCTAssertEqual(ledger.advance(to: now), [gameDate("2026-10-21T00:00:00Z"), gameDate("2026-10-22T00:00:00Z")])
        XCTAssertTrue(ledger.advance(to: now).isEmpty)
        XCTAssertEqual(ledger.remainingFreezes, 0)
        XCTAssertEqual(ledger.summary(at: now).protectedStreak, 3)
        XCTAssertEqual(ledger.summary(at: now).actualTrainingDays, 1)
        XCTAssertFalse(ledger.summary(at: now).trainedToday)
        XCTAssertEqual(ledger.events.count, 1)
        XCTAssertEqual(ledger.totalBonusXP, 0)
        XCTAssertEqual(ledger.summary(at: gameDate("2026-10-24T12:00:00Z")).protectedStreak, 0)
    }

    func testOnlyExplicitElapsedRestDaysPreserveTheChainWithoutSpendingAFreeze() throws {
        let first = gameDate("2026-10-20T12:00:00Z"), now = gameDate("2026-10-23T12:00:00Z")
        var ledger = GamificationLedger(createdAt: first, calendar: gameCalendar())
        _ = try ledger.awardCompletion(record: gameRecord(first), completedAt: first, eligibleBaseXP: 0, now: first)
        let rest = ["2026-10-19T12:00:00Z", "2026-10-21T12:00:00Z", "2026-10-23T12:00:00Z", "2026-10-24T12:00:00Z"].map(gameDate)
        XCTAssertEqual(ledger.advance(to: now, plannedRestDays: rest), [gameDate("2026-10-22T00:00:00Z")])
        XCTAssertEqual(ledger.restDays, [gameDate("2026-10-21T00:00:00Z")])
        XCTAssertEqual(ledger.remainingFreezes, 1)
        XCTAssertEqual(ledger.summary(at: now).protectedStreak, 3)
        XCTAssertEqual(ledger.summary(at: now).actualTrainingDays, 1)
        var empty = GamificationLedger(createdAt: first, calendar: gameCalendar())
        XCTAssertTrue(empty.advance(to: now, plannedRestDays: rest).isEmpty)
        XCTAssertTrue(empty.frozenDays.isEmpty && empty.restDays.isEmpty)
    }

    func testFreezeCalendarTraversesDSTUsingDaysRatherThan86400Seconds() throws {
        let first = gameDate("2026-10-23T23:30:00Z"), now = gameDate("2026-10-27T12:00:00Z")
        let calendar = gameCalendar("Europe/London")
        var ledger = GamificationLedger(createdAt: first, calendar: calendar)
        _ = try ledger.awardCompletion(record: gameRecord(first), completedAt: first, eligibleBaseXP: 0, now: first)
        let covered = ledger.advance(to: now)
        XCTAssertEqual(covered, [gameDate("2026-10-24T23:00:00Z"), gameDate("2026-10-26T00:00:00Z")])
        XCTAssertEqual(ledger.summary(at: now).protectedStreak, 3)
        XCTAssertEqual(ledger.summary(at: now).actualTrainingDays, 1)
    }

    func testInvalidClockNeverConsumesProtection() throws {
        let first = gameDate("2026-10-20T12:00:00Z")
        var ledger = GamificationLedger(createdAt: first, calendar: gameCalendar())
        _ = try ledger.awardCompletion(record: gameRecord(first), completedAt: first, eligibleBaseXP: 0, now: first)
        XCTAssertTrue(ledger.advance(to: Date(timeIntervalSince1970: .nan)).isEmpty)
        XCTAssertEqual(ledger.remainingFreezes, 2)
        XCTAssertEqual(ledger.summary(at: Date(timeIntervalSince1970: .nan)).protectedStreak, 0)
    }

    func testRemovalPurgesBonusWithoutReawardingOthersOrRestoringDeletedIDs() throws {
        var ledger = GamificationLedger(createdAt: gameDate("2026-10-19T00:00:00Z"), calendar: gameCalendar())
        try ledger.scheduleWindow(DailyXPWindow(startHour: 18), at: gameDate("2026-10-19T12:00:00Z"))
        let firstDate = gameDate("2026-10-20T18:00:00Z"), secondDate = gameDate("2026-10-21T18:00:00Z")
        let first = gameRecord(firstDate), second = gameRecord(secondDate)
        _ = try ledger.awardCompletion(record: first, completedAt: firstDate, eligibleBaseXP: 10, now: firstDate)
        let retained = try ledger.awardCompletion(record: second, completedAt: secondDate, eligibleBaseXP: 10, now: secondDate)
        _ = ledger.advance(to: gameDate("2026-10-23T12:00:00Z"))
        ledger.removeCompletion(sessionID: first.id)
        XCTAssertEqual(ledger.events, [retained!])
        XCTAssertEqual(ledger.totalBonusXP, 10)
        ledger = try JSONDecoder().decode(GamificationLedger.self, from: JSONEncoder().encode(ledger))
        XCTAssertNil(try ledger.awardCompletion(record: first, completedAt: firstDate, eligibleBaseXP: 10, now: secondDate))
        XCTAssertEqual(ledger.totalBonusXP, 10)
        ledger.removeCompletion(sessionID: second.id)
        XCTAssertEqual(ledger.summary(at: gameDate("2026-10-23T12:00:00Z")).protectedStreak, 0)
        XCTAssertEqual(ledger.totalBonusXP, 0)
        let reset = GamificationLedger(createdAt: secondDate, calendar: gameCalendar())
        XCTAssertEqual(reset.remainingFreezes, 2)
        XCTAssertTrue(reset.events.isEmpty && reset.windowChanges.isEmpty)
    }
}

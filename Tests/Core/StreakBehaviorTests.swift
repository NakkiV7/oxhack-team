import Foundation
import Testing
@testable import SpottrCore

private func streakCalendar(_ zone: String = "Europe/London") -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: zone)!
    calendar.firstWeekday = 2
    return calendar
}

private func streakDate(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

private func streakSession(_ date: String, id: UUID = UUID(), setID: UUID = UUID(), reps: Int = 4, source: InputSource = .camera) -> SessionRecord {
    .init(id: id, date: streakDate(date), sets: [
        .init(id: setID, exercise: .squat, number: 1, reps: reps, target: 12,
              activeSeconds: 20, source: source, reason: .voluntary)
    ])
}

@Test func publicActivityDaysExposeTheSameLocalEvidenceWithoutInventingCompletionTimes() {
    let history = [streakSession("2026-10-23T23:30:00Z"), streakSession("2026-10-24T10:00:00Z"),
                   streakSession("2026-10-25T12:00:00Z"), streakSession("2026-10-26T08:00:00Z", source: .video)]
    let now = streakDate("2026-10-26T12:00:00Z"), calendar = streakCalendar()
    let days = StreakSummary.activityDays(history: history, now: now, calendar: calendar)
    #expect(days == Set([streakDate("2026-10-23T23:00:00Z"), streakDate("2026-10-24T23:00:00Z")]))
    #expect(StreakSummary(history: history, now: now, calendar: calendar).totalTrainingDays == days.count)
}

@Test func streakCountsDistinctRealTrainingDaysAndAllowsTodayToRemainUnfinished() {
    let history = [streakSession("2026-10-22T12:00:00Z"), streakSession("2026-10-23T12:00:00Z"),
                   streakSession("2026-10-23T14:00:00Z")]
    let summary = StreakSummary(history: history, now: streakDate("2026-10-24T12:00:00Z"), calendar: streakCalendar())
    #expect(summary.currentStreak == 2)
    #expect(summary.longestStreak == 2)
    #expect(summary.daysThisWeek == 2)
    #expect(summary.totalTrainingDays == 2)
    #expect(!summary.trainedToday)
}

@Test func streakExcludesZeroVideoFutureAndDuplicateEvidenceButIncludesCompletedManualHolds() {
    let sessionID = UUID(), setID = UUID()
    let hold = LoggedSet(id: UUID(), exerciseID: "plank", reps: 0, seconds: 20, source: .manual, reason: .voluntary)
    let history = [
        streakSession("2026-10-22T12:00:00Z", id: sessionID, setID: setID),
        streakSession("2026-10-24T10:00:00Z", id: sessionID),
        streakSession("2026-10-24T11:00:00Z", setID: setID),
        streakSession("2026-10-24T18:00:00Z"),
        streakSession("2026-10-25T12:00:00Z"),
        streakSession("2026-10-21T12:00:00Z", source: .video),
        streakSession("2026-10-20T12:00:00Z", reps: 0),
        SessionRecord(id: UUID(), date: streakDate("2026-10-19T12:00:00Z"), sets: []),
        SessionRecord(id: UUID(), date: streakDate("2026-10-23T12:00:00Z"), sets: [], loggedSets: [hold, hold])
    ]
    let summary = StreakSummary(history: history, now: streakDate("2026-10-24T12:00:00Z"), calendar: streakCalendar())
    #expect(summary.currentStreak == 2)
    #expect(summary.longestStreak == 2)
    #expect(summary.totalTrainingDays == 2)
    #expect(summary.daysThisWeek == 2)
    #expect(!summary.trainedToday)
}

@Test func streakUsesLocalCalendarDaysAcrossTheClockChangeAndResetsAfterAMissedDay() {
    let history = [streakSession("2026-10-23T23:30:00Z"), streakSession("2026-10-24T23:30:00Z"),
                   streakSession("2026-10-25T23:30:00Z"), streakSession("2026-10-26T08:00:00Z")]
    let summary = StreakSummary(history: history, now: streakDate("2026-10-26T12:00:00Z"), calendar: streakCalendar())
    #expect(summary.currentStreak == 3)
    #expect(summary.longestStreak == 3)
    #expect(summary.daysThisWeek == 1)
    #expect(summary.trainedToday)
    let later = StreakSummary(history: history, now: streakDate("2026-10-28T12:00:00Z"), calendar: streakCalendar())
    #expect(later.currentStreak == 0)
    #expect(later.longestStreak == 3)
    let west = StreakSummary(history: Array(history.prefix(2)), now: streakDate("2026-10-25T12:00:00Z"), calendar: streakCalendar("America/Los_Angeles"))
    #expect(west.currentStreak == 2)
    #expect(!west.trainedToday)
}

@Test func emptyAndInvalidDatedHistoryNeverInventATrainingDay() {
    let invalid = SessionRecord(id: UUID(), date: Date(timeIntervalSince1970: .nan), sets: [])
    let summary = StreakSummary(history: [invalid], now: streakDate("2026-10-24T12:00:00Z"), calendar: streakCalendar())
    #expect(summary.currentStreak == 0)
    #expect(summary.longestStreak == 0)
    #expect(summary.daysThisWeek == 0)
    #expect(summary.totalTrainingDays == 0)
}

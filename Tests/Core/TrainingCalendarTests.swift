import Foundation
import Testing
@testable import SpottrCore

private func london() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/London")!
    calendar.firstWeekday = 2
    calendar.locale = Locale(identifier: "en_GB")
    return calendar
}
private let monday = Date(timeIntervalSince1970: 1_792_368_000)   // Monday 19 October 2026, 00:00 UTC (01:00 in London)
private func at(_ day: Int, hour: Double = 10) -> Date { monday.addingTimeInterval(Double(day) * 86_400 + hour * 3_600) }
private func logged(_ id: String, count: Int, sets: Int, day: Int) throws -> SessionRecord {
    try LoggedWorkout.make(exerciseID: id, count: count, sets: sets, date: at(day))
}
private func camera(_ exercise: Exercise, reps: [Int], day: Int) -> SessionRecord {
    let sets = reps.enumerated().map { index, count in
        SetRecord(id: UUID(), exercise: exercise, number: index + 1, reps: count, target: count, activeSeconds: Double(count) * 3, source: .camera, reserve: nil, reason: .target)
    }
    return SessionRecord(id: UUID(), date: at(day), sets: sets)
}

@Test func theMonthGridStartsOnTheCalendarsFirstWeekdayAndMarksEachDay() throws {
    let squats = camera(.squat, reps: [12, 10], day: 1)            // Tuesday 20 October
    let bridges = try logged("gluteBridge", count: 12, sets: 3, day: 1)
    let plank = try logged("plank", count: 20, sets: 2, day: 4)    // Friday 23 October
    let month = TrainingMonth(containing: at(2), history: [squats, bridges, plank, squats], calendar: london())
    #expect(month.weekdaySymbols == ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
    #expect(month.days.count % 7 == 0 && month.days.filter(\.inMonth).count == 31)
    #expect(london().component(.weekday, from: month.days[0].date) == 2)           // the grid opens on a Monday
    #expect(month.days.first { $0.inMonth }.map { london().component(.day, from: $0.date) } == 1)
    let tuesday = try #require(month.days.first { london().isDate($0.date, inSameDayAs: at(1)) })
    #expect(tuesday.trained && tuesday.hasCameraSets && tuesday.hasManualSets)
    #expect(tuesday.reports.count == 2 && tuesday.setCount == 5 && tuesday.reps == 22 + 36)   // the repeated record counts once
    #expect(tuesday.averageHeartRate == nil)                                              // no Watch readings recorded
    let friday = try #require(month.days.first { london().isDate($0.date, inSameDayAs: at(4)) })
    #expect(friday.holdSeconds == 40 && !friday.hasCameraSets && friday.hasManualSets)
    #expect(month.trainedDays == 2)
}

@Test func theWeekComparisonNeverGivesAPercentageFromAnEmptyWeek() throws {
    let lastWeek = try logged("squat", count: 12, sets: 2, day: -5)
    let thisWeek = [camera(.squat, reps: [12, 12, 12], day: 0), try logged("plank", count: 20, sets: 1, day: 2)]
    let comparison = WeekComparison(history: [lastWeek] + thisWeek, now: at(3), calendar: london())
    #expect(comparison.thisWeek.setCount == 4 && comparison.lastWeek.setCount == 2)
    #expect(comparison.trainingDays.this == 2 && comparison.trainingDays.last == 1)
    #expect(WeekComparison.delta(4, 2) == "+2 vs last week")
    #expect(WeekComparison.delta(2, 4, unit: " min") == "−2 min vs last week")
    #expect(WeekComparison.delta(3, 0) == "New this week" && WeekComparison.delta(0, 0) == "Same as last week")
    #expect(comparison.highlights.contains("4 sets this week, up from 2 last week."))
    #expect(comparison.highlights.contains("3 of 4 sets were counted by the camera; the rest were logged by you."))
    #expect(comparison.highlights.last == "No Apple Watch heart-rate readings this week; missing readings are never shown as zero.")
    let empty = WeekComparison(history: [], now: at(3), calendar: london())
    #expect(empty.highlights == ["No sets recorded this week or last week yet."])
}

@Test func theConsistencyStripCountsTrainingDaysAndTheCurrentRun() throws {
    let history = [try logged("squat", count: 12, sets: 1, day: 0), try logged("squat", count: 12, sets: 1, day: 1),
                   try logged("plank", count: 20, sets: 1, day: 2), try logged("squat", count: 12, sets: 1, day: -10)]
    let strip = ConsistencyStrip(history: history, now: at(3), calendar: london())
    #expect(strip.days.count == 30 && strip.trainedDays == 4)
    #expect(strip.days.last.map { london().isDate($0.date, inSameDayAs: at(3)) } == true)
    #expect(strip.currentStreak == 3)    // today has no session yet, so the run ends yesterday
    let trainedToday = ConsistencyStrip(history: history + [try logged("squat", count: 12, sets: 1, day: 3)], now: at(3, hour: 20), calendar: london())
    #expect(trainedToday.currentStreak == 4 && trainedToday.bestStreak == 4)
}

@Test func heatmapLevelsComeFromThePersonsOwnTrainingDays() throws {
    // Volumes 12, 24, 36 and 48 reps on four days: each lands in its own quartile of this person's history.
    let history = try (1...4).map { try logged("squat", count: 12, sets: $0, day: $0 - 4) }
    let strip = ConsistencyStrip(history: history, now: at(0, hour: 20), calendar: london())
    #expect(strip.days.suffix(4).map(\.volume) == [12, 24, 36, 48])
    #expect(strip.days.suffix(4).map(\.level) == [1, 2, 3, 4])
    #expect(strip.days.dropLast(4).allSatisfy { $0.level == 0 && !$0.trained })
    #expect(strip.bestStreak == 4 && strip.currentStreak == 4)
    let comparison = WeekComparison(history: [camera(.squat, reps: [10], day: 0)], now: at(1), calendar: london())
    #expect(comparison.averageRepSeconds.this == nil && comparison.averageHeartRate.this == nil)   // no timed reps or Watch readings stored
}

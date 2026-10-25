import Foundation
import Testing
@testable import SpottrCore

private func calendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/London")!
    calendar.firstWeekday = 2
    return calendar
}
private let monday = Date(timeIntervalSince1970: 1_792_368_000)   // Monday 19 October 2026
private func on(_ day: Int, hour: Double = 10) -> Date { monday.addingTimeInterval(Double(day) * 86_400 + hour * 3_600) }
private func camera(_ day: Int, reps: Int, durations: [Double]? = nil, source: InputSource = .camera) -> SessionRecord {
    SessionRecord(id: UUID(), date: on(day), sets: [SetRecord(id: UUID(), exercise: .squat, number: 1, reps: reps, target: 12, activeSeconds: Double(reps) * 2,
                                                              source: source, reserve: nil, reason: .target, repDurations: durations)])
}

@Test func trainingDaysCombineSessionsAndIgnoreVideoReplays() throws {
    let manual = try LoggedWorkout.make(exerciseID: "gluteBridge", count: 12, sets: 2, date: on(0, hour: 18))
    let days = TrainingCalendar.days(history: [camera(0, reps: 10), manual, camera(1, reps: 8, source: .video)], calendar: calendar())
    #expect(days.count == 1)                                            // the video replay on Tuesday is not a training day
    let monday = try #require(days[calendar().startOfDay(for: on(0))])
    #expect(monday.sessionIDs.count == 2 && monday.sets == 3 && monday.reps == 34 && monday.kind == .camera)
    #expect(monday.cameraSets == 1 && monday.manualSets == 2 && monday.activeSeconds == 20)
}

@Test func theMonthGridStartsOnTheCalendarsFirstWeekday() {
    let grid = TrainingCalendar.monthGrid(containing: on(0), calendar: calendar())
    #expect(grid.count == 5 && grid.allSatisfy { $0.count == 7 })
    #expect(grid[0].prefix(3).allSatisfy { $0 == nil })                 // 1 October 2026 is a Thursday
    #expect(grid[0][3].map { calendar().component(.day, from: $0) } == 1)
    #expect(grid.last?.compactMap { $0 }.last.map { calendar().component(.day, from: $0) } == 31)
    #expect(TrainingCalendar.weekdaySymbols(calendar: calendar()) == ["M", "T", "W", "T", "F", "S", "S"])
}

@Test func streaksCountConsecutiveDaysAndSurviveUntilTodaysSession() {
    let cal = calendar(), day = { (offset: Int) in cal.startOfDay(for: on(offset)) }
    let trained: Set<Date> = [day(-6), day(-5), day(-4), day(-2), day(-1)]
    #expect(TrainingCalendar.streaks(trainingDays: trained, today: on(0), calendar: cal) == (2, 3))   // not trained yet today
    #expect(TrainingCalendar.streaks(trainingDays: trained.union([day(0)]), today: on(0), calendar: cal) == (3, 3))
    #expect(TrainingCalendar.streaks(trainingDays: [day(-3)], today: on(0), calendar: cal) == (0, 1))
}

@Test func theWeekComparesWithTheWeekBefore() {
    let history = [camera(-7, reps: 10, durations: [2, 2]), camera(0, reps: 12, durations: [1.5, 2.5]), camera(2, reps: 12), camera(2, reps: 6)]
    let week = TrainingCalendar.weekComparison(history: history, now: on(3), calendar: calendar())
    #expect(week.sessions.now == 3 && week.sessions.before == 1)
    #expect(week.trainingDays.now == 2 && week.trainingDays.before == 1)
    #expect(week.sets.now == 3 && week.sets.before == 1)
    #expect(week.reps.now == 30 && week.reps.before == 10)
    #expect(week.averageRepSeconds.now == 2 && week.averageRepSeconds.before == 2)
    #expect(week.thisWeek.start == calendar().startOfDay(for: on(0)))
}

@Test func sampleHistoryFillsPastDaysButNeverTodayOrARealTrainingDay() throws {
    let now = on(6, hour: 12)                                           // Sunday 25 October 2026
    let real = camera(3, reps: 10)
    let sample = TrainingCalendar.sampleHistory(now: now, excluding: [real], calendar: calendar())
    let days = TrainingCalendar.days(history: sample, calendar: calendar())
    let today = calendar().startOfDay(for: now)
    #expect(days[today] == nil && days[calendar().startOfDay(for: real.date)] == nil)
    #expect((20...35).contains(days.count))                             // about five days a week over six weeks
    #expect(days.values.contains { $0.kind == .camera } && days.values.contains { $0.kind == .manual })
    #expect(TrainingCalendar.streaks(trainingDays: Set(days.keys), today: now, calendar: calendar()).current == 2)   // Thursday's real day sits outside the sample
    #expect(TrainingCalendar.sampleHistory(now: now, excluding: [real], calendar: calendar()) == sample)   // the same on every render
}

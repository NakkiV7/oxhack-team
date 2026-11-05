import Foundation
import Testing
@testable import SpottrCore

private func dashboardRecord(_ date: Date, source: InputSource = .camera, reps: Int = 8, id: UUID = UUID()) -> SessionRecord {
    .init(id: id, date: date, sets: [.init(id: UUID(), exercise: .squat, number: 1, reps: reps,
                                         target: 12, activeSeconds: 20, source: source, reason: .voluntary)])
}

@Test func dashboardShowsAnActualSevenDayWeekWithoutInventingTraining() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    calendar.firstWeekday = 2
    let now = Date(timeIntervalSince1970: 1_794_052_800)
    let dashboard = TrainingDashboard(history: [], now: now, calendar: calendar)
    #expect(dashboard.days.count == 7)
    #expect(dashboard.trainingDays == 0)
    #expect(dashboard.sessionCount == 0)
    #expect(dashboard.totalSets == 0)
    #expect(dashboard.latestRecord == nil)
    #expect(dashboard.days.allSatisfy { $0.setCount == 0 })
}

@Test func dashboardCountsRecordedNonReplayWorkOnceAndFindsTheLatestReport() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    calendar.firstWeekday = 2
    let now = Date(timeIntervalSince1970: 1_794_052_800)
    let recent = dashboardRecord(now.addingTimeInterval(-60))
    let earlier = dashboardRecord(now.addingTimeInterval(-120), source: .manual, reps: 5)
    let video = dashboardRecord(now.addingTimeInterval(-10), source: .video, reps: 99)
    let future = dashboardRecord(now.addingTimeInterval(60), reps: 99)
    let empty = dashboardRecord(now.addingTimeInterval(-20), reps: 0)
    let sample = dashboardRecord(now.addingTimeInterval(-5), reps: 99,
                                 id: UUID(uuidString: "5A3B1E00-0000-4000-8000-000000000001")!)
    let dashboard = TrainingDashboard(history: [video, future, earlier, recent, recent, empty, sample], now: now, calendar: calendar)
    #expect(dashboard.trainingDays == 1)
    #expect(dashboard.sessionCount == 2)
    #expect(dashboard.totalSets == 2)
    #expect(dashboard.totalReps == 13)
    #expect(dashboard.latestRecord?.id == recent.id)
    #expect(dashboard.days.reduce(0) { $0 + $1.setCount } == 2)
}

@Test func dashboardLatestReportSurvivesAWeekWithNoNewTraining() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = Date(timeIntervalSince1970: 1_794_052_800)
    let previousWeek = dashboardRecord(now.addingTimeInterval(-8 * 86_400))
    let dashboard = TrainingDashboard(history: [previousWeek], now: now, calendar: calendar)
    #expect(dashboard.sessionCount == 0)
    #expect(dashboard.trainingDays == 0)
    #expect(dashboard.latestRecord?.id == previousWeek.id)
}

@Test func dashboardIncludesManualHoldsAndKeepsSevenCalendarDaysAcrossClockChanges() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Europe/London"))
    calendar.firstWeekday = 2
    let now = try #require(ISO8601DateFormatter().date(from: "2026-10-25T18:00:00Z"))
    let hold = SessionRecord(id: UUID(), date: now.addingTimeInterval(-60), sets: [], loggedSets: [
        .init(id: UUID(), exerciseID: "plank", reps: 0, seconds: 20, source: .manual,
              reason: .voluntary, number: 1, target: 20)
    ])
    let invalid = dashboardRecord(Date(timeIntervalSince1970: .nan))
    let dashboard = TrainingDashboard(history: [invalid, hold], now: now, calendar: calendar)
    #expect(dashboard.days.count == 7)
    #expect(Set(dashboard.days.map(\.date)).count == 7)
    #expect(dashboard.days.allSatisfy { calendar.startOfDay(for: $0.date) == $0.date })
    #expect(dashboard.totalSets == 1)
    #expect(dashboard.totalReps == 0)
    #expect(dashboard.trainingDays == 1)
    #expect(dashboard.latestRecord?.id == hold.id)
}

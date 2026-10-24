import Foundation
import Testing
@testable import SpottrCore

@Test func reportProjectsOnlyObservedRestAndTotalsItWithoutDuplicatingSets() {
    let first = SetRecord(id: UUID(), exercise: .squat, number: 1, reps: 4, target: 12,
                          activeSeconds: 20, source: .camera, reason: .voluntary)
    let second = SetRecord(id: UUID(), exercise: .squat, number: 2, reps: 4, target: 12,
                           activeSeconds: 20, source: .camera, reason: .voluntary, restSecondsBefore: 11)
    let third = SetRecord(id: UUID(), exercise: .squat, number: 3, reps: 4, target: 12,
                          activeSeconds: 20, source: .camera, reason: .voluntary, restSecondsBefore: 0)
    let report = WorkoutReport(record: .init(id: UUID(), date: Date(), sets: [first, second, second, third]))
    #expect(report.sets.map(\.restSecondsBefore) == [nil, 11, 0])
    #expect(report.recordedRestSeconds == 11)
}

@Test(arguments: [-1.0, Double.nan, Double.infinity, -Double.infinity])
func reportKeepsInvalidRecordedRestUnknown(rest: Double) {
    let set = SetRecord(id: UUID(), exercise: .squat, number: 1, reps: 4, target: 12,
                        activeSeconds: 20, source: .camera, reason: .voluntary, restSecondsBefore: rest)
    let report = WorkoutReport(record: .init(id: UUID(), date: Date(), sets: [set]))
    #expect(report.sets.first?.restSecondsBefore == nil)
    #expect(report.recordedRestSeconds == nil)
}

@Test func reportPreservesLongAndZeroRestsAfterReopeningWhileMissingRestStaysUnknown() throws {
    let legacy = SetRecord(id: UUID(), exercise: .squat, number: 1, reps: 4, target: 12,
                           activeSeconds: 20, source: .camera, reason: .voluntary)
    let longRest = SetRecord(id: UUID(), exercise: .squat, number: 2, reps: 4, target: 12,
                             activeSeconds: 20, source: .camera, reason: .voluntary, restSecondsBefore: 3600)
    let immediate = SetRecord(id: UUID(), exercise: .squat, number: 3, reps: 4, target: 12,
                              activeSeconds: 20, source: .camera, reason: .voluntary, restSecondsBefore: 0)
    let manual = try LoggedWorkout.make(exerciseID: "wallPushup", count: 8, sets: 1)
    let record = SessionRecord(id: UUID(), date: Date(), sets: [legacy, longRest, immediate], loggedSets: manual.loggedSets)
    let reopened = try JSONDecoder().decode(SessionRecord.self, from: JSONEncoder().encode(record))
    let report = WorkoutReport(record: reopened)
    #expect(report.sets.map(\.restSecondsBefore) == [nil, 3600, 0, nil])
    #expect(report.recordedRestSeconds == 3600)
    #expect(WorkoutReport(record: manual).recordedRestSeconds == nil)
    #expect(WorkoutReport(record: .init(id: UUID(), date: Date(), sets: [legacy])).recordedRestSeconds == nil)
    #expect(WorkoutReport(record: .init(id: UUID(), date: Date(), sets: [immediate])).recordedRestSeconds == 0)
}

@Test func reportUsesActualExercisesAndManualHoldUnits() throws {
    let manual = try LoggedWorkout.make(exerciseID: "plank", count: 25, sets: 2)
    let report = WorkoutReport(record: manual)
    #expect(report.category == .core)
    #expect(report.setCount == 2)
    #expect(report.reps == 0)
    #expect(report.holdSeconds == 50)
    #expect(report.activeSeconds == 50)
    #expect(report.sets.first?.exerciseName == "Forearm plank")
    #expect(report.sets.first?.quantityText == "25 sec")
    #expect(report.sets.first?.source == .manual)
}

private func reportCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/London")!
    calendar.firstWeekday = 2
    calendar.minimumDaysInFirstWeek = 4
    return calendar
}

@Test func weeklyReportUsesHalfOpenLocalCalendarWeekAcrossClockChange() throws {
    let calendar = reportCalendar()
    let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 12))!
    let interval = calendar.dateInterval(of: .weekOfYear, for: date)!
    let first = try LoggedWorkout.make(exerciseID: "wallPushup", count: 8, sets: 2, date: interval.start)
    let last = try LoggedWorkout.make(exerciseID: "plank", count: 20, sets: 1, date: interval.end.addingTimeInterval(-1))
    let next = try LoggedWorkout.make(exerciseID: "squat", count: 12, sets: 1, date: interval.end)
    let before = try LoggedWorkout.make(exerciseID: "squat", count: 12, sets: 1, date: interval.start.addingTimeInterval(-1))
    let week = WeekReport(history: [first, last, next, before, first], containing: date, calendar: calendar)
    #expect(week.interval == interval)
    #expect(interval.duration == 169 * 3600)
    #expect(week.sessions.count == 2)
    #expect(week.setCount == 3)
    #expect(week.reps == 16)
    #expect(week.holdSeconds == 20)
    #expect(week.days.count == 7)
    #expect(week.days.map(\.setCount) == [2, 0, 0, 0, 0, 0, 1])
    #expect(week.categories.first(where: { $0.category == .upperBody })?.setCount == 2)
    #expect(week.categories.first(where: { $0.category == .core })?.holdSeconds == 20)
}

@Test func heartRateReportDeduplicatesReadingTimesAndDropsStaleInvalidOrForeignSamples() {
    let id = UUID()
    let start = Date(timeIntervalSince1970: 100)
    func message(_ sent: Double, _ measured: Double, _ value: Double, sessionID: UUID? = nil) -> WatchTelemetry {
        .init(sessionID: sessionID ?? id, sentAt: start.addingTimeInterval(sent),
              heartRate: .init(value: value, date: start.addingTimeInterval(measured)), accelerationG: nil, rotationRadiansPerSecond: nil)
    }
    let telemetry = [message(0, 0, 100), message(1, 0, 100), message(2, 2, 140),
                     message(20, 0, 200), message(3, 3, 400), message(4, 9, 110),
                     message(5, 5, 110, sessionID: UUID()), message(30, 30, 120)]
    let report = WorkoutReport(record: .init(id: id, date: start, sets: [], telemetry: telemetry))
    #expect(report.heartRate.samples.map(\.value) == [100, 140, 120])
    #expect(report.heartRate.average == 120)
    #expect(report.heartRate.minimum == 100)
    #expect(report.heartRate.maximum == 140)
    #expect(report.heartRate.samples.map(\.segment) == [0, 0, 1])
    #expect(report.heartRate.samples.last?.date == start.addingTimeInterval(30))
}

@Test func motionReportPreservesRecordedMagnitudeUnitsAndLeavesMissingSignalsEmpty() {
    let id = UUID()
    let date = Date(timeIntervalSince1970: 100)
    let samples: [WatchTelemetry] = [
        .init(sessionID: id, sentAt: date, heartRate: nil, accelerationG: .init(value: 0.4, date: date), rotationRadiansPerSecond: .init(value: 1.7, date: date)),
        .init(sessionID: id, sentAt: date.addingTimeInterval(1), heartRate: nil, accelerationG: .init(value: 0.4, date: date), rotationRadiansPerSecond: nil),
        .init(sessionID: id, sentAt: date.addingTimeInterval(20), heartRate: nil, accelerationG: .init(value: 0.6, date: date.addingTimeInterval(20)), rotationRadiansPerSecond: nil)
    ]
    let report = WorkoutReport(record: .init(id: id, date: date, sets: [], telemetry: samples))
    #expect(report.heartRate.samples.isEmpty)
    #expect(report.heartRate.average == nil)
    #expect(report.acceleration.samples.map(\.value) == [0.4, 0.6])
    #expect(report.acceleration.samples.map(\.segment) == [0, 1])
    #expect(report.rotation.samples.map(\.value) == [1.7])
    let empty = WorkoutReport(record: .init(id: UUID(), date: date, sets: []))
    #expect(empty.acceleration.samples.isEmpty)
    #expect(empty.rotation.samples.isEmpty)
}

@Test func categoryAndTotalsFollowActualSetsWithoutCountingRepeatedSetIDsTwice() throws {
    let date = Date()
    let camera = SetRecord(id: UUID(), exercise: .squat, number: 1, reps: 7, target: 12,
                           activeSeconds: 30, source: .camera, reserve: 2, reason: .form)
    let manual = try LoggedWorkout.make(exerciseID: "wallPushup", count: 8, sets: 1, date: date)
    let record = SessionRecord(id: UUID(), date: date, sets: [camera, camera], loggedSets: manual.loggedSets)
    let report = WorkoutReport(record: record)
    #expect(report.category == .fullBody)
    #expect(report.setCount == 2)
    #expect(report.reps == 15)
    #expect(report.activeSeconds == 30)
    #expect(report.sets.first?.reserve == 2)
    #expect(report.sets.first?.reason == .form)
    #expect(report.sets.map(\.source) == [.camera, .manual])
}

@Test func reportTempoUsesRecordedRepDurationsAndWeightsEachRepOnce() {
    let first = SetRecord(id: UUID(), exercise: .squat, number: 1, reps: 2, target: 12,
                          activeSeconds: 99, source: .camera, reason: .voluntary, repDurations: [1, 1])
    let second = SetRecord(id: UUID(), exercise: .squat, number: 2, reps: 1, target: 12,
                           activeSeconds: 99, source: .camera, reason: .voluntary, repDurations: [4])
    let report = WorkoutReport(record: .init(id: UUID(), date: Date(), sets: [first, first, second]))
    #expect(report.sets.map(\.averageRepSeconds) == [1, 4])
    #expect(report.averageRepSeconds == 2)
    #expect(report.timedRepCount == 3)
}

@Test(arguments: [[0.59], [15.01], [Double.nan], [Double.infinity], [], [1, 2]])
func reportRejectsInvalidOrIncompleteRecordedTempo(durations: [Double]) {
    let set = SetRecord(id: UUID(), exercise: .squat, number: 1, reps: 1, target: 12,
                        activeSeconds: 99, source: .camera, reason: .voluntary, repDurations: durations)
    let report = WorkoutReport(record: .init(id: UUID(), date: Date(), sets: [set]))
    #expect(report.sets.first?.averageRepSeconds == nil)
    #expect(report.averageRepSeconds == nil)
    #expect(report.timedRepCount == 0)
}

@Test func legacyAndManualSetsKeepTempoUnknownWhileValidBoundaryTimingsRemainUsable() throws {
    let legacy = SetRecord(id: UUID(), exercise: .squat, number: 1, reps: 3, target: 12,
                           activeSeconds: 30, source: .camera, reason: .voluntary)
    let recorded = SetRecord(id: UUID(), exercise: .pushup, number: 2, reps: 2, target: 10,
                             activeSeconds: 30, source: .video, reason: .voluntary, repDurations: [0.6, 15])
    let manual = try LoggedWorkout.make(exerciseID: "wallPushup", count: 8, sets: 1)
    let record = SessionRecord(id: UUID(), date: Date(), sets: [legacy, recorded], loggedSets: manual.loggedSets)
    let reopened = try JSONDecoder().decode(SessionRecord.self, from: JSONEncoder().encode(record))
    let report = WorkoutReport(record: reopened)
    #expect(report.sets.first?.averageRepSeconds == nil)
    #expect(report.sets.last?.averageRepSeconds == nil)
    #expect(report.averageRepSeconds == 7.8)
    #expect(report.timedRepCount == 2)
}

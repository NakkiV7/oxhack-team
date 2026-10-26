import Foundation
import Testing
@testable import SpottrCore

@Test func energyReportUsesLatestCumulativeObservationPerRunWithoutSummingOrMonotonicInvention() {
    let id = UUID(), run = UUID(), secondRun = UUID(), start = Date(timeIntervalSince1970: 100)
    func message(_ sent: Double, _ asOf: Double, _ value: Double, _ recordingID: UUID, owner: UUID? = nil) -> WatchTelemetry {
        .init(sessionID: owner ?? id, sentAt: start.addingTimeInterval(sent), heartRate: nil,
              accelerationG: nil, rotationRadiansPerSecond: nil,
              activeEnergy: .init(recordingID: recordingID, kilocalories: value, asOf: start.addingTimeInterval(asOf)))
    }
    let first = [message(2, 1, 5, run), message(3, 1, 5, run), message(6, 5, 7, run)]
    #expect(WorkoutReport(record: .init(id: id, date: start, sets: [], telemetry: first)).activeEnergy.map(\.kilocalories) == [7])
    #expect(WorkoutReport(record: .init(id: id, date: start, sets: [], telemetry: [message(60, 5, 7, run)])).activeEnergy.map(\.kilocalories) == [7])
    let samples = first + [message(8, 5, 6, run), message(9, 4, 99, run), message(10, 9, 0, secondRun),
                           message(11, 10, 100, run, owner: UUID()), message(12, 11, -1, run),
                           message(13, 16, 100, run), message(14, -3, 100, run),
                           message(.nan, 15, 100, run), message(16, .nan, 100, run)]
    let record = SessionRecord(id: id, date: start, sets: [], telemetry: Array(samples.reversed()))
    let energy = WorkoutReport(record: record).activeEnergy
    #expect(energy.map(\.recordingID) == [run, secondRun])
    #expect(energy.map(\.kilocalories) == [6, 0])
    #expect(energy.map(\.asOf) == [start.addingTimeInterval(5), start.addingTimeInterval(9)])
    #expect(WorkoutReport(record: .init(id: id, date: start, sets: [])).activeEnergy.isEmpty)
    let noEnergy = SessionRecord(id: id, date: start, sets: [])
    #expect(CoachGrounding.facts(history: [record]) == CoachGrounding.facts(history: [noEnergy]))
}

private func highlightRecord(reps: Int, source: InputSource = .camera, exercise: Exercise = .squat,
                             reason: StopReason = .voluntary, date: Double = 100) -> SessionRecord {
    .init(id: UUID(), date: Date(timeIntervalSince1970: date), sets: [
        .init(id: UUID(), exercise: exercise, number: 1, reps: reps, target: exercise.target,
              activeSeconds: 10, source: source, reason: reason)
    ])
}

@Test func highlightComparesSingleSetsOnlyWithinEarlierSameExerciseAndSource() {
    let current = highlightRecord(reps: 7)
    let prior = highlightRecord(reps: 5, date: 50)
    let manual = highlightRecord(reps: 100, source: .manual, date: 40)
    let other = highlightRecord(reps: 100, exercise: .pushup, date: 30)
    let future = highlightRecord(reps: 100, date: 150)
    let highlight = WorkoutReport(record: current).highlight(history: [future, manual, prior, other, prior, current])
    #expect(highlight == .repBest(exerciseID: "squat", source: .camera, reps: 7, previousBest: 5))
    #expect(WorkoutReport(record: prior).highlight(history: [current]) == .firstActivity)
    #expect(WorkoutReport(record: highlightRecord(reps: 5)).highlight(history: [prior]) == .recorded)
}

@Test func firstActivityRequiresKnownHistoryAndActualNonReplayWork() throws {
    let current = highlightRecord(reps: 3)
    let empty = highlightRecord(reps: 0, date: 20)
    let video = highlightRecord(reps: 20, source: .video, date: 30)
    #expect(WorkoutReport(record: current).highlight(history: nil) == .recorded)
    #expect(WorkoutReport(record: current).highlight(history: [empty, video, current]) == .firstActivity)
    #expect(WorkoutReport(record: video).highlight(history: []) == .replay)
    #expect(WorkoutReport(record: empty).highlight(history: []) == .noActivity)
    let hold = try LoggedWorkout.make(exerciseID: "plank", count: 20, sets: 1, date: Date(timeIntervalSince1970: 50))
    #expect(WorkoutReport(record: hold).highlight(history: []) == .firstActivity)
    #expect(WorkoutReport(record: current).highlight(history: [hold]) == .recorded)
    let future = highlightRecord(reps: 3, date: Date().addingTimeInterval(3600).timeIntervalSince1970)
    #expect(WorkoutReport(record: future).highlight(history: []) == .recorded)
}

@Test func recordedBestUsesTheLargestCurrentSetRatherThanTotalsOrTheFirstCandidate() {
    let first = highlightRecord(reps: 7)
    let larger = highlightRecord(reps: 9)
    let record = SessionRecord(id: first.id, date: first.date, sets: first.sets + larger.sets + larger.sets)
    let prior = highlightRecord(reps: 5, date: 50)
    #expect(WorkoutReport(record: record).highlight(history: [prior]) == .repBest(exerciseID: "squat", source: .camera, reps: 9, previousBest: 5))
}

@Test(arguments: [StopReason.discomfort, .failure, .form])
func difficultOrPainfulSessionsNeverReceiveAMilestone(reason: StopReason) {
    let current = highlightRecord(reps: 20, reason: reason)
    let prior = highlightRecord(reps: 5, date: 20)
    let expected: SessionHighlight = reason == .discomfort ? .discomfort : .difficult
    #expect(WorkoutReport(record: current).highlight(history: [prior]) == expected)
    #expect(WorkoutReport(record: highlightRecord(reps: 0, reason: reason)).highlight(history: []) == expected)
}

@Test func signalCoverageDescribesUniqueTimestampSpanAndGapsWithoutInventingCompleteness() {
    let id = UUID(), start = Date(timeIntervalSince1970: 100)
    let telemetry = [0.0, 0, 12, 25].map { offset in
        WatchTelemetry(sessionID: id, sentAt: start.addingTimeInterval(offset),
                       heartRate: .init(value: 120, date: start.addingTimeInterval(offset)),
                       accelerationG: nil, rotationRadiansPerSecond: nil)
    }
    let signal = WorkoutReport(record: .init(id: id, date: start, sets: [], telemetry: telemetry)).heartRate
    #expect(signal.samples.count == 3)
    #expect(signal.sampleSpan == 25)
    #expect(signal.gapCount == 1)
    let single = WorkoutReport(record: .init(id: id, date: start, sets: [], telemetry: Array(telemetry.prefix(1)))).heartRate
    #expect(single.sampleSpan == 0 && single.gapCount == 0)
    let missing = WorkoutReport(record: .init(id: id, date: start, sets: [])).heartRate
    #expect(missing.sampleSpan == nil && missing.gapCount == 0)
}

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

@Test func configuredCameraTimingsRequireSupportedSourceAndCompleteValidObservationArray() {
    let cases: [(InputSource, String, Int, [Double]?, LoggedSet.QuantityOrigin?, Int)] = [
        (.camera, "squat", 2, [1, 2], nil, 2),
        (.camera, "pushup", 2, [1], nil, 0),
        (.camera, "wallPushup", 2, [1, 2], nil, 0),
        (.manual, "squat", 2, [1, 2], .selfReport, 0),
        (.video, "squat", 2, [1, 2], nil, 0),
        (.camera, "squat", 2, [1, .infinity], nil, 0),
        (.camera, "squat", 2, [0.1, 2], nil, 0),
        (.camera, "squat", 2, nil, nil, 0)
    ]
    for (source, exerciseID, reps, durations, origin, expected) in cases {
        let set = LoggedSet(id: UUID(), exerciseID: exerciseID, reps: reps, seconds: 0,
            source: source, reason: .voluntary, quantityOrigin: origin, repDurations: durations)
        let report = WorkoutReport(record: .init(id: UUID(), date: Date(), sets: [], loggedSets: [set]))
        #expect(report.timedRepCount == expected)
        #expect(report.sets.first?.source == source)
    }
}

@Test func watchSignalReportExcludesPreSessionReadingsAndUsesLatestTimestampedCorrection() {
    let id = UUID(), start = Date(timeIntervalSince1970: 1_792_886_400)
    func packet(_ sent: Double, _ measured: Double, _ value: Double) -> WatchTelemetry {
        let reading = SensorReading(value: value, date: start.addingTimeInterval(measured))
        return .init(sessionID: id, sentAt: start.addingTimeInterval(sent), heartRate: reading,
                     accelerationG: reading, rotationRadiansPerSecond: reading)
    }
    let messages = [packet(1, -3, 99), packet(3, 2, 121), packet(2, 2, 120), packet(4, 4, 130)]
    let report = WorkoutReport(record: .init(id: id, date: start, sets: [], telemetry: messages))
    #expect(report.heartRate.samples.map(\.value) == [121, 130])
    #expect(report.acceleration.samples.map(\.value) == [121, 130])
    #expect(report.rotation.samples.map(\.value) == [121, 130])
    #expect(report.heartRate.average == 125.5)
    #expect(report.heartRate.sourceLabel == "Apple Watch · HealthKit")
    #expect(report.acceleration.sourceLabel == "Apple Watch · Core Motion")
    #expect(report.rotation.sourceLabel == "Apple Watch · Core Motion")
}

@Test func watchEnergyTimelineKeepsCumulativeRunsSeparateAndAcceptsCorrectionsWithoutSumming() {
    let id = UUID(), run = UUID(), nextRun = UUID(), start = Date(timeIntervalSince1970: 1_792_886_400)
    func packet(_ sent: Double, _ asOf: Double, _ kcal: Double, _ recording: UUID) -> WatchTelemetry {
        .init(sessionID: id, sentAt: start.addingTimeInterval(sent), heartRate: nil, accelerationG: nil,
              rotationRadiansPerSecond: nil, activeEnergy: .init(recordingID: recording, kilocalories: kcal,
                                                               asOf: start.addingTimeInterval(asOf)))
    }
    let messages = [packet(20, 20, 4.5, run), packet(2, 0, 0, run), packet(1, 0, 0, run),
                    packet(10, 10, 3, run), packet(11, 10, 2.75, run), packet(30, 30, 1, nextRun),
                    packet(31, 30, 1, nextRun), packet(32, 40, 8, nextRun), packet(0, -3, 9, run)]
    let report = WorkoutReport(record: .init(id: id, date: start, sets: [], telemetry: messages))
    #expect(report.energyTimeline.map(\.kilocalories) == [0, 2.75, 4.5, 1])
    #expect(report.energyTimeline.map(\.recordingID) == [run, run, run, nextRun])
    #expect(report.activeEnergy.map(\.kilocalories) == [4.5, 1])
    #expect(WorkoutReport(record: .init(id: id, date: start, sets: [])).energyTimeline.isEmpty)
}

@Test func nativeWatchReportFixturesKeepCorrectionsSeparateTotalsAndMissingSignalsExplicit() throws {
    let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("UI/Fixtures")
    func report(_ name: String) throws -> WorkoutReport {
        let records = try JSONDecoder().decode([SessionRecord].self,
            from: Data(contentsOf: fixtures.appendingPathComponent(name + ".json")))
        #expect(records.count == 1)
        return WorkoutReport(record: try #require(records.first))
    }
    let populated = try report("watch-populated")
    #expect(populated.heartRate.samples.map(\.value) == [118, 121, 120])
    #expect(populated.heartRate.gapCount == 1)
    #expect(populated.acceleration.samples.map(\.value) == [0.05, 0.5, 0.1])
    #expect(populated.rotation.samples.map(\.value) == [0.15, 1.25, 0.2])
    #expect(populated.activeEnergy.map(\.kilocalories) == [2.5, 0.4])
    #expect(populated.energyTimeline.map(\.kilocalories) == [0, 1.25, 2.5, 0.4])
    let partial = try report("watch-partial")
    #expect(partial.heartRate.samples.isEmpty)
    #expect(partial.acceleration.samples.map(\.value) == [0.3])
    #expect(partial.rotation.samples.isEmpty)
    #expect(partial.activeEnergy.isEmpty)
}

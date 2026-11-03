import Foundation
import Testing
@testable import SpottrCore

@Suite struct DemoPreviewTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/London")!
        return value
    }
    private var reference: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 12))!
    }

    @Test func recentSevenDaysStayReproducibleAcrossClockChange() throws {
        let sessions = DemoPreviewData.sessions(referenceDate: reference, calendar: calendar)
        #expect(sessions.count == 7)
        #expect(sessions == DemoPreviewData.sessions(referenceDate: reference, calendar: calendar))
        #expect(sessions.map { calendar.component(.day, from: $0.date) } == [19, 20, 21, 22, 23, 24, 25])
        #expect(sessions.map { calendar.component(.hour, from: $0.date) } == Array(repeating: 12, count: 7))
        #expect(sessions.last?.date == reference)
        #expect(reference.timeIntervalSince(sessions[5].date) == 25 * 3600)
        let ids = sessions.map(\.id) + sessions.flatMap { $0.sets.map(\.id) + $0.loggedSets.map(\.id) }
        #expect(Set(ids).count == ids.count)
        let reopened = try JSONDecoder().decode([SessionRecord].self, from: JSONEncoder().encode(sessions))
        #expect(reopened == sessions)
        let shifted = DemoPreviewData.sessions(referenceDate: reference.addingTimeInterval(7 * 86400), calendar: calendar)
        #expect(shifted.map(\.id) == sessions.map(\.id))
        #expect(shifted[0].date > sessions[0].date)
    }

    @Test func reportsUseCoherentSyntheticCountsAndQualifiedPreviewWatchSignals() {
        let sessions = DemoPreviewData.sessions(referenceDate: reference)
        for record in sessions {
            let report = WorkoutReport(record: record)
            #expect(report.setCount == record.setCount)
            #expect(report.reps == record.reps)
            #expect(report.activeSeconds == record.activeSeconds)
            #expect(record.telemetry.count >= 12)
            #expect(record.telemetry.allSatisfy { $0.sessionID == record.id })
            #expect(report.heartRate.samples.count == record.telemetry.count)
            #expect(report.heartRate.samples.allSatisfy { (65...165).contains($0.value) })
            #expect(report.acceleration.samples.count == record.telemetry.count)
            #expect(report.rotation.samples.count == record.telemetry.count)
            #expect(!report.activeEnergy.isEmpty)
            for set in report.sets {
                #expect(ExerciseCatalog.find(set.exerciseID) != nil)
                #expect(set.activeSeconds > 0)
                if set.source == .camera {
                    #expect(["pushup", "squat"].contains(set.exerciseID))
                    #expect(set.repDurations.count == set.reps)
                    #expect(set.repDurations.reduce(0, +) <= set.activeSeconds)
                } else {
                    #expect(set.source == .manual)
                    #expect(set.quantityOrigin == .selfReport)
                    #expect(set.repDurations.isEmpty)
                }
            }
        }
        let reports = sessions.map(WorkoutReport.init)
        #expect(reports.map(\.setCount) == [6, 6, 5, 6, 9, 6, 11])
        #expect(reports.map(\.reps) == [24, 34, 12, 49, 78, 65, 84])
        #expect(reports.map(\.holdSeconds) == [0, 0, 40, 0, 0, 0, 60])
        #expect(reports.contains { $0.category == .mobility })
        #expect(reports.contains { $0.sets.contains { $0.exerciseID == "pushup" } })
        #expect(reports.contains { $0.sets.contains { $0.exerciseID == "squat" } })
        #expect(reports.contains { $0.holdSeconds > 0 })
    }

    @Test func previewBiometricsKeepAuthoredPresageAndEffortSeparateFromWatchProvenance() throws {
        let sessions = DemoPreviewData.sessions(referenceDate: reference)
        let insights = try sessions.map { try #require(DemoPreviewData.insight(for: $0)) }
        for insight in insights {
            #expect(insight.biometrics.sourceLabel == "Synthetic preview · not recorded health data")
            #expect((60...110).contains(insight.biometrics.presagePulse))
            #expect((10...30).contains(insight.biometrics.presageBreathing))
            #expect(insight.biometrics.rationale.contains("authored"))
            #expect(insight.biometrics.rationale.contains("not measured"))
        }
        #expect(Set(insights.map { $0.biometrics.effortBand }) == ["Lower effort", "Higher effort"])
        let low = try #require(insights.first { $0.biometrics.effortBand == "Lower effort" })
        let high = try #require(insights.first { $0.biometrics.effortBand == "Higher effort" })
        #expect(high.biometrics.presagePulse > low.biometrics.presagePulse)
        let changed = SessionRecord(id: sessions[0].id, date: sessions[0].date, sets: sessions[0].sets,
            telemetry: [.init(sessionID: UUID(), sentAt: sessions[0].date, heartRate: nil, accelerationG: nil, rotationRadiansPerSecond: nil)])
        #expect(DemoPreviewData.insight(for: changed) == nil, "Removing fixture provenance must remove authored biometric analysis")
    }

    @Test func authoredGradesReferToFixtureFactsAndNeverGradeRealOrChangedRecords() throws {
        let sessions = DemoPreviewData.sessions(referenceDate: reference)
        let insights = try sessions.map { try #require(DemoPreviewData.insight(for: $0)) }
        #expect(insights.first?.grade == "D-")
        #expect(insights.last?.grade == "A+")
        #expect(insights.map(\.score) == [50, 62, 70, 78, 84, 94, 99])
        #expect(insights.map(\.grade) == ["D-", "D-", "C-", "C+", "B", "A", "A+"])
        for (record, insight) in zip(sessions, insights) {
            #expect(insight.sessionID == record.id)
            #expect(insight.sourceLabel == "Synthetic preview")
            #expect(insight.summary.contains("\(record.setCount) sets"))
            #expect(insight.summary.contains("\(record.reps) reps"))
            #expect(insight.score == (insight.achievementScore + insight.effortScore) / 2)
            #expect(insight.rationale.contains("authored"))
            #expect(insight.rationale.contains("health"))
        }
        let real = SessionRecord(id: UUID(), date: reference, sets: sessions[0].sets)
        #expect(DemoPreviewData.insight(for: real) == nil)
        let changed = SessionRecord(id: sessions[0].id, date: reference, sets: [])
        #expect(DemoPreviewData.insight(for: changed) == nil)
    }

    @Test func invalidReferenceDateNeverCreatesFixtures() {
        #expect(DemoPreviewData.sessions(referenceDate: Date(timeIntervalSince1970: .nan)).isEmpty)
        #expect(DemoPreviewData.sessions(referenceDate: Date(timeIntervalSince1970: .infinity)).isEmpty)
    }

    @Test func onlyExactPreviewFixturesCanBeEnrichedWithoutChangingRealOrEditedHistory() throws {
        for enriched in DemoPreviewData.sessions(referenceDate: reference, calendar: calendar) {
            let legacy = SessionRecord(id: enriched.id, date: enriched.date, sets: enriched.sets,
                                       loggedSets: enriched.loggedSets, skippedSets: enriched.skippedSets)
            #expect(legacy.telemetry.isEmpty)
            #expect(DemoPreviewData.enrichedRecord(legacy) == enriched)
            #expect(DemoPreviewData.enrichedRecord(enriched) == enriched)
            #expect(DemoPreviewData.insight(for: legacy) != nil)
            let real = SessionRecord(id: UUID(), date: enriched.date, sets: enriched.sets, loggedSets: enriched.loggedSets)
            #expect(DemoPreviewData.enrichedRecord(real) == nil)
            let edited = SessionRecord(id: enriched.id, date: enriched.date, sets: Array(enriched.sets.dropLast()),
                                       loggedSets: Array(enriched.loggedSets.dropLast()))
            #expect(DemoPreviewData.enrichedRecord(edited) == nil)
            let editedTelemetry = SessionRecord(id: enriched.id, date: enriched.date, sets: enriched.sets,
                telemetry: [.init(sessionID: enriched.id, sentAt: enriched.date,
                                  heartRate: .init(value: 71, date: enriched.date), accelerationG: nil, rotationRadiansPerSecond: nil)],
                loggedSets: enriched.loggedSets)
            #expect(DemoPreviewData.enrichedRecord(editedTelemetry) == nil)
        }
    }

    @Test func newlyCompletedPreviewWorkoutGetsSeparateDisplayExamplesWithoutInventingRecordedHealth() throws {
        let date = reference
        let record = try LoggedWorkout.make(exerciseID: "squat", count: 3, sets: 1, date: date)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let before = try encoder.encode(record)
        #expect(DemoPreviewData.reportMetrics(for: record, previewEnabled: false) == nil)
        let examples = try #require(DemoPreviewData.reportMetrics(for: record, previewEnabled: true))
        #expect(examples.sourceLabel == "Synthetic preview · not recorded health data")
        #expect(examples.exampleRecord.id == record.id)
        #expect(examples.exampleRecord.sets == record.sets)
        #expect(examples.exampleRecord.loggedSets == record.loggedSets)
        let report = WorkoutReport(record: examples.exampleRecord)
        #expect(report.heartRate.samples.count >= 12)
        #expect(report.acceleration.samples.count >= 12)
        #expect(report.rotation.samples.count >= 12)
        #expect(!report.activeEnergy.isEmpty)
        #expect(examples.angleSamples.count >= 12)
        #expect(examples.angleSamples.allSatisfy { $0.date >= record.date && (0...180).contains($0.value) })
        #expect(try encoder.encode(record) == before)
        #expect(WorkoutReport(record: record).heartRate.samples.isEmpty)
        #expect(record.telemetry.isEmpty)
        let empty = SessionRecord(id: UUID(), date: date, sets: [])
        #expect(DemoPreviewData.reportMetrics(for: empty, previewEnabled: true) == nil)
    }

    @Test func fixtureAccessDoesNotPopulateRealHistoryOrProfile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let history = HistoryStore(url: directory.appendingPathComponent("real-history.json"))
        #expect(try history.load().isEmpty)
        _ = DemoPreviewData.sessions(referenceDate: reference)
        #expect(DemoPreviewData.profile.name.contains("Demo"))
        #expect(DemoPreviewData.profile.bodyMeasurements == nil)
        #expect(try LocalProfile().name.isEmpty)
        #expect(try history.load().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }
}

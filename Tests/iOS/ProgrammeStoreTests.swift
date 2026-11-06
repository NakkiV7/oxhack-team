import XCTest
@testable import Spottr

@MainActor final class ProgrammeStoreTests: XCTestCase {
    func testCurrentWeekSurvivesExpiredRestoreTimezoneRoundTripAndAgeCorrection() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = try AccountWorkspace(scope: .init(accountID: UUID(), profileID: UUID(), root: root))
        let profile = try LocalProfile(programmePreferences: .init(goals: [.strength], weekdays: Set(1...7), ageContext: .init(ageYears: 30, guardianManaged: false)))
        try workspace.profile.save(profile)
        var london = Calendar(identifier: .gregorian); london.timeZone = TimeZone(identifier: "Europe/London")!
        let today = london.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 12))!
        var selectedCalendar = london
        let store = ProgrammeStore(scope: workspace.scope, profile: workspace.profile, now: { today }, calendar: { selectedCalendar })
        let a = try store.prepare(profile: profile, history: [], at: today, calendar: london)
        let old = try ProgrammePlanner.makeWeek(profile: profile, history: [], start: today.addingTimeInterval(-14 * 86400), calendar: london)
        try store.restore(old, profile: profile)
        for _ in 0..<2 {
            _ = try store.reconcile(profile: profile, history: [], protecting: [], at: today, calendar: london)
            XCTAssertEqual(store.current, a)
            XCTAssertEqual(store.current?.days.first?.id, store.day(at: today, calendar: london)?.id)
        }
        let reopened = ProgrammeStore(scope: workspace.scope, profile: workspace.profile, now: { today }, calendar: { selectedCalendar })
        _ = try reopened.reconcile(profile: profile, history: [], protecting: [], at: today, calendar: london)
        XCTAssertEqual(reopened.current, a)
        var tokyo = london; tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        selectedCalendar = tokyo
        let eastern = try reopened.reconcile(profile: profile, history: [], protecting: [], at: today, calendar: tokyo)
        XCTAssertEqual(reopened.current, eastern)
        XCTAssertEqual(reopened.capture(dayID: reopened.day()?.id).programmeID, eastern.id)
        selectedCalendar = london
        _ = try reopened.reconcile(profile: profile, history: [], protecting: [], at: today, calendar: london)
        XCTAssertEqual(reopened.current, a)
        XCTAssertEqual(reopened.capture(dayID: a.days.first?.id, at: today).programmeID, a.id)
        let junior = try LocalProfile(programmePreferences: .init(goals: [.strength], weekdays: Set(1...7), ageContext: .init(ageYears: 10, guardianManaged: true)))
        try workspace.profile.save(junior)
        XCTAssertNil(reopened.current)
        let corrected = try reopened.reconcile(profile: junior, history: [], protecting: [], at: today, calendar: london)
        XCTAssertEqual(reopened.current, corrected)
        XCTAssertTrue(reopened.archive.snapshots.contains(a))
    }
    func testPreparedProgrammePersistsBeforeTodayAndRejectsRetiredPolicyWrites() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = try AccountProfileDirectory(accountID: UUID(), root: root)
        let person = try directory.add(age: .init(ageYears: 30, guardianManaged: false), name: "Adult")
        let workspace = try AccountWorkspace(scope: directory.scope(person.id))
        let profile = try XCTUnwrap(workspace.profile.profile)
        let date = Date()
        let preview = try workspace.programme.preview(profile: profile, history: [], at: date)
        try workspace.programme.acceptPreview(preview, profile: profile)
        let reopened = try AccountWorkspace(scope: workspace.scope)
        XCTAssertEqual(reopened.programme.current, preview)
        XCTAssertEqual(try reopened.programme.prepare(profile: profile, history: [], at: date), preview)
        workspace.invalidatePolicy()
        XCTAssertThrowsError(try workspace.programme.prepare(profile: profile, history: [], at: date.addingTimeInterval(8 * 86400)))
        XCTAssertNil(reopened.programme.error)
    }
    func testActualEffortRestReadyAndRecordPreservePlannedIdentity() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var clock = 0.0
        let store = TrainingStore(historyURL: root.appendingPathComponent("history.json"), clock: { clock })
        let plan = try CoachSavedPlan.catalogue(exerciseID: "frontArmRaise", sets: 2, target: 6, restSeconds: 30)
        store.beginAuthorizedPlan(plan, availableSupport: [], plannedWorkoutID: "scheduled-day")
        XCTAssertNil(store.configured?.actualReps)
        store.beginConfiguredSet(); store.setConfiguredReps(3); store.endSet()
        store.setEffort(.hard)
        XCTAssertEqual(store.configured?.completed.last?.effort, .hard)
        store.feedback(reserve: 1, reason: .voluntary)
        XCTAssertEqual(store.configured?.completed.last?.effort, .hard)
        clock = 31; store.prepareAfterRest()
        XCTAssertEqual(store.configured?.index, 1)
        XCTAssertFalse(store.configured?.hasStarted == true)
        XCTAssertNil(store.configured?.actualReps)
        store.finish()
        XCTAssertEqual(store.history.first?.plannedWorkoutID, "scheduled-day")
        XCTAssertEqual(store.history.first?.loggedSets.first?.reps, 3)
        XCTAssertEqual(store.history.first?.loggedSets.first?.effort, .hard)
    }
    func testExportIncludesProgrammeAndActualMeasurementsAndRejectsForeignSessionContext() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = try AccountWorkspace(scope: .init(accountID: UUID(), profileID: UUID(), root: root))
        let profile = try LocalProfile(programmePreferences: .init(goals: [.strength], weekdays: Set(1...7), ageContext: .init(ageYears: 30, guardianManaged: false)))
        try workspace.profile.save(profile)
        _ = try workspace.programme.prepare(profile: profile, history: [])
        try workspace.programme.recordWeight(kilograms: 71, date: .now.addingTimeInterval(-86400))
        let context = SessionTrainingContext(owner: .init(accountID: UUID(), profileID: UUID()), age: nil)
        workspace.training.persist(.init(id: UUID(), date: .now, sets: [], trainingContext: context))
        XCTAssertTrue(workspace.training.history.isEmpty)
        let url = try workspace.scope.exportLocalData()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let exported = try JSONDecoder().decode(AccountLocalExport.self, from: Data(contentsOf: url))
        XCTAssertEqual(exported.programme, workspace.programme.archive)
        XCTAssertEqual(exported.weights, workspace.programme.weights)
    }
    func testDatedWeightIsExplicitScopedAndRetiredPolicyCannotWrite() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = try AccountProfileDirectory(accountID: UUID(), root: root)
        let person = try directory.add(age: .init(ageYears: 30, guardianManaged: false), name: "Adult")
        let workspace = try AccountWorkspace(scope: directory.scope(person.id))
        XCTAssertTrue(workspace.programme.weights.isEmpty)
        let measured = Date().addingTimeInterval(-86400)
        try workspace.programme.recordWeight(kilograms: 71.5, date: measured)
        XCTAssertEqual(workspace.programme.weights.first?.date, measured)
        XCTAssertEqual(try AccountWorkspace(scope: workspace.scope).programme.weights.first?.kilograms, 71.5)
        workspace.invalidatePolicy()
        XCTAssertThrowsError(try workspace.programme.recordWeight(kilograms: 72, date: .now))
    }
}

import XCTest
@testable import Spottr

@MainActor final class CoachProgrammeTests: XCTestCase {
    private var root: URL!
    override func setUp() { root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    override func tearDown() { try? FileManager.default.removeItem(at: root); super.tearDown() }
    private func workspace(age: Int = 30) throws -> AccountWorkspace {
        let scope = AccountDataScope(accountID: UUID(), profileID: UUID(), root: root)
        let profile = try LocalProfile(programmePreferences: .init(goals: [.strength, .balance], weekdays: Set(1...7), availableSupport: Set(PathSurvey.equipmentChoices), startingPoint: .somePractice, ageContext: .init(ageYears: age, guardianManaged: age < 18)))
        try NativeProfileStore(url: scope.file("profile.json")).save(profile)
        let workspace = try AccountWorkspace(scope: scope)
        try workspace.programme.prepare(profile: profile, history: [])
        return workspace
    }
    func testCoachEditsRealFuturePlanAndMovesWholeWorkoutWithoutCreatingHistory() throws {
        let w = try workspace(), actions = CoachProgrammeActions(store: w.training, profile: w.profile)
        let original = try XCTUnwrap(w.programme.current)
        let day = try XCTUnwrap(actions.days.first { $0.plan != nil })
        try actions.apply(.easier, dayID: day.id, revision: original.revision)
        let easier = try XCTUnwrap(w.programme.current?.days.first { $0.id == day.id }?.plan)
        XCTAssertLessThan(easier.items[0].target, day.plan!.items[0].target)
        XCTAssertGreaterThanOrEqual(easier.items[0].restSeconds, day.plan!.items[0].restSeconds)
        try actions.apply(.shorter, dayID: day.id, revision: w.programme.current!.revision)
        let short = try XCTUnwrap(w.programme.current?.days.first { $0.id == day.id }?.plan)
        XCTAssertLessThan(short.items.reduce(0) { $0 + $1.sets }, easier.items.reduce(0) { $0 + $1.sets })
        let destination = try XCTUnwrap(actions.days.first { $0.id != day.id })
        try actions.apply(.move(toDayID: destination.id), dayID: day.id, revision: w.programme.current!.revision)
        XCTAssertEqual(w.programme.current?.days.first { $0.id == destination.id }?.plan, short)
        try actions.apply(.rest, dayID: destination.id, revision: w.programme.current!.revision)
        XCTAssertNil(w.programme.current?.days.first { $0.id == destination.id }?.plan)
        XCTAssertEqual(try AccountWorkspace(scope: w.scope).programme.current, w.programme.current)
        XCTAssertTrue(w.training.history.isEmpty)
        XCTAssertTrue(w.training.rewards.ledger.events.isEmpty)
    }
    func testCoachSwapRespectsActualFamilySupportExclusionsAndJuniorCaps() throws {
        for age in [12, 30] {
            let w = try workspace(age: age), actions = CoachProgrammeActions(store: w.training, profile: w.profile)
            let day = try XCTUnwrap(actions.days.first { $0.plan != nil })
            let items = try XCTUnwrap(day.plan?.items)
            for item in items {
                let alternatives = actions.replacements(for: item, day: day)
                XCTAssertTrue(alternatives.allSatisfy { $0.family == ExerciseCatalog.find(item.exerciseID)?.family && w.profile.profile!.effectiveProgrammePreferences.canUse($0) && !items.map(\.exerciseID).contains($0.id) })
            }
            if let item = items.first(where: { !actions.replacements(for: $0, day: day).isEmpty }), let replacement = actions.replacements(for: item, day: day).first {
                try actions.apply(.swap(exerciseID: item.exerciseID, replacementID: replacement.id), dayID: day.id, revision: w.programme.current!.revision)
                let changed = try XCTUnwrap(w.programme.current?.days.first { $0.id == day.id }?.plan?.items.first { $0.exerciseID == replacement.id })
                if age < 13 { XCTAssertLessThanOrEqual(changed.target, changed.unit == .reps ? 6 : 10) }
            }
            XCTAssertThrowsError(try actions.apply(.swap(exerciseID: items[0].exerciseID, replacementID: "diamondPushup"), dayID: day.id, revision: w.programme.current!.revision))
        }
    }
    func testActiveRecordedStaleAndRetiredActionsPreserveActualQuantities() throws {
        let w = try workspace(), actions = CoachProgrammeActions(store: w.training, profile: w.profile)
        let day = try XCTUnwrap(actions.days.first { $0.plan != nil }), revision = w.programme.current!.revision
        let repFirst = try CoachSavedPlan(items: day.plan!.items.sorted { $0.unit == .reps && $1.unit != .reps }, availableSupport: Set(PathSurvey.equipmentChoices), createdAt: day.date, rationale: "Rep-first partial-work fixture")
        w.training.beginAuthorizedPlan(repFirst, availableSupport: Set(PathSurvey.equipmentChoices), plannedWorkoutID: day.id)
        w.training.beginConfiguredSet(); w.training.setConfiguredReps(3)
        let activeID = w.training.configured?.id
        XCTAssertThrowsError(try actions.apply(.easier, dayID: day.id, revision: revision))
        XCTAssertEqual(w.training.configured?.actualReps, 3)
        XCTAssertEqual(w.training.configured?.id, activeID)
        w.training.endSet(); w.training.setEffort(.hard); w.training.finish()
        XCTAssertThrowsError(try actions.apply(.rest, dayID: day.id, revision: revision))
        XCTAssertEqual(w.training.history.first?.loggedSets.first?.reps, 3)
        XCTAssertEqual(w.training.history.first?.loggedSets.first?.effort, .hard)
        let future = try XCTUnwrap(actions.days.first { $0.plan != nil })
        try actions.apply(.easier, dayID: future.id, revision: revision)
        XCTAssertThrowsError(try actions.apply(.shorter, dayID: future.id, revision: revision))
        w.invalidatePolicy()
        XCTAssertThrowsError(try actions.apply(.rest, dayID: future.id, revision: w.programme.current!.revision))
    }
}

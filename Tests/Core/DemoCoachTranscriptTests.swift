import XCTest
@testable import SpottrCore

final class DemoCoachTranscriptTests: XCTestCase {
    func testRestartWeekHasSevenDaysAndMostExercisesSelectedWithoutApprovingAnything() throws {
        let week = DemoCoachTranscript.days
        XCTAssertEqual(week.map(\.id), ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"])
        XCTAssertEqual(week.filter { $0.kind == .strength }.count, 2)
        let offered = Set(week.flatMap(\.exerciseIDs))
        XCTAssertTrue(DemoCoachTranscript.defaultSelection.isSubset(of: offered))
        XCTAssertGreaterThan(DemoCoachTranscript.defaultSelection.count, offered.count / 2)
        XCTAssertLessThan(DemoCoachTranscript.defaultSelection.count, offered.count)
        for id in offered { XCTAssertNotNil(ExerciseCatalog.find(id)) }
    }

    func testStartingADayRequiresSelectionAndItsActualSupportAndKeepsOmittedExercisesOut() throws {
        XCTAssertThrowsError(try DemoCoachTranscript.plan(dayID: "monday", selected: [], support: []))
        XCTAssertThrowsError(try DemoCoachTranscript.plan(dayID: "monday", selected: ["wallPushup"], support: []))
        XCTAssertThrowsError(try DemoCoachTranscript.plan(dayID: "sunday", selected: DemoCoachTranscript.defaultSelection, support: ["Wall"]))
        XCTAssertThrowsError(try DemoCoachTranscript.plan(dayID: "unknown", selected: ["squat"], support: []))
        XCTAssertThrowsError(try DemoCoachTranscript.plan(dayID: "monday", selected: ["invented"], support: []))
        let plan = try DemoCoachTranscript.plan(dayID: "monday", selected: ["gluteBridge", "deadBug"], support: [])
        XCTAssertEqual(plan.items.map(\.exerciseID), ["gluteBridge", "deadBug"])
        XCTAssertTrue(plan.items.allSatisfy { $0.sets == 1 && $0.restSeconds == 60 })
        _ = try ConfigurableSession(plan: plan, availableSupport: [])
        let wall = try DemoCoachTranscript.plan(dayID: "monday", selected: ["wallPushup"], support: ["Wall"])
        XCTAssertEqual(wall.items.map(\.exerciseID), ["wallPushup"])
        XCTAssertEqual(DemoCoachTranscript.requiredSupport(selected: ["wallPushup"]), ["Wall"])
    }

    func testEveryOfferedDayCanStartThroughTheRealPlanContractWithItsDeclaredUnits() throws {
        let offered = Set(DemoCoachTranscript.days.flatMap(\.exerciseIDs))
        let support = DemoCoachTranscript.requiredSupport(selected: offered)
        for day in DemoCoachTranscript.days where !day.exerciseIDs.isEmpty {
            let plan = try DemoCoachTranscript.plan(dayID: day.id, selected: offered, support: support)
            XCTAssertEqual(plan.items.map(\.exerciseID), day.exerciseIDs)
            XCTAssertLessThanOrEqual(plan.items.count, 3)
            for item in plan.items {
                let entry = try XCTUnwrap(ExerciseCatalog.find(item.exerciseID))
                XCTAssertEqual(item.unit, entry.unit)
                XCTAssertLessThanOrEqual(entry.level, 2)
                XCTAssertGreaterThan(item.target, 0)
            }
            _ = try ConfigurableSession(plan: plan, availableSupport: support)
        }
        let stretch = try DemoCoachTranscript.plan(dayID: "tuesday", selected: ["hipFlexorStretch"], support: [])
        XCTAssertEqual(stretch.items.first?.unit, .seconds)
        XCTAssertEqual(stretch.items.first?.target, 15)
    }
}

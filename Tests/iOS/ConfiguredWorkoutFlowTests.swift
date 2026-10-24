import XCTest
@testable import Spottr

@MainActor
final class ConfiguredWorkoutFlowTests: XCTestCase {
    func testSavedPlanStartsReadyAndOnlyCompletedWorkIsSavedOnceOnFinish() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("history.json")
        let store = TrainingStore(historyURL: url)
        let plan = try JSONDecoder().decode(CoachSavedPlan.self, from: Data("""
        {"items":[{"exerciseID":"wallPushup","sets":2,"target":8,"unit":"reps","restSeconds":30},
        {"exerciseID":"plank","sets":1,"target":20,"unit":"seconds","restSeconds":45}],
        "approvedAt":0,"rationale":"Offline test fixture"}
        """.utf8))

        store.startPlan(plan, availableSupport: ["Wall"])
        XCTAssertTrue(store.presented)
        XCTAssertEqual(store.configured?.current.exerciseID, "wallPushup")
        XCTAssertFalse(store.configured?.hasStarted ?? true)
        store.endSet()
        XCTAssertEqual(store.configured?.phase, .active)
        store.beginConfiguredSet()
        store.setConfiguredReps(4)
        store.endSet()
        XCTAssertTrue(store.history.isEmpty)
        XCTAssertEqual(store.configured?.completed.first?.reps, 4)
        store.feedback(reserve: nil, reason: .discomfort)
        store.next()
        XCTAssertEqual(store.configured?.phase, .rest)
        store.finish()
        XCTAssertEqual(store.history.count, 1)
        XCTAssertEqual(store.history.first?.setCount, 1)
        XCTAssertEqual(store.history.first?.loggedSets.first?.reason, .discomfort)
        store.save()
        XCTAssertEqual(store.history.count, 1)
        XCTAssertEqual(TrainingStore(historyURL: url).history, store.history)
    }
}

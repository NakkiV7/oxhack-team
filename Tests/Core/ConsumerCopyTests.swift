import XCTest
@testable import SpottrCore

final class ConsumerCopyTests: XCTestCase {
    func testCatalogueGoalUsesReadableTrainingDoseWithoutDecorativeSeparators() {
        XCTAssertTrue(ExerciseCatalog.all.allSatisfy { !$0.goalText.contains("·") })
        XCTAssertTrue(ExerciseCatalog.all.allSatisfy { $0.goalText.contains(String($0.goal)) && $0.goalText.contains("2 days") })
    }
    func testWatchConnectionAndQueueUseNaturalCopyWithoutChangingCounts() {
        let now = Date()
        let confirmation = WatchSetupConfirmation(checkedAt: now, pendingSamples: 3, droppedSamples: 2, queueMessage: nil)
        let observation = WatchSetupObservation(supported: true, activated: true, paired: true, installed: true, reachable: true, confirmation: confirmation)
        let presentation = WatchSetupPresentation(observation: observation, at: now)
        XCTAssertEqual(presentation.queueText, "3 waiting. 2 removed at the Watch queue limit.")
        XCTAssertFalse(WatchSetupPresentation(observation: observation, at: now.addingTimeInterval(20)).summary.contains("—"))
    }
}

import XCTest

final class ReportPolishFlowTests: XCTestCase {
    @MainActor func testManualReportKeepsMissingSignalsVisibleAndMakesTimingExplanationOptional() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = UUID().uuidString
        app.launch()
        logWallPushupsForUITest(app)
        app.tabBars.buttons["Insights"].tap()
        app.segmentedControls["insights-section"].buttons["Reports"].tap()
        let report = app.buttons["insights-report"].firstMatch
        XCTAssertTrue(report.waitForExistence(timeout: 4))
        report.tap()
        XCTAssertTrue(revealUITestText("Recorded work & rest", in: app).exists)

        let explanation = "Only saved timers and rest are shown. Manual rep entries may be untimed."
        XCTAssertFalse(app.staticTexts[explanation].exists)
        let details = app.buttons["About work & rest"]
        for _ in 0..<5 where !details.isHittable { app.swipeUp() }
        XCTAssertTrue(details.exists)
        details.tap()
        XCTAssertTrue(revealUITestText(explanation, in: app).exists)
        XCTAssertTrue(revealUITestText("No Watch heart-rate readings recorded.", in: app).exists)
        XCTAssertTrue(revealUITestText("Rep tempo was not recorded.", in: app).exists)
        XCTAssertFalse(app.staticTexts["0 kcal"].exists)
    }
}

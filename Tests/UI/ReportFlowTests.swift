import XCTest

final class ReportFlowTests: XCTestCase {
    @MainActor func testEmptyWeekShowsActualZeroTotalsAndNoInventedSignals() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchEnvironment["SPOTTR_DATA_NAMESPACE"]=UUID().uuidString;app.launch()
        app.tabBars.buttons["Insights"].tap()
        let sections=app.segmentedControls["insights-section"]
        XCTAssertTrue(sections.waitForExistence(timeout:5));sections.buttons["Overview"].tap()
        XCTAssertTrue(app.staticTexts["Training trends"].exists)
        sections.buttons["Reports"].tap()
        XCTAssertTrue(app.staticTexts["No session reports yet"].waitForExistence(timeout:4))
        XCTAssertFalse(app.staticTexts["Time-weighted average"].exists)
    }
    @MainActor func testSavedSessionOpensReportWithActualExerciseAndSignalAbsence() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchEnvironment["SPOTTR_DATA_NAMESPACE"]=UUID().uuidString;app.launch()
        logWallPushupsForUITest(app)
        app.tabBars.buttons["Insights"].tap()
        app.segmentedControls["insights-section"].buttons["Reports"].tap()
        let report=app.buttons["insights-report"].firstMatch
        XCTAssertTrue(report.waitForExistence(timeout:4));report.tap()
        XCTAssertTrue(app.staticTexts["Your sets"].waitForExistence(timeout:4))
        XCTAssertTrue(app.staticTexts["Upper body"].firstMatch.exists)
        XCTAssertTrue(revealUITestText("No Watch heart-rate readings recorded.",in:app).exists)
        XCTAssertFalse(app.staticTexts["0 kcal"].exists)
        XCTAssertTrue(revealUITestText("Rep tempo was not recorded.",in:app).exists)
        let attachment=XCTAttachment(screenshot:app.screenshot());attachment.name="Measured report without fabricated Watch data";attachment.lifetime = .keepAlways;add(attachment)
    }
}

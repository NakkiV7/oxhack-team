import XCTest

final class ReportFlowTests: XCTestCase {
    @MainActor func testEmptyWeekShowsActualZeroTotalsAndNoInventedSignals() {
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = UUID().uuidString
        app.launch()
        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.staticTexts["This week"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Your first session starts here."].exists)
        XCTAssertFalse(app.staticTexts["Average heart rate"].exists)
    }

    @MainActor func testSavedSessionOpensReportWithActualExerciseAndSignalAbsence() {
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = UUID().uuidString
        app.launch()
        app.buttons["Start session"].tap()
        app.buttons["End set"].tap()
        app.buttons["Finish session"].tap()
        XCTAssertTrue(app.staticTexts["Session saved"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.staticTexts["This week"].waitForExistence(timeout: 5))
        let report = app.buttons["session-report"].firstMatch
        XCTAssertTrue(report.waitForExistence(timeout: 5))
        report.tap()
        XCTAssertTrue(app.staticTexts["Session report"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Lower body"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Camera"].firstMatch.exists)
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["No Watch heart-rate readings recorded."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No Watch active-energy readings recorded."].exists)
        XCTAssertFalse(app.staticTexts["0 kcal"].exists)
        XCTAssertTrue(app.staticTexts["Rep tempo was not recorded."].exists)
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["No Watch acceleration readings recorded."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No Watch rotation readings recorded."].exists)
        XCTAssertTrue(app.staticTexts["Apple Watch · Core Motion"].firstMatch.exists)
    }
}

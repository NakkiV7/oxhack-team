import XCTest

final class TrainingDashboardFlowTests: XCTestCase {
    @MainActor func testTodayMakesTrainingAndOptionalWatchSetupReachableWithoutInventedTotals() {
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["Start session"].waitForExistence(timeout: 5))
        let today = XCTAttachment(screenshot: app.screenshot()); today.name = "Today"; today.lifetime = .keepAlways; add(today)
        XCTAssertTrue(app.staticTexts["today-selected-exercise"].exists)
        XCTAssertFalse(app.staticTexts["6 sets"].exists)
        XCTAssertFalse(app.staticTexts["Build your\nfoundation."].exists)
        app.swipeUp()
        XCTAssertTrue(app.otherElements["today-weekly-rhythm"].waitForExistence(timeout: 3))
        app.swipeUp()
        XCTAssertTrue(app.buttons["today-watch-setup"].waitForExistence(timeout: 3))
        app.buttons["today-watch-setup"].tap()
        XCTAssertTrue(app.staticTexts["Watch setup"].waitForExistence(timeout: 3))
        let watch = XCTAttachment(screenshot: app.screenshot()); watch.name = "Watch setup"; watch.lifetime = .keepAlways; add(watch)
    }

    @MainActor func testInsightsKeepsHealthHistorySeparateAndMissingWorkoutSignalsVisible() {
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = UUID().uuidString
        app.launch()
        app.tabBars.buttons["Insights"].tap()
        let sections = app.segmentedControls["insights-section"]
        XCTAssertTrue(sections.waitForExistence(timeout: 5))
        sections.buttons["Overview"].tap()
        XCTAssertTrue(app.staticTexts["Training trends"].waitForExistence(timeout: 3))
        let healthSetup = app.buttons["Health history & zone setup"]
        for _ in 0..<5 where !healthSetup.isHittable { app.swipeUp() }
        let overview = XCTAttachment(screenshot: app.screenshot()); overview.name = "Health history overview"; overview.lifetime = .keepAlways; add(overview)
        XCTAssertTrue(healthSetup.exists)
        for _ in 0..<5 where !sections.isHittable { app.swipeDown() }
        XCTAssertFalse(app.staticTexts["Live heart rate"].exists)
        sections.buttons["Calendar"].tap()
        XCTAssertTrue(app.buttons["calendar-day-\(Calendar.current.component(.day, from: Date()))"].waitForExistence(timeout: 3))
        sections.buttons["Reports"].tap()
        XCTAssertTrue(app.staticTexts["No session reports yet"].waitForExistence(timeout: 3))
    }

    @MainActor func testManualWorkoutOpensRecentReportWithoutInventingWatchOrCameraMeasurements() {
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = UUID().uuidString
        app.launch()
        logWallPushupsForUITest(app)
        app.tabBars.buttons["Today"].tap()
        app.swipeUp()
        let report = app.buttons["today-recent-report"]
        XCTAssertTrue(report.waitForExistence(timeout: 3))
        report.tap()
        XCTAssertTrue(app.staticTexts["Your sets"].waitForExistence(timeout: 3))
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Recorded work & rest"].waitForExistence(timeout: 3))
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["No Watch heart-rate readings recorded."].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Time-weighted average"].exists)
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Rep tempo was not recorded."].waitForExistence(timeout: 3))
    }
}

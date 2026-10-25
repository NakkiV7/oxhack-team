import XCTest

final class DemoProgressFlowTests: XCTestCase {
    @MainActor func testFreshProgressHasNoPreviewAndExplicitPreviewOpensSampleInsights() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = UUID().uuidString
        app.launch()
        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.staticTexts["Your first session starts here."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.scrollViews["demo-progress-dashboard"].exists)

        app.tabBars.buttons["Today"].tap()
        app.buttons["profile-settings"].tap()
        let preview = app.switches["testflight-preview-toggle"]
        for _ in 0..<8 where !preview.isHittable { app.swipeUp() }
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        preview.switches.firstMatch.tap()
        if app.navigationBars["Profile & settings"].buttons["Done"].exists {
            app.navigationBars["Profile & settings"].buttons["Done"].tap()
        }
        app.tabBars.buttons["Progress"].tap()

        XCTAssertTrue(app.staticTexts["Sample progress"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Sample workouts. Your real history stays separate."].exists)
        let insights = app.buttons["demo-progress-insights"]
        XCTAssertTrue(insights.exists)
        insights.tap()
        XCTAssertTrue(app.staticTexts["Workout insights"].waitForExistence(timeout: 5))
        let firstWorkout = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "demo-insight-workout-")).firstMatch
        XCTAssertTrue(firstWorkout.waitForExistence(timeout: 5))
        XCTAssertTrue(firstWorkout.label.contains("A complete sample session"))
        XCTAssertTrue(firstWorkout.label.contains("99"))
        firstWorkout.tap()
        XCTAssertTrue(app.staticTexts["Effort & achievement"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Preview grade"].exists)
        let report = app.buttons["demo-workout-full-report"]
        for _ in 0..<5 where !report.isHittable { app.swipeUp() }
        XCTAssertTrue(report.exists)
        report.tap()
        XCTAssertTrue(app.navigationBars["Session report"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["demo-full-report-preview-badge"].exists)

        app.tabBars.buttons["Today"].tap()
        app.buttons["profile-settings"].tap()
        for _ in 0..<8 where !preview.isHittable { app.swipeUp() }
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        preview.switches.firstMatch.tap()
        if app.navigationBars["Profile & settings"].buttons["Done"].exists {
            app.navigationBars["Profile & settings"].buttons["Done"].tap()
        }
        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.staticTexts["Your first session starts here."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Sample progress"].exists)

        app.terminate()
        app.launch()
        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.staticTexts["Your first session starts here."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Sample progress"].exists)
    }
}

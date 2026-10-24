import XCTest

final class CoachFlowTests: XCTestCase {
    @MainActor func testSavedProfileFocusAndWeeklyTargetAppearInCoachAndReportContextWithoutSending() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = UUID().uuidString
        app.launch()
        app.tabBars.buttons["Coach"].tap()
        XCTAssertTrue(app.staticTexts["Your next move."].waitForExistence(timeout: 5))
        app.tabBars.buttons["Today"].tap()
        app.buttons["profile-settings"].tap()
        let weeklyTarget = app.steppers["weekly-training-target"]
        XCTAssertTrue(weeklyTarget.waitForExistence(timeout: 3))
        weeklyTarget.buttons["weekly-training-target-Increment"].tap()
        app.buttons["goal-strength"].tap()
        let mobility = app.buttons["goal-mobility"]
        for _ in 0..<4 where !mobility.isHittable { app.swipeUp() }
        mobility.tap()
        let save = app.buttons["save-profile"]
        for _ in 0..<4 where !save.isHittable { app.swipeUp() }
        save.tap()
        app.navigationBars.buttons["Done"].tap()

        app.tabBars.buttons["Coach"].tap()
        let coachContext = app.staticTexts["coach-goal-context"]
        XCTAssertTrue(coachContext.waitForExistence(timeout: 5))
        XCTAssertEqual(coachContext.label, "Mobility · 4 days/week")
        XCTAssertFalse(app.staticTexts["Thinking…"].exists)
        app.tabBars.buttons["Progress"].tap()
        let reportContext = app.staticTexts["coach-summary-goal-context"]
        for _ in 0..<5 where !reportContext.exists { app.swipeUp() }
        XCTAssertTrue(reportContext.waitForExistence(timeout: 3))
        XCTAssertEqual(reportContext.label, "Mobility · 4 days/week")
        XCTAssertFalse(app.staticTexts["Thinking…"].exists)
    }

    func testCoachNeedsExplicitSendAndOffersLocalConnectionSettings() {
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = UUID().uuidString
        app.launch()
        app.tabBars.buttons["Coach"].tap()
        XCTAssertTrue(app.staticTexts["Your next move."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Thinking…"].exists)
        app.buttons["Coach settings"].tap()
        XCTAssertTrue(app.textFields["Gateway URL"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.secureTextFields["Gateway access token"].exists)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Propose a workout"].exists)
    }
}

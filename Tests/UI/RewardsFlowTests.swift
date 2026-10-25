import XCTest

final class RewardsFlowTests: XCTestCase {
    @MainActor func testTodaySeparatesWeeklyTargetAndExplainsTheMissingStreakWithoutColour() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = UUID().uuidString
        app.launch()
        let weekly = app.staticTexts["today-weekly-target"]
        XCTAssertTrue(weekly.waitForExistence(timeout: 5))
        XCTAssertEqual(weekly.label, "Weekly target")
        XCTAssertEqual(weekly.value as? String, "0 of 3 training days this week")
        let streak = app.staticTexts["today-streak-status"]
        XCTAssertTrue(streak.exists)
        XCTAssertEqual(streak.value as? String, "No active streak. No training logged today.")
        XCTAssertFalse(app.staticTexts["This week · your target"].exists)
        XCTAssertTrue(app.buttons["manage-training-rewards"].isHittable)
    }

    @MainActor func testTomorrowBonusWindowRequiresExplicitSaveAndNeverChangesToday() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = UUID().uuidString
        app.launch()
        func openRewards() {
            app.buttons["profile-settings"].tap()
            let rewards = app.buttons["training-rewards-settings"]
            for _ in 0..<7 where !rewards.isHittable { app.swipeUp() }
            XCTAssertTrue(rewards.waitForExistence(timeout: 3), "Profile needs the training-rewards settings entry.")
            rewards.tap()
            XCTAssertTrue(app.staticTexts["today-bonus-window"].waitForExistence(timeout: 3))
        }
        openRewards()
        let today = app.staticTexts["today-bonus-window"].label
        let tomorrow = app.staticTexts["tomorrow-bonus-window"].label
        XCTAssertTrue(app.staticTexts["Today’s window is fixed. Changes start tomorrow."].exists)
        let startHour = app.buttons["bonus-start-hour"]
        startHour.tap()
        app.buttons["09:00"].tap()
        XCTAssertNotEqual(app.staticTexts["tomorrow-bonus-window"].label, tomorrow)
        XCTAssertEqual(app.staticTexts["today-bonus-window"].label, today)
        app.navigationBars.buttons["Cancel"].tap()
        app.navigationBars.buttons["Done"].tap()
        openRewards()
        XCTAssertEqual(app.staticTexts["tomorrow-bonus-window"].label, tomorrow)
        app.buttons["bonus-start-hour"].tap()
        app.buttons["10:00"].tap()
        let save = app.buttons["save-bonus-window"]
        for _ in 0..<4 where !save.isHittable { app.swipeUp() }
        save.tap()
        XCTAssertTrue(app.staticTexts["Saved for tomorrow."].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["today-bonus-window"].label, today)
        app.terminate()
        app.launch()
        openRewards()
        XCTAssertEqual(app.staticTexts["today-bonus-window"].label, today)
        XCTAssertTrue(app.staticTexts["tomorrow-bonus-window"].label.contains("10:00"))
        XCTAssertTrue(app.staticTexts["tomorrow-bonus-window"].label.contains("12:00"))
        app.navigationBars.buttons["Cancel"].tap()
        app.navigationBars.buttons["Done"].tap()
    }
}

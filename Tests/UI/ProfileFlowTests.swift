import XCTest

final class ProfileFlowTests: XCTestCase {
    @MainActor func testProfileOpensExerciseFilmingGuideAndKeepsChecklistSeparateFromVideos() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = UUID().uuidString
        app.launch()
        app.buttons["profile-settings"].tap()
        let checklist = app.buttons["Film your exercises"]
        for _ in 0..<4 where !checklist.exists { app.swipeUp() }
        XCTAssertTrue(checklist.waitForExistence(timeout: 5))
        checklist.tap()
        XCTAssertTrue(app.staticTexts["0 of 19 filmed · 0 local videos added"].waitForExistence(timeout: 3))
        app.buttons["filmed-wallPushup"].tap()
        XCTAssertTrue(app.staticTexts["1 of 19 filmed · 0 local videos added"].exists)
        app.buttons["guide-wallPushup"].tap()
        XCTAssertTrue(app.staticTexts["Guide graphic"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["add-lesson-wallPushup"].exists)
        XCTAssertTrue(app.staticTexts["Record the full cycle"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["1 of 19 filmed · 0 local videos added"].waitForExistence(timeout: 3))
    }

    @MainActor func testLocalOnboardingRequiresAGoalAndCanBeRestartedWithoutErasingProfile() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["SPOTTR_FORCE_ONBOARDING"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["onboarding-continue"].waitForExistence(timeout: 5))
        app.buttons["onboarding-continue"].tap()
        app.buttons["goal-strength"].tap()
        XCTAssertFalse(app.buttons["onboarding-continue"].isEnabled)
        app.buttons["goal-mobility"].tap()
        app.buttons["onboarding-continue"].tap()
        app.textFields["Your name (optional)"].tap()
        app.textFields["Your name (optional)"].typeText("Omar")
        app.buttons["onboarding-continue"].tap()
        app.buttons["profile-settings"].tap()
        XCTAssertTrue(app.textFields["Your name (optional)"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["Your name (optional)"].value as? String, "Omar")
        for _ in 0..<4 where !app.buttons["Restart introduction"].exists { app.swipeUp() }
        app.buttons["Restart introduction"].tap()
        app.buttons["Cancel introduction"].tap()
        for _ in 0..<4 where !app.textFields["Your name (optional)"].exists { app.swipeDown() }
        XCTAssertEqual(app.textFields["Your name (optional)"].value as? String, "Omar")
        for _ in 0..<4 where !app.buttons["Reset local profile"].exists { app.swipeUp() }
        app.buttons["Reset local profile"].tap()
        app.buttons["Cancel"].tap()
        for _ in 0..<4 where !app.textFields["Your name (optional)"].exists { app.swipeDown() }
        XCTAssertEqual(app.textFields["Your name (optional)"].value as? String, "Omar")
    }
}

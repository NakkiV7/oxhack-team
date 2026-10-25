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
        let requirements = app.buttons["lesson-requirements-wallPushup"]
        XCTAssertTrue(requirements.exists)
        requirements.tap()
        XCTAssertTrue(app.staticTexts["500 MB total for lesson videos"].exists)
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

    @MainActor func testProfileAutosavesEditsAndInvalidGoalsKeepTheLastValidProfile() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = UUID().uuidString
        app.launch()
        app.buttons["profile-settings"].tap()
        let name = app.textFields["Your name (optional)"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Synthetic Guest")
        app.staticTexts["Saved on this iPhone. No account or sign-in is needed."].tap()
        app.steppers["weekly-training-target"].buttons["weekly-training-target-Increment"].tap()
        let mobility = app.buttons["goal-mobility"]
        for _ in 0..<4 where !mobility.isHittable { app.swipeUp() }
        mobility.tap()
        let strength = app.buttons["goal-strength"]
        for _ in 0..<4 where !strength.isHittable { app.swipeDown() }
        strength.tap()
        app.navigationBars.buttons["Done"].tap()
        app.terminate(); app.launch()
        app.buttons["profile-settings"].tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "Synthetic Guest")
        XCTAssertTrue(app.staticTexts["4 training days"].exists)
        for _ in 0..<4 where !mobility.isHittable { app.swipeUp() }
        XCTAssertEqual(mobility.value as? String, "Selected")
        mobility.tap()
        let validation = app.staticTexts["profile-validation-error"]
        for _ in 0..<4 where !validation.exists { app.swipeDown() }
        XCTAssertTrue(validation.waitForExistence(timeout: 3))
        app.navigationBars.buttons["Done"].tap()
        app.buttons["profile-settings"].tap()
        for _ in 0..<4 where !mobility.isHittable { app.swipeUp() }
        XCTAssertEqual(mobility.value as? String, "Selected")
    }

    @MainActor func testProfileBackgroundAndDownwardDragDismissKeyboardWithoutBlockingControls() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = UUID().uuidString
        app.launch()
        app.buttons["profile-settings"].tap()
        let name = app.textFields["Your name (optional)"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Synthetic")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        app.staticTexts["Saved on this iPhone. No account or sign-in is needed."].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        name.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        app.swipeDown()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        app.steppers["weekly-training-target"].buttons["weekly-training-target-Increment"].tap()
        XCTAssertTrue(app.staticTexts["4 training days"].exists)
        app.navigationBars.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["profile-settings"].waitForExistence(timeout: 3))
    }

}

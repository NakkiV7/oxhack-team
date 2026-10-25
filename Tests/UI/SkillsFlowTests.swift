import XCTest

final class SkillsFlowTests: XCTestCase {
    @MainActor func testLinearTreeExplainsLocksAndPreviewWithoutEarningChallenges() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = UUID().uuidString
        app.launch()
        app.tabBars.buttons["Skills"].tap()
        app.segmentedControls.buttons["Linear"].tap()
        let wall = app.buttons["skill-wallPushup"]
        XCTAssertTrue(wall.waitForExistence(timeout: 5))
        XCTAssertTrue(wall.label.contains("Available"))
        let incline = app.buttons["skill-inclinePushup"]
        for _ in 0..<5 where !incline.isHittable { app.swipeUp() }
        XCTAssertTrue(incline.label.contains("Locked"))
        XCTAssertTrue(incline.label.contains("Wall push-ups"))
        XCTAssertTrue(incline.label.contains("0/3 sets"))
        for _ in 0..<6 where !app.switches["skill-preview-access"].isHittable { app.swipeDown() }
        app.switches["skill-preview-access"].tap()
        for _ in 0..<5 where !incline.isHittable { app.swipeUp() }
        XCTAssertTrue(incline.label.contains("Preview · not earned"))
        XCTAssertTrue(incline.label.contains("Wall push-ups"))
        incline.tap()
        XCTAssertTrue(app.staticTexts["Manual: 0 sets"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Camera: 0 sets"].exists)
    }

    @MainActor func testAccessibilityTextUsesLinearTreeWithoutChangingSavedLayout() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = UUID().uuidString
        app.launch()
        app.tabBars.buttons["Skills"].tap()
        app.segmentedControls.buttons["Grid"].tap()
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        app.tabBars.buttons["Skills"].tap()
        XCTAssertTrue(app.staticTexts["skill-accessible-layout-note"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.scrollViews["skill-graph"].exists)
        XCTAssertTrue(app.buttons["skill-wallPushup"].exists)
        app.terminate()
        app.launchArguments = []
        app.launch()
        app.tabBars.buttons["Skills"].tap()
        XCTAssertTrue(app.segmentedControls.buttons["Grid"].isSelected)
    }

    @MainActor func testManualLogKeyboardDismissalPreservesUnsavedQuantityAndSets() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = UUID().uuidString
        app.launch()
        app.tabBars.buttons["Skills"].tap()
        let exercise = app.buttons["skill-wallPushup"]
        XCTAssertTrue(exercise.waitForExistence(timeout: 5))
        exercise.tap()
        let log = app.buttons["Log manually"]
        for _ in 0..<6 where !log.isHittable { app.swipeUp() }
        XCTAssertTrue(log.isHittable)
        log.tap()
        let quantity = app.textFields["Reps per set"], sets = app.textFields["Number of sets"]
        XCTAssertTrue(quantity.waitForExistence(timeout: 3))
        XCTAssertEqual(quantity.value as? String, "8")
        XCTAssertEqual(sets.value as? String, "3")
        quantity.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        quantity.typeText(XCUIKeyboardKey.delete.rawValue + "12")
        XCTAssertEqual(quantity.value as? String, "12", "Prepare the quantity draft before exercising keyboard dismissal.")
        sets.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        sets.typeText(XCUIKeyboardKey.delete.rawValue + "2")
        XCTAssertEqual(sets.value as? String, "2", "Prepare the sets draft before exercising keyboard dismissal.")
        let done = app.buttons["manual-workout-keyboard-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 3), "Number-pad entry needs an explicit keyboard Done action.")
        done.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertEqual(quantity.value as? String, "12")
        XCTAssertEqual(sets.value as? String, "2")
        XCTAssertFalse(app.staticTexts["Workout saved"].exists)

        quantity.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        let explanation = app.staticTexts["Log only the sets you completed. For different quantities, save them separately."]
        XCTAssertTrue(explanation.isHittable)
        explanation.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertEqual(quantity.value as? String, "12")
        XCTAssertEqual(sets.value as? String, "2")
        XCTAssertFalse(app.staticTexts["Workout saved"].exists)

        sets.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        app.swipeDown()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertEqual(quantity.value as? String, "12")
        XCTAssertEqual(sets.value as? String, "2")
        XCTAssertFalse(app.staticTexts["Workout saved"].exists)
        app.navigationBars.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["Manual: 0 sets"].waitForExistence(timeout: 3))
    }

    @MainActor func testExpandedGridPreviewNeverClaimsEarnedProgress() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = UUID().uuidString
        app.launch()
        app.tabBars.buttons["Skills"].tap()
        app.segmentedControls.buttons["Grid"].tap()
        let expand = app.buttons["skill-grid-expand"]
        XCTAssertTrue(expand.waitForExistence(timeout: 5))
        expand.tap()
        XCTAssertEqual(expand.label, "Collapse skill tree")
        let preview = app.switches["skill-preview-access"]
        XCTAssertTrue(preview.exists)
        XCTAssertEqual(preview.value as? String, "0")
        preview.tap()
        XCTAssertTrue(app.staticTexts["Preview access · no achievements earned"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["0 of 19 challenges earned"].exists)
        app.buttons["skill-wallPushup"].tap()
        XCTAssertTrue(app.staticTexts["Manual: 0 sets"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Camera: 0 sets"].exists)
    }

    @MainActor func testOptionalOnboardingBaselineSuggestsPracticeWithoutLoggingSets() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["SPOTTR_FORCE_ONBOARDING"] = "1"
        app.launch()
        app.buttons["onboarding-continue"].tap()
        app.buttons["onboarding-continue"].tap()
        let baseline = app.buttons["onboarding-baseline"]
        for _ in 0..<4 where !baseline.isHittable { app.swipeUp() }
        XCTAssertTrue(baseline.waitForExistence(timeout: 3))
        baseline.tap()
        app.buttons["Some practice"].tap()
        app.buttons["onboarding-continue"].tap()
        app.tabBars.buttons["Skills"].tap()
        XCTAssertTrue(app.staticTexts["Practice ideas · Some practice"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["suggested-inclinePushup"].exists)
        XCTAssertTrue(app.staticTexts["0 of 19 challenges earned"].exists)
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "SPOTTR_FORCE_ONBOARDING")
        app.launch()
        app.tabBars.buttons["Skills"].tap()
        XCTAssertTrue(app.staticTexts["Practice ideas · Some practice"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["0 of 19 challenges earned"].exists)
        app.tabBars.buttons["Today"].tap()
        app.buttons["profile-settings"].tap()
        app.steppers["weekly-training-target"].buttons["weekly-training-target-Increment"].tap()
        let save = app.buttons["save-profile"]
        for _ in 0..<4 where !save.isHittable { app.swipeUp() }
        save.tap()
        app.navigationBars.buttons["Done"].tap()
        app.tabBars.buttons["Skills"].tap()
        XCTAssertTrue(app.staticTexts["Practice ideas · Some practice"].waitForExistence(timeout: 3))
    }

    @MainActor func testTreeAndLinearViewsShareExerciseDetailsAndRememberSelection() {
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = UUID().uuidString
        app.launch()
        app.tabBars.buttons["Skills"].tap()
        let grid = app.segmentedControls.buttons["Grid"]
        XCTAssertTrue(grid.waitForExistence(timeout: 5))
        grid.tap()
        XCTAssertTrue(app.buttons["skill-wallPushup"].waitForExistence(timeout: 3))
        app.buttons["skill-wallPushup"].tap()
        XCTAssertTrue(app.staticTexts["Wall push-ups"].waitForExistence(timeout: 3))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.segmentedControls.buttons["Linear"].tap()
        XCTAssertTrue(app.buttons["skill-wallPushup"].waitForExistence(timeout: 3))
        app.terminate()
        app.launch()
        app.tabBars.buttons["Skills"].tap()
        XCTAssertTrue(app.segmentedControls.buttons["Linear"].isSelected)
    }

    @MainActor func testManualTrainingEarnsVisibleProgressAndPersists() {
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = UUID().uuidString
        app.launch()
        app.tabBars.buttons["Skills"].tap()
        app.buttons["skill-wallPushup"].tap()
        XCTAssertTrue(app.staticTexts["Wall push-ups"].waitForExistence(timeout: 5))
        app.buttons["Log manually"].tap()
        XCTAssertTrue(app.textFields["Reps per set"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.textFields["Reps per set"].value as? String, "8")
        XCTAssertEqual(app.textFields["Number of sets"].value as? String, "3")
        app.buttons["Save workout"].tap()
        XCTAssertTrue(app.staticTexts["Workout saved"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Manual: 3 sets"].waitForExistence(timeout: 3))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["30 XP"].waitForExistence(timeout: 3))
        app.terminate()
        app.launch()
        app.tabBars.buttons["Skills"].tap()
        XCTAssertTrue(app.staticTexts["30 XP"].waitForExistence(timeout: 3))
    }

    @MainActor func testLibraryShowsHoldUnitsWithoutCameraClaim() {
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = UUID().uuidString
        app.launch()
        app.buttons["Exercise library"].tap()
        app.buttons["library-plank"].tap()
        XCTAssertTrue(app.staticTexts["Forearm plank"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Start hold timer"].exists)
        app.buttons["Log manually"].tap()
        XCTAssertTrue(app.textFields["Seconds per set"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.textFields["Reps per set"].exists)
    }

    @MainActor func testHoldTimerCanPauseAndRequiresReviewBeforeSaving() {
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = UUID().uuidString
        app.launch()
        app.buttons["Exercise library"].tap()
        app.buttons["library-plank"].tap()
        app.buttons["Start hold timer"].tap()
        XCTAssertTrue(app.staticTexts["Ready when you are"].waitForExistence(timeout: 3))
        app.buttons["Start hold"].tap()
        XCTAssertTrue(app.buttons["Pause hold"].waitForExistence(timeout: 3))
        let finish = app.buttons["Finish hold"]
        XCTAssertTrue(finish.waitForExistence(timeout: 3))
        let enabled = NSPredicate(format: "enabled == true")
        expectation(for: enabled, evaluatedWith: finish)
        waitForExpectations(timeout: 5)
        app.buttons["Pause hold"].tap()
        XCTAssertTrue(app.staticTexts["Hold paused"].exists)
        finish.tap()
        XCTAssertTrue(app.textFields["Seconds per set"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.textFields["Number of sets"].value as? String, "1")
        app.buttons["Save workout"].tap()
        XCTAssertTrue(app.staticTexts["Workout saved"].waitForExistence(timeout: 3))
    }
}

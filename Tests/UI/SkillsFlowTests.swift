import XCTest

final class SkillsFlowTests: XCTestCase {
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

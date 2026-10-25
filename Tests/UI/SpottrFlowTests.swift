import XCTest

final class SpottrFlowTests: XCTestCase {
    @MainActor func testSeparateStorageNamespaceStartsWithEmptyHistory() {
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = UUID().uuidString
        app.launch()
        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.staticTexts["Your first session starts here."].waitForExistence(timeout: 3))
    }
    @MainActor func testUnavailableCameraLeavesVideoAndStopControlsUsable() {
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = UUID().uuidString
        app.launch()
        app.buttons["Start session"].tap()
        app.buttons["Use camera"].tap()
        XCTAssertTrue(app.staticTexts["Camera unavailable"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Import video"].exists)
        XCTAssertTrue(app.buttons["End set"].exists)
    }
    @MainActor func testSessionCanPauseFinishAndPersist() {
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["Start session"].waitForExistence(timeout: 10))
        app.buttons["Start session"].tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5))
        app.buttons["Pause"].tap()
        XCTAssertTrue(app.buttons["Resume"].exists)
        app.buttons["Resume"].tap()
        app.buttons["End set"].tap()
        XCTAssertTrue(app.staticTexts["How many more could you do?"].waitForExistence(timeout: 5))
        app.buttons["2 reps in reserve"].tap()
        app.buttons["Finish session"].tap()
        XCTAssertTrue(app.staticTexts["Session saved"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.staticTexts["1 set · 0 reps"].firstMatch.waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.staticTexts["1 set · 0 reps"].firstMatch.waitForExistence(timeout: 5))
    }
}

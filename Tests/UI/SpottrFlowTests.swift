import XCTest

final class SpottrFlowTests: XCTestCase {
    @MainActor func testPreviewRestWaitsForVisibleCameraBeforeShowingExamplesWithoutStartingPaidMeasurement() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = UUID().uuidString
        app.launch()
        app.buttons["profile-settings"].tap()
        let preview = app.switches["testflight-preview-toggle"]
        for _ in 0..<8 where !preview.isHittable { app.swipeUp() }
        XCTAssertTrue(preview.exists)
        preview.switches.firstMatch.tap()
        let done = app.navigationBars["Profile & settings"].buttons["Done"]
        if done.exists { done.tap() }
        app.buttons["Start session"].tap()
        app.buttons["End set"].tap()
        let camera = app.buttons["presage-rest-camera-toggle"]
        XCTAssertTrue(camera.waitForExistence(timeout: 5)); camera.tap()
        XCTAssertFalse(app.staticTexts["presage-demo-badge"].exists)
        XCTAssertFalse(app.switches["presage-example-vitals-toggle"].exists)
        XCTAssertFalse(app.staticTexts["Example readings · not measured. Live Watch heart rate takes priority when available."].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Example readings are presentation-only")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Camera unavailable"].exists)
        XCTAssertFalse(app.staticTexts["72 bpm"].exists)
        XCTAssertFalse(app.staticTexts["14 /min"].exists)
        XCTAssertFalse(app.staticTexts["75-second check. Stay still; HRV needs at least 60 seconds."].exists)
        XCTAssertFalse(app.buttons["Stop measurement"].exists)
        XCTAssertFalse(app.buttons["Start stationary measurement"].exists)
    }

    @MainActor func testPresageIsRestOnlyAndCameraControlDoesNotStartMeasurement() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = UUID().uuidString
        app.launch()
        app.buttons["Start session"].tap()
        XCTAssertFalse(app.buttons["presage-rest-camera-toggle"].exists)
        app.buttons["End set"].tap()
        let camera = app.buttons["presage-rest-camera-toggle"]
        XCTAssertTrue(camera.waitForExistence(timeout: 5))
        XCTAssertEqual(camera.label, "Turn camera ON")
        camera.tap()
        XCTAssertEqual(camera.label, "Turn camera OFF")
        let start = app.buttons["Start stationary measurement"]
        for _ in 0..<4 where !start.isHittable { app.swipeUp() }
        XCTAssertTrue(start.exists)
        XCTAssertFalse(start.isEnabled)
        XCTAssertFalse(app.buttons["Stop measurement"].exists)
        for _ in 0..<4 where !camera.isHittable { app.swipeDown() }
        camera.tap()
        XCTAssertEqual(camera.label, "Turn camera ON")
        XCTAssertFalse(app.buttons["Stop measurement"].exists)
    }

    @MainActor func testFinishedLegacySessionHeaderCloseDismissesWithoutDuplicatingHistory() {
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["Start session"].waitForExistence(timeout: 10))
        app.buttons["Start session"].tap()
        XCTAssertTrue(app.buttons["End set"].waitForExistence(timeout: 5))
        app.buttons["End set"].tap()
        XCTAssertTrue(app.buttons["Finish session"].waitForExistence(timeout: 5))
        app.buttons["Finish session"].tap()
        XCTAssertTrue(app.staticTexts["Session saved"].waitForExistence(timeout: 5))
        let close = app.buttons["Finish session now"]
        XCTAssertTrue(close.isHittable)
        close.tap()
        XCTAssertTrue(app.buttons["Start session"].waitForExistence(timeout: 5),
                      "The finished workout header Close must dismiss just like Done.")
        XCTAssertFalse(app.staticTexts["Session saved"].exists)
        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.buttons["session-report"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "session-report").count, 1,
                       "Closing finished work must not save another history record.")
    }
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

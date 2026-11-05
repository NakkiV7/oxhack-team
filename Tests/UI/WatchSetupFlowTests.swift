import XCTest

final class WatchSetupFlowTests: XCTestCase {
    @MainActor func testWatchChoiceIsOptionalAndDoesNotGrantHealthAccess() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["SPOTTR_FORCE_ONBOARDING"] = "1"
        app.launch()
        app.buttons["onboarding-continue"].tap()
        app.buttons["onboarding-watch-guide"].tap()
        let model = app.buttons["watch-model-se"]
        XCTAssertTrue(model.waitForExistence(timeout: 4))
        model.tap()
        XCTAssertTrue(app.staticTexts["watch-model-guidance"].label.contains("doesn’t measure blood oxygen"))
        XCTAssertTrue(app.buttons["watch-check-connection"].exists)
        XCTAssertTrue(app.staticTexts["watch-setup-status"].exists)
        let check = app.buttons["watch-check-connection"]
        for _ in 0..<6 where !check.isHittable { app.swipeUp() }
        XCTAssertTrue(check.isHittable)
        let capture = XCTAttachment(screenshot: app.screenshot()); capture.name = "Watch connection milestones"; capture.lifetime = .keepAlways; add(capture)
        let noWatch = app.buttons["watch-model-noWatch"]
        for _ in 0..<5 where !noWatch.isHittable { app.swipeDown() }
        noWatch.tap()
        XCTAssertTrue(app.staticTexts["watch-phone-only"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["watch-check-connection"].exists)
        app.buttons["watch-model-notSure"].tap()
        XCTAssertTrue(app.buttons["watch-check-connection"].waitForExistence(timeout: 3))
    }
}

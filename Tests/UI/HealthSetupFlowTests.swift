import XCTest

final class HealthSetupFlowTests: XCTestCase {
    @MainActor func testOptionalWatchAndHealthSetupCanBeSkippedWithoutReadingHealthOrResettingProfile() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["SPOTTR_FORCE_ONBOARDING"] = "1"
        app.launch()
        let next = app.buttons["onboarding-continue"]
        XCTAssertTrue(next.waitForExistence(timeout: 8))
        next.tap()
        XCTAssertTrue(app.staticTexts["onboarding-health-optional"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["onboarding-watch-guide"].exists)
        XCTAssertTrue(app.buttons["onboarding-health-setup"].exists)
        next.tap()
        XCTAssertTrue(app.buttons["goal-strength"].waitForExistence(timeout: 3))
        next.tap()
        next.tap()
        next.tap()
        next.tap()
        XCTAssertTrue(app.buttons["profile-settings"].waitForExistence(timeout: 4))
        app.buttons["profile-settings"].tap()
        let setup = app.buttons["profile-health-setup"]
        for _ in 0..<10 where !setup.isHittable { app.swipeUp() }
        XCTAssertTrue(setup.isHittable)
        setup.tap()
        XCTAssertTrue(app.buttons["health-connect"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["health-not-requested"].exists)
        XCTAssertTrue(app.buttons["health-watch-guide"].exists)
        XCTAssertTrue(app.textFields["health-maximum-heart-rate"].exists)
        XCTAssertFalse(app.staticTexts["Apple Health connected"].exists)
    }
}

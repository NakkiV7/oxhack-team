import XCTest

final class PatientOnboardingFlowTests: XCTestCase {
    @MainActor func testPitchExamplesAreAvailableInsideTheAppWithoutConnectingServices() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = UUID().uuidString
        app.launch()
        let studio = app.buttons["demo-studio"]
        for _ in 0..<4 where !studio.isHittable { app.swipeUp() }
        XCTAssertTrue(studio.waitForExistence(timeout: 5))
        studio.tap()
        XCTAssertTrue(app.staticTexts["See Spottr in motion."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["demo-example-squat"].exists)
        XCTAssertTrue(app.buttons["demo-example-pushup"].exists)
        app.buttons["demo-example-pushup"].tap()
        XCTAssertTrue(app.staticTexts["Recorded example · not your workout"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Cavemantraining · CC BY-SA 4.0"].exists)
    }

    @MainActor func testNewGuestCanGoFromIntroductionStraightToTheirTrainingPath() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["SPOTTR_FORCE_ONBOARDING"] = "1"
        app.launch()
        XCTAssertTrue(app.staticTexts["Move a little.\nBuild from there."].waitForExistence(timeout: 8))
        for _ in 0..<3 { app.buttons["onboarding-continue"].tap() }
        XCTAssertTrue(app.buttons["first-session-path"].waitForExistence(timeout: 5))
        app.buttons["first-session-path"].tap()
        XCTAssertTrue(app.buttons["path-build-banner"].waitForExistence(timeout: 5))
        app.buttons["path-build-banner"].tap()
        XCTAssertTrue(app.buttons["path-continue"].waitForExistence(timeout: 5))
    }
}

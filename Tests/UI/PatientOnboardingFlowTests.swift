import XCTest

final class PatientOnboardingFlowTests: XCTestCase {
    @MainActor func testWorkoutUsesOnlyThePhoneCameraWithoutPairingControls() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = UUID().uuidString
        app.launch()
        app.buttons["Start session"].tap()
        XCTAssertTrue(app.buttons["Use camera"].waitForExistence(timeout: 5))
        for _ in 0..<3 { app.swipeUp() }
        XCTAssertFalse(app.buttons["secondary-camera-menu"].exists)
        XCTAssertFalse(app.buttons["Pair side camera"].exists)
        XCTAssertFalse(app.buttons["front-camera-toggle"].exists)
        XCTAssertTrue(app.buttons["Use manual reps"].exists)
    }

    @MainActor func testMovementGuidesAreAvailableWithoutConnectingServices() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchEnvironment["SPOTTR_DATA_NAMESPACE"]=UUID().uuidString;app.launch()
        app.buttons["profile-settings"].tap()
        let guides=app.buttons["Movement guides"]
        for _ in 0..<8 where !guides.isHittable { app.swipeUp() }
        XCTAssertTrue(guides.isHittable);guides.tap()
        XCTAssertTrue(app.buttons["guide-wallPushup"].waitForExistence(timeout:4))
    }

    @MainActor func testNewGuestCanGoFromIntroductionStraightToTheirTrainingPath() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["SPOTTR_FORCE_ONBOARDING"] = "1"
        app.launch()
        XCTAssertTrue(app.staticTexts["Move a little.\nBuild from there."].waitForExistence(timeout: 8))
        for _ in 0..<6 { app.buttons["onboarding-continue"].tap() }
        let nextSkill=app.buttons["first-session-path"]
        for _ in 0..<6 where !nextSkill.isHittable { app.swipeUp() }
        XCTAssertTrue(nextSkill.isHittable);nextSkill.tap()
        XCTAssertTrue(app.staticTexts["Your next level"].waitForExistence(timeout:4))
        XCTAssertTrue(app.buttons["skill-wallPushup"].exists)
        XCTAssertFalse(app.buttons["path-build-banner"].exists)
    }
}

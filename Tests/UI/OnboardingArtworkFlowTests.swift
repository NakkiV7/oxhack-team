import XCTest

final class OnboardingArtworkFlowTests: XCTestCase {
    @MainActor func testMovementDemonstrationLeadsToOptionalWatchSetupAndGuestTraining() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["SPOTTR_FORCE_ONBOARDING"] = "1"
        app.launch()
        XCTAssertTrue(app.staticTexts["A comfortable squat"].waitForExistence(timeout: 8))
        let capture = XCTAttachment(screenshot: app.screenshot()); capture.name = "Onboarding movement"; capture.lifetime = .keepAlways; add(capture)
        let next = app.buttons["onboarding-continue"]
        next.tap()
        XCTAssertTrue(app.staticTexts["onboarding-health-optional"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["onboarding-watch-guide"].isHittable)
        XCTAssertTrue(app.buttons["onboarding-health-setup"].isHittable)
        let setup = XCTAttachment(screenshot: app.screenshot()); setup.name = "Onboarding optional setup"; setup.lifetime = .keepAlways; add(setup)
        for _ in 0..<5 { next.tap() }
        XCTAssertTrue(app.buttons["profile-settings"].waitForExistence(timeout: 5))
    }
}

import XCTest

final class OfflineMVPFlowTests: XCTestCase {
    @MainActor func testOnboardingPlacesComfortableSkillsAndConsumerCoachHasOnlyChoices() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["SPOTTR_FORCE_ONBOARDING"] = "1"
        app.launch()
        let next = app.buttons["onboarding-continue"]
        XCTAssertTrue(next.waitForExistence(timeout: 8))
        next.tap()
        XCTAssertTrue(app.switches["goal-weightManagement"].exists)
        next.tap()
        next.tap()
        XCTAssertTrue(app.buttons["comfortable-wallPushup"].waitForExistence(timeout: 3))
        app.buttons["comfortable-wallPushup"].tap()
        next.tap()
        XCTAssertTrue(app.buttons["coach-voice-maya"].waitForExistence(timeout: 3))
        app.buttons["coach-voice-maya"].tap()
        attach(app, name: "abstract-trainer-onboarding")
        next.tap()
        XCTAssertTrue(app.buttons["profile-settings"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.tabBars.buttons["Progress"].exists)
        app.tabBars.buttons["Skills"].tap()
        XCTAssertTrue(app.staticTexts["Starting skill"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Your next quest"].exists)
        XCTAssertTrue(app.staticTexts["Next challenge"].exists)
        attach(app, name: "vertical-skill-path")
        app.tabBars.buttons["Coach"].tap()
        XCTAssertTrue(app.buttons["coach-option-Start moving"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.textViews.element.exists)
        XCTAssertFalse(app.buttons["Generate coach summary"].exists)
        attach(app, name: "offline-coach-options")
    }
    @MainActor private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

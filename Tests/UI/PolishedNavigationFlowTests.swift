import XCTest

final class PolishedNavigationFlowTests: XCTestCase {
    @MainActor func testPrimaryScreensKeepClearActionsAndCoachChoicesExposeSelection() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["today-start-session"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Insights"].tap()
        XCTAssertTrue(app.staticTexts["Your progress"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Insights."].exists)
        app.tabBars.buttons["Coach"].tap()
        let easier = app.buttons["coach-option-Make it easier"]
        XCTAssertTrue(easier.waitForExistence(timeout: 3))
        easier.tap()
        XCTAssertTrue(easier.isSelected)
        XCTAssertFalse(app.staticTexts["Choices and guidance are built into Spottr. Everything here runs on your iPhone."].exists)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Coach choices"; image.lifetime = .keepAlways; add(image)
        app.tabBars.buttons["Skills"].tap()
        XCTAssertTrue(app.buttons["skill-path-family"].waitForExistence(timeout: 3))
        let skills = XCTAttachment(screenshot: app.screenshot()); skills.name = "Skills path"; skills.lifetime = .keepAlways; add(skills)
        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.buttons["today-start-session"].waitForExistence(timeout: 3))
    }

    @MainActor func testAccessibilityTextKeepsTrainingAndInsightsNavigationReachable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = UUID().uuidString
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let start = app.buttons["today-start-session"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        for _ in 0..<8 where !start.isHittable { app.swipeUp() }
        XCTAssertTrue(start.isHittable)
        let today = XCTAttachment(screenshot: app.screenshot()); today.name = "Today accessibility text"; today.lifetime = .keepAlways; add(today)
        app.tabBars.buttons["Insights"].tap()
        XCTAssertTrue(app.buttons["insights-section-selector"].waitForExistence(timeout: 3))
        app.buttons["insights-section-selector"].tap()
        let reports = app.buttons["Reports"].firstMatch
        XCTAssertTrue(reports.waitForExistence(timeout: 3)); reports.tap()
        XCTAssertTrue(app.staticTexts["No session reports yet"].waitForExistence(timeout: 3))
        let insight = XCTAttachment(screenshot: app.screenshot()); insight.name = "Insights accessibility text"; insight.lifetime = .keepAlways; add(insight)
    }
}

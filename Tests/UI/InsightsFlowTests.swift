import XCTest

final class InsightsFlowTests: XCTestCase {
    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor func testInsightsShowsTheCalendarReportsWeeklyReviewAndResearch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = UUID().uuidString
        app.launch()

        // Log one manual workout so today has training: 3 sets of 8 wall push-ups.
        app.tabBars.buttons["Skills"].tap()
        app.buttons["skill-wallPushup"].tap()
        XCTAssertTrue(app.staticTexts["Wall push-ups"].waitForExistence(timeout: 5))
        app.buttons["Log manually"].tap()
        XCTAssertTrue(app.textFields["Reps per set"].waitForExistence(timeout: 3))
        app.buttons["Save workout"].tap()
        XCTAssertTrue(app.staticTexts["Workout saved"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // Calendar: today is a logged training day with its totals and sets.
        app.tabBars.buttons["Insights"].tap()
        XCTAssertTrue(app.staticTexts["Insights."].waitForExistence(timeout: 5))
        app.segmentedControls["insights-section"].buttons["Calendar"].tap()   // the last section is remembered between launches
        let today = app.buttons["calendar-day-\(Calendar.current.component(.day, from: Date()))"]
        XCTAssertTrue(today.waitForExistence(timeout: 3))
        XCTAssertTrue(today.label.contains("24 reps, logged"), "Today reads: \(today.label)")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "3 sets")).firstMatch.exists)
        // Sample days fill the past for presentations and always say they are samples.
        XCTAssertTrue(app.buttons["calendar-samples"].exists)
        let dayOfMonth = Calendar.current.component(.day, from: Date())
        if dayOfMonth > 1 { XCTAssertTrue(app.buttons["calendar-day-\(dayOfMonth - 1)"].label.hasSuffix("sample"), "Yesterday reads: \(app.buttons["calendar-day-\(dayOfMonth - 1)"].label)") }
        snapshot(app, "1-calendar")
        app.swipeUp()
        snapshot(app, "2-calendar-streaks")
        app.swipeDown(); app.swipeDown()

        // Reports: the workout is listed and opens the existing session report.
        app.segmentedControls["insights-section"].buttons["Reports"].tap()
        let report = app.buttons["insights-report"].firstMatch
        XCTAssertTrue(report.waitForExistence(timeout: 3))
        snapshot(app, "3-reports")
        report.tap()
        XCTAssertTrue(app.staticTexts["Your sets"].waitForExistence(timeout: 5))
        snapshot(app, "4-session-report")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // Weekly review: this week against last, the coach's review card and concrete quests.
        app.segmentedControls["insights-section"].buttons["Weekly"].tap()
        XCTAssertTrue(app.staticTexts["Training days"].waitForExistence(timeout: 3))
        snapshot(app, "5-weekly")
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Next week’s quests"].exists)
        snapshot(app, "6-weekly-quests")
        app.swipeDown(); app.swipeDown()

        // Research: the reviewed guidance library with links to each source.
        app.segmentedControls["insights-section"].buttons["Research"].tap()
        XCTAssertTrue(app.links.firstMatch.waitForExistence(timeout: 3) || app.buttons["Read the source"].firstMatch.waitForExistence(timeout: 3))
        snapshot(app, "7-research")
    }
}

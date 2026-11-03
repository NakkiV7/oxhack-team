import XCTest

final class TrainingPathFlowTests: XCTestCase {
    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
    private func option(_ app: XCUIApplication, _ prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    @MainActor func testBuildingAPathKeepsTheTreeReachableAndShowsTheMapAfterSaving() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = UUID().uuidString
        app.launch()
        app.tabBars.buttons["Skills"].tap()

        // Before a path exists, the existing challenge tree is unchanged and a card offers to build one.
        XCTAssertTrue(app.buttons["skill-wallPushup"].waitForExistence(timeout: 5))
        let banner = app.buttons["path-build-banner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 3))
        snapshot(app, "1-skills-before-path")
        banner.tap()

        // Five questions. Without a configured gateway the catalogue path is built and labelled as such.
        XCTAssertTrue(option(app, "Squat path").waitForExistence(timeout: 3))
        snapshot(app, "2-survey-goal")
        app.buttons["path-continue"].tap()
        option(app, "I'm not sure").tap()
        app.buttons["path-continue"].tap()
        option(app, "Stable support").tap()
        app.buttons["path-continue"].tap()
        app.buttons["path-continue"].tap()
        option(app, "Learn the movement").tap()
        app.buttons["Encouraging"].tap()
        snapshot(app, "3-survey-preferences")
        app.buttons["path-continue"].tap()
        XCTAssertTrue(app.buttons["path-build"].waitForExistence(timeout: 3))
        snapshot(app, "4-survey-review")
        app.buttons["path-build"].tap()
        let accept = app.buttons["path-accept"]
        XCTAssertTrue(accept.waitForExistence(timeout: 30))
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "path-provenance").firstMatch.label, "Built from the catalogue")
        snapshot(app, "5-path-preview")
        accept.tap()

        // The saved path: the start is current, the goal is locked, and the full tree is one tap away.
        XCTAssertTrue(app.staticTexts["Your path."].waitForExistence(timeout: 5))
        let start = app.buttons["path-node-gluteBridge"]
        XCTAssertTrue(start.waitForExistence(timeout: 3))
        XCTAssertTrue(start.label.contains("Current step"))
        XCTAssertTrue(app.buttons["path-node-assistedSquat"].label.contains("Locked"))
        snapshot(app, "6-path-home")
        for _ in 0..<3 { app.swipeUp() }
        snapshot(app, "7-path-map")

        let goal = app.buttons["path-node-assistedSquat"]
        if !goal.isHittable { app.swipeUp() }
        goal.tap()
        let goTo = app.buttons["path-step-goto"]
        XCTAssertTrue(goTo.waitForExistence(timeout: 3))
        XCTAssertTrue(goTo.label.contains("Split squats"))
        snapshot(app, "8-locked-step-sheet")
        goTo.tap()
        XCTAssertTrue(app.staticTexts["Split squats"].waitForExistence(timeout: 3))
        app.swipeDown(velocity: .fast)

        for _ in 0..<4 { app.swipeDown() }
        app.buttons["path-current-quest"].tap()
        XCTAssertTrue(app.buttons["path-step-start"].waitForExistence(timeout: 3))
        snapshot(app, "9-current-step-sheet")
        app.swipeDown(velocity: .fast)

        app.segmentedControls["path-view-mode"].buttons["List"].tap()
        XCTAssertTrue(app.buttons["path-row-squat"].waitForExistence(timeout: 3))
        snapshot(app, "10-path-list")
        for _ in 0..<4 { app.swipeUp() }
        app.buttons["path-all-challenges"].tap()
        XCTAssertTrue(app.buttons["skill-wallPushup"].waitForExistence(timeout: 5))
        snapshot(app, "11-all-challenges")
    }
}

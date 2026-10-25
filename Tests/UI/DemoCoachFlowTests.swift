import XCTest

final class DemoCoachFlowTests: XCTestCase {
    @MainActor func testScriptedCoachRequiresPreviewSupportReviewAndExplicitMondayStart() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = UUID().uuidString
        app.launch()
        app.tabBars.buttons["Coach"].tap()
        XCTAssertTrue(app.scrollViews["coach-conversation"].waitForExistence(timeout: 5))
        XCTAssertFalse(element("demo-coach-conversation", in: app).exists)
        XCTAssertFalse(element("demo-coach-preview-badge", in: app).exists)

        app.tabBars.buttons["Today"].tap()
        app.buttons["profile-settings"].tap()
        let preview = app.switches["testflight-preview-toggle"]
        reveal(preview, in: app)
        thumb(preview).tap()
        let profileDone = app.navigationBars["Profile & settings"].buttons["Done"]
        if profileDone.exists { profileDone.tap() }
        XCTAssertTrue(app.tabBars.buttons["Coach"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Coach"].tap()
        XCTAssertTrue(element("demo-coach-conversation", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("demo-coach-preview-badge", in: app).exists)
        XCTAssertTrue(element("demo-coach-user-message", in: app).exists)
        XCTAssertTrue(element("demo-coach-workflow", in: app).exists)
        let count = app.staticTexts["demo-coach-selection-count"]
        let approve = app.buttons["demo-coach-approve"]
        XCTAssertEqual(count.label, "6 of 7 exercises selected")
        XCTAssertFalse(approve.isEnabled)
        XCTAssertFalse(app.buttons["demo-coach-start-monday"].exists)

        let mondayWall = element("demo-coach-exercise-monday-wallPushup", in: app)
        reveal(mondayWall, in: app)
        thumb(mondayWall).tap()
        XCTAssertEqual(count.label, "5 of 7 exercises selected")
        let thursdayWall = element("demo-coach-exercise-thursday-wallPushup", in: app)
        reveal(thursdayWall, in: app)
        XCTAssertEqual(thumb(thursdayWall).value as? String, "0", "One exercise selection must apply to every day")
        XCTAssertTrue(approve.isEnabled)
        approve.tap()
        let mondayStart = app.buttons["demo-coach-start-monday"]
        reveal(mondayStart, in: app, up: false)
        XCTAssertTrue(mondayStart.isEnabled)
        XCTAssertFalse(app.buttons["configured-start"].exists, "Approving a week must not start a workout")

        let stretch = element("demo-coach-exercise-tuesday-hipFlexorStretch", in: app)
        reveal(stretch, in: app)
        thumb(stretch).tap()
        XCTAssertEqual(count.label, "6 of 7 exercises selected")
        XCTAssertTrue(approve.isEnabled)
        reveal(mondayWall, in: app, up: false)
        XCTAssertTrue(mondayStart.waitForNonExistence(timeout: 3), "Changing a selection must invalidate approval")
        thumb(mondayWall).tap()
        XCTAssertEqual(count.label, "7 of 7 exercises selected")
        XCTAssertFalse(approve.isEnabled, "Restoring wall push-ups must require wall support confirmation")
        let wallSupport = element("demo-coach-support-wall", in: app)
        reveal(wallSupport, in: app)
        thumb(wallSupport).tap()
        XCTAssertTrue(approve.isEnabled)
        approve.tap()
        reveal(mondayStart, in: app, up: false)
        mondayStart.tap()
        XCTAssertTrue(app.buttons["configured-start"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Wall push-ups"].exists)
        XCTAssertEqual(app.staticTexts["configured-quantity"].label, "—")
        XCTAssertFalse(app.textFields["configured-reps"].exists, "Starting the plan must still wait for an explicit set start")
        XCTAssertFalse(app.buttons["configured-input-menu"].exists, "Wall push-ups stay manual; no camera request is needed")
        app.buttons["Finish custom session"].tap()
        app.buttons["Finish and save ended sets"].tap()
        XCTAssertTrue(app.staticTexts["No ended sets to save."].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(element("demo-coach-conversation", in: app).waitForExistence(timeout: 5))
    }

    @MainActor private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor private func thumb(_ toggle: XCUIElement) -> XCUIElement {
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch : toggle
    }

    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication, up: Bool = true) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            if up { app.swipeUp() } else { app.swipeDown() }
        }
        if element.waitForExistence(timeout: 3) && element.isHittable { return }
        let description = app.debugDescription
        print("DEMO_COACH_HIERARCHY_BEGIN\n\(description)\nDEMO_COACH_HIERARCHY_END")
        let hierarchy = XCTAttachment(string: description)
        hierarchy.name = "Demo Coach accessibility hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        XCTFail("Could not reveal requested accessibility element")
    }
}

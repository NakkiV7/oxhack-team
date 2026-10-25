import XCTest

final class CoachFlowTests: XCTestCase {
    @MainActor func testCoachSettingsDoneScrollAndExplanationDismissKeyboardWithoutSavingDraft() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = UUID().uuidString
        app.launch()
        app.tabBars.buttons["Coach"].tap()
        app.buttons["Coach settings"].tap()
        let address = app.textFields["Gateway URL"]
        XCTAssertTrue(address.waitForExistence(timeout: 3))
        let original = address.value as? String ?? ""
        address.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        address.typeText(".synthetic")
        let draft = address.value as? String ?? ""
        XCTAssertEqual(draft, original + ".synthetic")
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 3), "Settings need an explicit keyboard dismissal action.")
        done.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertEqual(address.value as? String, draft)

        address.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        address.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: draft.count))
        let blank = address.value as? String ?? ""
        XCTAssertTrue(blank.isEmpty || blank == address.placeholderValue)
        app.descendants(matching: .any)["coach-settings-form"].swipeDown()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertEqual(address.value as? String ?? "", blank)

        address.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        address.typeText("synthetic")
        let explanation = app.staticTexts.matching(NSPredicate(format: "label == %@", "Use the access token for your Spottr gateway. Your Gemini provider key stays on the server. The access token is stored in this iPhone’s Keychain.")).firstMatch
        XCTAssertTrue(explanation.isHittable)
        explanation.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertEqual(address.value as? String, "synthetic")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["Your next move."].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Cancel coach request"].exists)
        app.terminate()
        app.launch()
        app.tabBars.buttons["Coach"].tap()
        app.buttons["Coach settings"].tap()
        XCTAssertTrue(address.waitForExistence(timeout: 3))
        XCTAssertEqual(address.value as? String, original)
        app.buttons["Cancel"].tap()
    }

    @MainActor func testCoachTitleAndDownwardScrollDismissKeyboardWithoutSendingTheDraft() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = UUID().uuidString
        app.launch()
        app.tabBars.buttons["Coach"].tap()
        let title = app.staticTexts["Your next move."]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let composer = app.descendants(matching: .any)["coach-message"]
        XCTAssertTrue(composer.waitForExistence(timeout: 3))
        composer.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        let draft = "Synthetic draft, do not send."
        composer.typeText(draft)

        XCTAssertTrue(title.isHittable)
        title.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertEqual(composer.value as? String, draft)

        composer.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        app.scrollViews["coach-conversation"].swipeDown()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertEqual(composer.value as? String, draft)
        XCTAssertFalse(app.buttons["Cancel coach request"].exists)
        XCTAssertFalse(app.staticTexts["SPOTTR · GEMINI"].exists)
    }

    @MainActor func testSavedProfileFocusAndWeeklyTargetAppearInCoachAndReportContextWithoutSending() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = UUID().uuidString
        app.launch()
        app.tabBars.buttons["Coach"].tap()
        XCTAssertTrue(app.staticTexts["Your next move."].waitForExistence(timeout: 5))
        app.tabBars.buttons["Today"].tap()
        app.buttons["profile-settings"].tap()
        let weeklyTarget = app.steppers["weekly-training-target"]
        XCTAssertTrue(weeklyTarget.waitForExistence(timeout: 3))
        weeklyTarget.buttons["weekly-training-target-Increment"].tap()
        app.buttons["goal-strength"].tap()
        let mobility = app.buttons["goal-mobility"]
        for _ in 0..<4 where !mobility.isHittable { app.swipeUp() }
        mobility.tap()
        let save = app.buttons["save-profile"]
        for _ in 0..<4 where !save.isHittable { app.swipeUp() }
        save.tap()
        app.navigationBars.buttons["Done"].tap()

        app.tabBars.buttons["Coach"].tap()
        let coachContext = app.staticTexts["coach-goal-context"]
        XCTAssertTrue(coachContext.waitForExistence(timeout: 5))
        XCTAssertEqual(coachContext.label, "Mobility · 4 days/week")
        XCTAssertFalse(app.staticTexts["Thinking…"].exists)
        app.tabBars.buttons["Progress"].tap()
        let reportContext = app.staticTexts["coach-summary-goal-context"]
        for _ in 0..<5 where !reportContext.exists { app.swipeUp() }
        XCTAssertTrue(reportContext.waitForExistence(timeout: 3))
        XCTAssertEqual(reportContext.label, "Mobility · 4 days/week")
        XCTAssertFalse(app.staticTexts["Thinking…"].exists)
    }

    func testCoachNeedsExplicitSendAndOffersLocalConnectionSettings() {
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = UUID().uuidString
        app.launch()
        app.tabBars.buttons["Coach"].tap()
        XCTAssertTrue(app.staticTexts["Your next move."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Thinking…"].exists)
        app.buttons["Coach settings"].tap()
        XCTAssertTrue(app.textFields["Gateway URL"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.secureTextFields["Gateway access token"].exists)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Propose a workout"].exists)
    }

    @MainActor func testConfiguredCameraChoiceNeedsResetConfirmationAndOtherExercisesRemainManual() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["SPOTTR_APPROVED_PLAN_FIXTURE"] = #"{"items":[{"exerciseID":"squat","sets":1,"target":2,"unit":"reps","restSeconds":30},{"exerciseID":"plank","sets":1,"target":20,"unit":"seconds","restSeconds":30}],"approvedAt":0,"rationale":"Synthetic UI fixture"}"#
        app.launch()
        app.tabBars.buttons["Coach"].tap()
        let startPlan = app.buttons["Start saved workout"]
        for _ in 0..<6 where !startPlan.isHittable { app.swipeUp() }
        XCTAssertTrue(startPlan.waitForExistence(timeout: 3), "The isolated debug fixture should expose the saved workout without persisting a plan.")
        startPlan.tap()
        let start = app.buttons["configured-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 3))
        let input = app.buttons["configured-input-menu"]
        XCTAssertTrue(input.exists)
        start.tap()
        let reps = app.textFields["configured-reps"]
        for _ in 0..<4 where !reps.isHittable || reps.frame.maxY > app.frame.maxY - 190 { app.swipeUp() }
        reps.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        reps.typeText("3")
        if app.buttons["Done entering reps"].exists { app.buttons["Done entering reps"].tap() }
        for _ in 0..<4 where !input.isHittable { app.swipeDown() }
        input.tap(); app.buttons["configured-input-phoneCamera"].tap()
        app.buttons["Cancel"].tap()
        XCTAssertEqual(reps.value as? String, "3")
        input.tap(); app.buttons["configured-input-phoneCamera"].tap()
        app.buttons["Reset and switch"].tap()
        XCTAssertTrue(start.exists)
        XCTAssertFalse(reps.exists)
        XCTAssertEqual(app.staticTexts["configured-quantity"].label, "0")
        XCTAssertEqual(app.switches["configured-voice-toggle"].value as? String, "0")
        input.tap(); app.buttons["configured-input-manual"].tap()
        XCTAssertTrue(start.exists)
        start.tap()
        for _ in 0..<4 where !reps.isHittable || reps.frame.maxY > app.frame.maxY - 190 { app.swipeUp() }
        reps.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        reps.typeText("2")
        if app.buttons["Done entering reps"].exists { app.buttons["Done entering reps"].tap() }
        app.buttons["configured-end"].tap()
        app.buttons["configured-next"].tap()
        XCTAssertFalse(input.exists)
        XCTAssertTrue(app.buttons["configured-start"].exists)
        app.buttons["Finish custom session"].tap()
        app.buttons["Finish and save ended sets"].tap()
        XCTAssertTrue(app.staticTexts["Session saved on this iPhone."].waitForExistence(timeout: 3))
        app.buttons["Done"].tap()
    }

}

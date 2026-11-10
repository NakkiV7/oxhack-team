import XCTest
import Vision

final class MembershipFlowTests: XCTestCase {
    @MainActor func testAccountWelcomeDefersInputsAndAppleCheckpointsBeforeIdentity() throws {
        continueAfterFailure = false
        let app = launchSignedOutAccount()
        defer { app.terminate() }
        XCTAssertFalse(app.textFields["Training person’s age in years"].exists, "The first welcome must defer enrolment inputs")
        XCTAssertFalse(app.textFields["Adult account owner’s email"].exists)
        XCTAssertTrue(app.staticTexts["Move at your own pace"].exists)
        for choice in ["Continue with email", "Sign in with passkey", "Recover account"] {
            XCTAssertTrue(app.buttons[choice].exists); XCTAssertTrue(app.buttons[choice].isHittable)
        }
        XCTAssertTrue(app.buttons["account-membership"].isHittable)
        let apple = app.buttons["account-apple-sign-in"]
        XCTAssertTrue(apple.exists); XCTAssertTrue(apple.isHittable)
        apple.tap()
        let age = app.textFields["Training person’s age in years"]
        XCTAssertTrue(age.waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["Adult account owner’s email"].exists)
        age.tap(); age.typeText("30")
        revealAndTap(app.buttons["Confirm age and role"], in: app)
        XCTAssertTrue(apple.waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["Training person’s age in years"].exists)
        XCTAssertFalse(app.textFields["Adult account owner’s email"].exists)
        XCTAssertFalse(app.buttons["Send verification code"].exists)
    }

    @MainActor func testAccountEmailCheckpointAndBackRetainAgeAndGuardianChoice() throws {
        continueAfterFailure = false
        let app = launchSignedOutAccount()
        defer { app.terminate() }
        app.buttons["Continue with email"].tap()
        let age = app.textFields["Training person’s age in years"]
        XCTAssertTrue(age.waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["Adult account owner’s email"].exists)
        let owner = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Account owner")).firstMatch
        XCTAssertTrue(owner.exists); owner.tap()
        let guardian = app.buttons["Adult guardian managing a profile"]
        XCTAssertTrue(guardian.waitForExistence(timeout: 3)); guardian.tap()
        age.tap(); age.typeText("12")
        revealAndTap(app.buttons["Confirm age and role"], in: app)
        let email = app.textFields["Adult account owner’s email"]
        XCTAssertTrue(email.waitForExistence(timeout: 5))
        XCTAssertFalse(age.exists); XCTAssertFalse(app.buttons["account-apple-sign-in"].exists)
        revealAndTap(app.buttons["Back"], in: app)
        XCTAssertTrue(age.waitForExistence(timeout: 5)); XCTAssertEqual(age.value as? String, "12")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "Adult guardian managing a profile", "Adult guardian managing a profile")).firstMatch.exists)
        revealAndTap(app.buttons["Back"], in: app)
        XCTAssertTrue(app.staticTexts["Move at your own pace"].waitForExistence(timeout: 5))
        XCTAssertFalse(age.exists); XCTAssertFalse(email.exists)
        app.buttons["Continue with email"].tap()
        XCTAssertTrue(email.waitForExistence(timeout: 5)); XCTAssertFalse(age.exists)
        XCTAssertFalse(app.buttons["account-apple-sign-in"].exists)
    }

    @MainActor func testAccountRecoveryChoosesEmailWithoutNewEnrolmentCheckpoint() throws {
        continueAfterFailure = false
        let app = launchSignedOutAccount()
        defer { app.terminate() }
        app.buttons["Recover account"].tap()
        XCTAssertTrue(app.buttons["Continue with email"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["Training person’s age in years"].exists)
        XCTAssertFalse(app.textFields["Adult account owner’s email"].exists)
        XCTAssertTrue(app.buttons["account-apple-sign-in"].exists)
        app.buttons["Continue with email"].tap()
        XCTAssertTrue(app.textFields["Adult account owner’s email"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["Training person’s age in years"].exists)
        XCTAssertFalse(app.buttons["account-apple-sign-in"].exists)
        XCTAssertTrue(app.staticTexts["Recover account"].exists)
        XCTAssertTrue(app.buttons["Send verification code"].exists)
        revealAndTap(app.buttons["Back"], in: app)
        XCTAssertTrue(app.buttons["account-apple-sign-in"].waitForExistence(timeout: 5))
        revealAndTap(app.buttons["Back"], in: app)
        XCTAssertTrue(app.staticTexts["Move at your own pace"].waitForExistence(timeout: 5))
    }

    @MainActor private func launchSignedOutAccount() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.navigationBars["Account and privacy"].waitForExistence(timeout: 8))
        return app
    }
    @MainActor private func revealAndTap(_ button: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<5 where !button.isHittable { app.swipeUp() }
        XCTAssertTrue(button.exists); XCTAssertTrue(button.isHittable); button.tap()
    }

    @MainActor func testSignedOutMembershipRestoreAndHelpRemainReachableWithoutWorkoutAccess() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = UUID().uuidString
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.navigationBars["Account and privacy"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["today-start-session"].exists)
        let membership = app.buttons["account-membership"]
        XCTAssertTrue(membership.exists)
        XCTAssertTrue(membership.isHittable, "Membership must be visible on first launch without scrolling")
        membership.tap()
        XCTAssertTrue(app.navigationBars["Membership"].waitForExistence(timeout: 5))
        let restore = app.buttons["membershipRestore"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["membershipBetaAccess"].exists)
        XCTAssertFalse(app.buttons["membershipPurchase-monthly"].exists && app.buttons["membershipPurchase-monthly"].isEnabled)
        let support = app.descendants(matching: .any).matching(identifier: "membershipSupport").firstMatch
        for _ in 0..<8 where !support.isHittable { app.swipeUp() }
        XCTAssertTrue(support.exists)
        for _ in 0..<8 where !restore.isHittable { app.swipeDown() }
        XCTAssertTrue(restore.isHittable); restore.tap()
        let feedback = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@ OR label CONTAINS[c] %@", "No active membership for this account", "Purchases could not be restored", "Approval is needed to continue")).firstMatch
        let returnedFeedback = feedback.waitForExistence(timeout: 5)
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Signed-out restore outcome or native guardian approval"
        attachment.lifetime = .keepAlways; add(attachment)
        let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
        try VNImageRequestHandler(cgImage: XCTUnwrap(screenshot.image.cgImage)).perform([request])
        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined().lowercased().filter { $0.isLetter }
        let nativeApproval = text.contains("unlockguardiancontrols") || (text.contains("enteriphonepasscode") && text.contains("spottr"))
        XCTAssertTrue(returnedFeedback || nativeApproval, "Restore must show a result or request the existing device-owner approval")
        XCTAssertFalse(app.buttons["today-start-session"].exists)
    }
}

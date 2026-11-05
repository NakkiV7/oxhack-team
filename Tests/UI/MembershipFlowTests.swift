import XCTest

final class MembershipFlowTests: XCTestCase {
    @MainActor func testBetaAccessAndMembershipNavigationDoNotRequireAccountOrPurchase() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["profile-settings"].waitForExistence(timeout: 8))
        app.buttons["profile-settings"].tap()
        XCTAssertTrue(app.staticTexts["profile-beta-access"].waitForExistence(timeout: 4))
        let membership = app.buttons["profile-membership"]
        XCTAssertTrue(membership.isHittable)
        membership.tap()
        XCTAssertTrue(app.staticTexts["membershipBetaAccess"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["membershipAppleConfirmation"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Spottr beta membership"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let account = app.descendants(matching: .any).matching(identifier: "profile-website-account").firstMatch
        for _ in 0..<10 where !account.isHittable { app.swipeUp() }
        XCTAssertTrue(account.exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "profile-privacy").firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "profile-support").firstMatch.exists)
        XCTAssertTrue(app.staticTexts["profile-account-separation"].exists)
        XCTAssertTrue(app.buttons["prepare-history-export"].exists)
        app.navigationBars.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["profile-settings"].waitForExistence(timeout: 3))
    }

    @MainActor func testPausedSquatGuideShowsTimingForBetaReview() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["profile-settings"].waitForExistence(timeout: 8))
        app.buttons["profile-settings"].tap()
        let lessons = app.buttons["Movement guides"]
        for _ in 0..<8 where !lessons.isHittable { app.swipeUp() }
        lessons.tap()
        let guide = app.buttons["guide-pausedSquat"]
        for _ in 0..<20 where !guide.isHittable { app.swipeUp() }
        XCTAssertTrue(guide.isHittable)
        guide.tap()
        XCTAssertTrue(app.navigationBars["Paused squats"].waitForExistence(timeout: 4))
        let graphic = XCTAttachment(screenshot: app.screenshot())
        graphic.name = "Paused squat guide beta"
        graphic.lifetime = .keepAlways
        add(graphic)
        let timing = app.staticTexts["Lower to depth and hold for at least 2 seconds"]
        for _ in 0..<4 where !timing.isHittable { app.swipeUp() }
        XCTAssertTrue(timing.isHittable)
        let instructions = XCTAttachment(screenshot: app.screenshot())
        instructions.name = "Paused squat timing beta"
        instructions.lifetime = .keepAlways
        add(instructions)
    }
}

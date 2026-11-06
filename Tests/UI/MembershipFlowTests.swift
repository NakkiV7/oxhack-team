import XCTest

final class MembershipFlowTests: XCTestCase {
    @MainActor func testSignedOutMembershipRestoreAndHelpRemainReachableWithoutWorkoutAccess() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.navigationBars["Account setup"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["today-start-session"].exists)
        let membership = app.buttons["account-membership"]
        for _ in 0..<8 where !membership.isHittable { app.swipeUp() }
        XCTAssertTrue(membership.isHittable)
        membership.tap()
        XCTAssertTrue(app.navigationBars["Membership"].waitForExistence(timeout: 5))
        let restore = app.buttons["membershipRestore"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["membershipBetaAccess"].exists)
        XCTAssertFalse(app.buttons["membershipPurchase-monthly"].exists && app.buttons["membershipPurchase-monthly"].isEnabled)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Signed-out membership and restore"
        attachment.lifetime = .keepAlways
        add(attachment)
        let support = app.descendants(matching: .any).matching(identifier: "membershipSupport").firstMatch
        for _ in 0..<8 where !support.isHittable { app.swipeUp() }
        XCTAssertTrue(support.exists)
    }
}

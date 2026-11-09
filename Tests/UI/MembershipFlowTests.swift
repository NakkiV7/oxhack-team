import XCTest
import Vision

final class MembershipFlowTests: XCTestCase {
    @MainActor func testSignedOutMembershipRestoreAndHelpRemainReachableWithoutWorkoutAccess() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = UUID().uuidString
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.navigationBars["Account and privacy"].waitForExistence(timeout: 8))
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

import XCTest

final class SecondaryCameraFlowTests: XCTestCase {
    @MainActor func testSideCameraPairingIsExplicitAndInvalidPairingCannotStartCapture() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = UUID().uuidString
        app.launch()
        app.buttons["Start session"].tap()
        XCTAssertTrue(app.buttons["secondary-camera-menu"].waitForExistence(timeout: 3))
        app.buttons["secondary-camera-menu"].tap()
        app.buttons["Pair side camera"].tap()
        XCTAssertTrue(app.navigationBars["Side camera"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.secureTextFields["secondary-camera-token"].exists)
        let fingerprint = app.descendants(matching: .any).matching(identifier: "secondary-camera-pin").firstMatch
        fingerprint.tap()
        fingerprint.typeText("z")
        app.buttons["secondary-camera-save"].tap()
        XCTAssertTrue(app.staticTexts["secondary-camera-pairing-error"].exists)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Resume"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Connecting to side camera…"].exists)
    }
}

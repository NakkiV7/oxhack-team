import XCTest

final class SecondaryCameraFlowTests: XCTestCase {
    @MainActor func testSideCameraSettingsDoneScrollAndExplanationDismissKeyboardWithoutSavingDraft() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = UUID().uuidString
        app.launch()
        app.buttons["Start session"].tap()
        app.buttons["secondary-camera-menu"].tap()
        app.buttons["Pair side camera"].tap()
        let address = app.textFields["secondary-camera-address"]
        XCTAssertTrue(address.waitForExistence(timeout: 3))
        let original = address.value as? String ?? ""
        let originalText = original == address.placeholderValue ? "" : original
        address.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        address.typeText(".synthetic")
        let draft = address.value as? String ?? ""
        XCTAssertEqual(draft, originalText + ".synthetic")
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 3), "Pairing needs an explicit keyboard dismissal action.")
        done.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertEqual(address.value as? String, draft)

        address.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        address.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: draft.count))
        let blank = address.value as? String ?? ""
        XCTAssertTrue(blank.isEmpty || blank == address.placeholderValue)
        app.descendants(matching: .any)["secondary-camera-settings-form"].swipeDown()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertEqual(address.value as? String ?? "", blank)

        address.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        address.typeText("synthetic")
        let explanation = app.staticTexts.matching(NSPredicate(format: "label == %@", "Enter the private address, certificate fingerprint, and token supplied by your Pi. Pairing stays in this device’s Keychain. Saving does not start the camera.")).firstMatch
        XCTAssertTrue(explanation.isHittable)
        explanation.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertEqual(address.value as? String, "synthetic")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Resume"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Connecting to side camera…"].exists)
        app.buttons["secondary-camera-menu"].tap()
        app.buttons["Pair side camera"].tap()
        XCTAssertTrue(address.waitForExistence(timeout: 3))
        XCTAssertEqual(address.value as? String ?? "", original)
        app.buttons["Cancel"].tap()
    }

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

import XCTest

final class CoachFlowTests: XCTestCase {
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
}

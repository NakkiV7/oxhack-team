import XCTest

@MainActor func logWallPushupsForUITest(_ app: XCUIApplication) {
    app.tabBars.buttons["Today"].tap()
    let library=app.buttons["today-library"]
    for _ in 0..<8 where !library.isHittable { app.swipeUp() }
    XCTAssertTrue(library.isHittable)
    library.tap()
    let exercise=app.buttons["library-wallPushup"]
    XCTAssertTrue(exercise.waitForExistence(timeout:4));exercise.tap()
    let manual=app.buttons["Log manually"]
    for _ in 0..<8 where !manual.isHittable { app.swipeUp() }
    XCTAssertTrue(manual.isHittable);manual.tap()
    XCTAssertTrue(app.buttons["Save workout"].waitForExistence(timeout:4))
    app.buttons["Save workout"].tap()
    XCTAssertTrue(app.staticTexts["Workout saved"].waitForExistence(timeout:4))
    app.buttons["Done"].tap()
    app.navigationBars.buttons.element(boundBy:0).tap()
    app.navigationBars.buttons["Done"].tap()
}

@MainActor func revealUITestText(_ title:String,in app:XCUIApplication) -> XCUIElement {
    let element=app.staticTexts[title].firstMatch
    for _ in 0..<10 where !element.isHittable { app.swipeUp() }
    return element
}

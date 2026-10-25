import XCTest
import UIKit

final class ReportFlowTests: XCTestCase {
    @MainActor func testEmptyWeekShowsActualZeroTotalsAndNoInventedSignals() {
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = UUID().uuidString
        app.launch()
        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.staticTexts["This week"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Your first session starts here."].exists)
        XCTAssertFalse(app.staticTexts["Average heart rate"].exists)
    }

    @MainActor func testSavedSessionOpensReportWithActualExerciseAndSignalAbsence() {
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = UUID().uuidString
        app.launch()
        app.buttons["Start session"].tap()
        app.buttons["End set"].tap()
        app.buttons["Finish session"].tap()
        XCTAssertTrue(app.staticTexts["Session saved"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.staticTexts["This week"].waitForExistence(timeout: 5))
        let report = app.buttons["session-report"].firstMatch
        XCTAssertTrue(report.waitForExistence(timeout: 5))
        report.tap()
        XCTAssertTrue(app.staticTexts["Session report"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Lower body"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Camera"].firstMatch.exists)
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["No Watch heart-rate readings recorded."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No Watch active-energy readings recorded."].exists)
        XCTAssertFalse(app.staticTexts["0 kcal"].exists)
        XCTAssertTrue(app.staticTexts["Rep tempo was not recorded."].exists)
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["No Watch acceleration readings recorded."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No Watch rotation readings recorded."].exists)
        XCTAssertTrue(app.staticTexts["Apple Watch · Core Motion"].firstMatch.exists)
    }

    // Seed only these dedicated simulator namespaces using docs/watch-native-report-checks.md.
    @MainActor func testPopulatedWatchReportKeepsSourcesAndRecordingTotalsReadable() {
        verifyPopulatedReport(largeText: false)
    }

    @MainActor func testPopulatedWatchReportAtAccessibilityTextSize() {
        verifyPopulatedReport(largeText: true)
    }

    @MainActor private func verifyPopulatedReport(largeText: Bool) {
        let app = openSeededReport(namespace: "E2733504-C099-43BC-BF15-A59F7FB6EE62", largeText: largeText)
        reveal(app.staticTexts["Watch heart rate"], in: app)
        XCTAssertTrue(app.staticTexts["Apple Watch · HealthKit"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["121 bpm"].exists, "The corrected highest sample is used, not the old value or the foreign session")
        attachReport(app, name: "Synthetic HR · \(largeText ? "accessibility" : "default")")
        reveal(app.staticTexts["Watch active energy"], in: app)
        let recordings = app.descendants(matching: .any).matching(identifier: "watch-active-energy-reading")
        XCTAssertEqual(recordings.count, 2, "Separate recording estimates must not become an added total")
        XCTAssertTrue(recordings.element(boundBy: 0).label.contains("Recording 1"))
        XCTAssertTrue(recordings.element(boundBy: 1).label.contains("Recording 2"))
        attachReport(app, name: "Synthetic energy recordings · \(largeText ? "accessibility" : "default")")
        reveal(app.staticTexts["Wrist acceleration magnitude"], in: app)
        XCTAssertTrue(app.staticTexts["Apple Watch · Core Motion"].firstMatch.exists)
        attachReport(app, name: "Synthetic acceleration · \(largeText ? "accessibility" : "default")")
        reveal(app.staticTexts["Wrist rotation magnitude"], in: app)
        XCTAssertFalse(app.staticTexts["No Watch rotation readings recorded."].exists)
        attachReport(app, name: "Synthetic rotation · \(largeText ? "accessibility" : "default")")
    }

    @MainActor func testPartialWatchReportLeavesStaleHeartAndRotationUnavailable() {
        let app = openSeededReport(namespace: "0FE03F3B-0411-4F0B-AEE9-E066958ABF4F")
        reveal(app.staticTexts["No Watch heart-rate readings recorded."], in: app)
        XCTAssertTrue(app.staticTexts["No Watch active-energy readings recorded."].exists)
        reveal(app.staticTexts["Wrist acceleration magnitude"], in: app)
        XCTAssertFalse(app.staticTexts["No Watch acceleration readings recorded."].exists)
        reveal(app.staticTexts["No Watch rotation readings recorded."], in: app)
        attachReport(app, name: "Synthetic partial sensors · stale HR and rotation stay unavailable")
    }

    @MainActor private func openSeededReport(namespace: String, largeText: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["SPOTTR_DATA_NAMESPACE"] = namespace
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue]
        }
        app.launch()
        app.tabBars.buttons["Progress"].tap()
        let report = app.buttons["session-report"].firstMatch
        XCTAssertTrue(report.waitForExistence(timeout: 5), "Seed the synthetic report namespace before this selector; see docs/watch-native-report-checks.md")
        report.tap()
        XCTAssertTrue(app.staticTexts["Session report"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 {
            if element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable, "The report section must remain reachable by scrolling")
    }

    @MainActor private func attachReport(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

}

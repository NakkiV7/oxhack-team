import XCTest
import SwiftUI
import UIKit
@testable import Spottr

@MainActor final class CoachPolishExternalTests: XCTestCase {
    func testPublicCoachAdjustmentAndActualInsightsTab() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let scope = AccountDataScope(accountID: UUID(), profileID: UUID(), root: root)
        let profile = try LocalProfile(name: "Alex", bodyMeasurements: .init(heightCM: 170, weightKG: 70), onboardingRevision: TrainingSetup.revision,
            programmePreferences: .init(goals: [.strength], weekdays: Set(1...7), availableSupport: Set(PathSurvey.equipmentChoices), startingPoint: .startingOut,
                ageContext: .init(ageYears: 30, guardianManaged: false), comfortAnswers: Dictionary(uniqueKeysWithValues: ExerciseFamily.allCases.map { ($0, TrainingSetup.Comfort.unsure) })))
        try NativeProfileStore(url: scope.file("profile.json")).save(profile)
        let w = try AccountWorkspace(scope: scope)
        let week = try w.programme.prepare(profile: profile, history: [])
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try XCTUnwrap(scene.windows.first { $0.isKeyWindow })
        let original = window.rootViewController, hidden = window.isHidden, level = window.windowLevel
        defer { w.suspend(); window.rootViewController = original; window.isHidden = hidden; window.windowLevel = level; window.makeKey() }
        window.rootViewController = UIHostingController(rootView: SpottrRoot(store: w.training, profileStore: w.profile).id(ObjectIdentifier(w)))
        window.makeKeyAndVisible()
        print("TASK9_PUBLIC_UI_READY")
        for _ in 0..<1200 {
            if w.programme.current?.revision != week.revision { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let changed = try XCTUnwrap(w.programme.current)
        XCTAssertGreaterThan(changed.revision, week.revision)
        XCTAssertLessThan(changed.days[0].plan!.items[0].target, week.days[0].plan!.items[0].target)
        capture(window, "actual-coach-adjustment")
        print("TASK9_PUBLIC_PLAN_CHANGED")
        for _ in 0..<900 {
            if labels(window).contains("Your progress") { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(labels(window).contains("Your progress"), labels(window).joined(separator: " | "))
        XCTAssertTrue(w.training.history.isEmpty)
        capture(window, "actual-insights-tab")
        print("TASK9_PUBLIC_UI_DONE")
    }
    private func labels(_ root: NSObject) -> [String] {
        var result: [String] = [], seen = Set<ObjectIdentifier>()
        func visit(_ object: NSObject) {
            guard seen.insert(ObjectIdentifier(object)).inserted else { return }
            if let label = object.accessibilityLabel { result.append(label) }
            (object as? UIView)?.subviews.forEach(visit)
            object.accessibilityElements?.compactMap { $0 as? NSObject }.forEach(visit)
            let count = object.accessibilityElementCount()
            if count > 0 && count < 500 { for index in 0..<count { if let child = object.accessibilityElement(at: index) as? NSObject { visit(child) } } }
        }
        visit(root); return result
    }
    private func capture(_ window: UIWindow, _ name: String) {
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

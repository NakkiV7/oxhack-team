import XCTest
import SwiftUI
import UIKit
@testable import Spottr

@MainActor final class QuestExternalAcceptanceTests: XCTestCase {
    private var window: UIWindow?
    private var controller: UIViewController?
    private var hidden = false
    private var level = UIWindow.Level.normal
    override func tearDown() {
        window?.rootViewController = controller; window?.isHidden = hidden; window?.windowLevel = level; window?.makeKey()
        window = nil; controller = nil; super.tearDown()
    }
    func testExternalChapterJumpRecoveryClaimAndRewardSettings() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let scope = AccountDataScope(accountID: UUID(), profileID: UUID(), root: root)
        let profile = try LocalProfile(name: "Alex", bodyMeasurements: .init(heightCM: 170, weightKG: 70), onboardingRevision: TrainingSetup.revision,
            programmePreferences: .init(goals: [.balance], weekdays: Set(1...7), availableSupport: ["Stable chair", "Wall"], startingPoint: .startingOut,
                ageContext: .init(ageYears: 30, guardianManaged: false), comfortAnswers: Dictionary(uniqueKeysWithValues: ExerciseFamily.allCases.map { ($0, TrainingSetup.Comfort.unsure) })))
        try NativeProfileStore(url: scope.file("profile.json")).save(profile)
        let workspace = try AccountWorkspace(scope: scope)
        defer { workspace.suspend() }
        _ = try workspace.programme.prepare(profile: profile, history: [])
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try XCTUnwrap(scene.windows.first { $0.isKeyWindow })
        self.window = window; controller = window.rootViewController; hidden = window.isHidden; level = window.windowLevel
        window.rootViewController = UIHostingController(rootView: SpottrRoot(store: workspace.training, profileStore: workspace.profile, healthStore: workspace.health).id(ObjectIdentifier(workspace)))
        window.makeKeyAndVisible()
        print("QUEST_EXTERNAL_READY_OPEN_SKILLS")
        try await wait { self.labels(window).contains { $0.contains("One journey, every movement") } }
        capture(window, "external-skills-start")
        print("QUEST_EXTERNAL_REVEAL_CHALLENGE")
        try await wait { self.labels(window).contains { $0.contains("Diamond push-ups") } }
        capture(window, "external-challenge-revealed")
        print("QUEST_EXTERNAL_TAP_TOOLBAR_JUMP")
        try await wait { self.labels(window).contains { $0.contains("Seated marching") } && !self.labels(window).contains { $0.contains("Diamond push-ups") } }
        capture(window, "external-jumped-current")
        print("QUEST_EXTERNAL_TODAY_RECOVERY_CHECKIN_CLAIM")
        try await wait { workspace.training.quests?.archive.claims.count == 1 }
        let archive = try XCTUnwrap(workspace.training.quests?.archive)
        XCTAssertEqual(archive.checkIns.count, 1)
        XCTAssertEqual(archive.claims.count, 1)
        XCTAssertEqual(archive.totalXP, 10)
        XCTAssertTrue(archive.claims[0].sessionIDs.isEmpty)
        XCTAssertTrue(workspace.training.history.isEmpty)
        XCTAssertTrue(workspace.training.rewards.ledger.events.isEmpty)
        capture(window, "external-recovery-single-claim")
        print("QUEST_EXTERNAL_MANAGE_REWARDS_SAVE_WINDOW")
        try await wait { !workspace.training.rewards.ledger.windowChanges.isEmpty }
        XCTAssertEqual(workspace.training.quests?.archive.claims.count, 1)
        XCTAssertTrue(workspace.training.history.isEmpty)
        capture(window, "external-reward-window-saved")
        print("QUEST_EXTERNAL_CLOSE_REWARDS")
        try await wait { !self.labels(window).contains("Save for tomorrow") }
        capture(window, "external-rewards-returned")
        try await Task.sleep(for: .seconds(2))
    }
    func testExternalChapterRevealHasNoBlankViewport() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let scope = AccountDataScope(accountID: UUID(), profileID: UUID(), root: root)
        let profile = try LocalProfile(name: "Alex", bodyMeasurements: .init(heightCM: 170, weightKG: 70), onboardingRevision: TrainingSetup.revision,
            programmePreferences: .init(goals: [.balance], weekdays: Set(1...7), availableSupport: ["Stable chair", "Wall"], startingPoint: .startingOut,
                ageContext: .init(ageYears: 30, guardianManaged: false), comfortAnswers: Dictionary(uniqueKeysWithValues: ExerciseFamily.allCases.map { ($0, TrainingSetup.Comfort.unsure) })))
        try NativeProfileStore(url: scope.file("profile.json")).save(profile)
        let workspace = try AccountWorkspace(scope: scope)
        defer { workspace.suspend() }
        _ = try workspace.programme.prepare(profile: profile, history: [])
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try XCTUnwrap(scene.windows.first { $0.isKeyWindow })
        self.window = window; controller = window.rootViewController; hidden = window.isHidden; level = window.windowLevel
        window.rootViewController = UIHostingController(rootView: SpottrRoot(store: workspace.training, profileStore: workspace.profile, healthStore: workspace.health).id(ObjectIdentifier(workspace)))
        window.makeKeyAndVisible()
        print("QUEST_GEOMETRY_OPEN_SKILLS")
        try await wait { self.labels(window).contains("One journey, every movement") }
        try await Task.sleep(for: .seconds(2))
        capture(window, "skills-settled-opaque-tab")
        for _ in 0..<20 {
            if objects(window).contains(where: { $0.accessibilityLabel?.contains("Challenge") == true && $0.accessibilityFrame.midY > window.safeAreaInsets.top + 70 && $0.accessibilityFrame.maxY < window.bounds.height - 100 }) { break }
            if let scroll = scrollViews(window).first(where: { $0.contentSize.height > $0.bounds.height && $0.bounds.width > 200 }) {
                scroll.setContentOffset(.init(x: 0, y: min(scroll.contentSize.height - scroll.bounds.height, scroll.contentOffset.y + 300)), animated: false)
            }
            try await Task.sleep(for: .milliseconds(200)); window.layoutIfNeeded()
        }
        if let header = objects(window).first(where: { $0.accessibilityLabel?.contains("Challenge") == true }),
           let scroll = scrollViews(window).first(where: { $0.contentSize.height > $0.bounds.height && $0.bounds.width > 200 }) {
            let target = scroll.contentOffset.y + header.accessibilityFrame.minY - (window.safeAreaInsets.top + 100)
            scroll.setContentOffset(.init(x: 0, y: target), animated: false)
            try await Task.sleep(for: .milliseconds(500)); window.layoutIfNeeded()
        }
        capture(window, "chapter-header-positioned")
        print("QUEST_GEOMETRY_CLICK_VISIBLE_CHALLENGE")
        try await wait { self.labels(window).contains { $0.contains("Diamond push-ups") } }
        try await Task.sleep(for: .seconds(2)); window.layoutIfNeeded()
        let names = ["One journey", "earned", "Jump to current", "Foundations", "Rhythm", "Control", "Strength", "Flow", "Challenge", "Close-grip push-ups", "Tempo push-ups", "Paused push-ups", "Diamond push-ups", "Assisted single-leg squats"]
        let visible = objects(window).filter { object in
            let frame = object.accessibilityFrame
            return names.contains { object.accessibilityLabel?.contains($0) == true } && object.accessibilityLabel != "Jump to current" && frame.height > 0 && frame.maxY > window.safeAreaInsets.top + 44 && frame.intersects(window.convert(window.bounds, to: nil))
        }
        let top = try XCTUnwrap(visible.map { $0.accessibilityFrame.minY }.min())
        print("QUEST_GEOMETRY_FIRST_CONTENT_TOP", top, "SAFE_TOP", window.safeAreaInsets.top)
        capture(window, "chapter-reveal-settled-geometry")
        XCTAssertLessThan(top, window.safeAreaInsets.top + 44 + 140, "Revealing a chapter must not leave a large empty viewport above the first visible chapter/node")
        for expected in ["Challenge", "Close-grip push-ups"] {
            let frame = try XCTUnwrap(objects(window).first { $0.accessibilityLabel?.contains(expected) == true }?.accessibilityFrame)
            XCTAssertGreaterThanOrEqual(frame.minY, window.safeAreaInsets.top + 44, "Selected chapter heading and first node must remain below the navigation bar")
            XCTAssertLessThan(frame.maxY, window.bounds.height - window.safeAreaInsets.bottom - 60, "Selected chapter heading and first node must be genuinely visible above the tab bar")
        }
        XCTAssertTrue(workspace.training.history.isEmpty)
        try await Task.sleep(for: .seconds(3))
    }
    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<900 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTFail("Timed out waiting for the external public UI action")
        throw NSError(domain: "QuestExternalWait", code: 1)
    }
    private func scrollViews(_ view: UIView) -> [UIScrollView] { ([view as? UIScrollView].compactMap { $0 }) + view.subviews.flatMap(scrollViews) }
    private func labels(_ root: NSObject) -> [String] { objects(root).compactMap(\.accessibilityLabel) }
    private func objects(_ root: NSObject) -> [NSObject] {
        var result: [NSObject] = [], seen = Set<ObjectIdentifier>()
        func visit(_ value: NSObject) {
            guard seen.insert(ObjectIdentifier(value)).inserted else { return }
            result.append(value)
            (value as? UIView)?.subviews.forEach(visit)
            value.accessibilityElements?.compactMap { $0 as? NSObject }.forEach(visit)
            let count = value.accessibilityElementCount()
            if count > 0 && count < 500 { for index in 0..<count { if let child = value.accessibilityElement(at: index) as? NSObject { visit(child) } } }
        }
        visit(root); return result
    }
    private func capture(_ window: UIWindow, _ name: String) {
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

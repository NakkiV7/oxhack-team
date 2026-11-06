import XCTest
import SwiftUI
import UIKit
@testable import Spottr

@MainActor final class QuestRenderedTests: XCTestCase {
    private var window: UIWindow?
    private var controller: UIViewController?
    private var hidden = false
    private var level = UIWindow.Level.normal
    override func tearDown() {
        window?.rootViewController = controller; window?.isHidden = hidden; window?.windowLevel = level; window?.makeKey()
        window = nil; controller = nil; super.tearDown()
    }
    func testCombinedNearbyMapShowsChapterAndJumpWithNoVisitCredit() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = try AccountWorkspace(scope: .init(accountID: UUID(), profileID: UUID(), root: root))
        let profile = try LocalProfile(programmePreferences: .init(goals: [.balance], weekdays: [1, 3, 5], ageContext: .init(ageYears: 30, guardianManaged: false)))
        try workspace.profile.save(profile)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try XCTUnwrap(scene.windows.first { $0.isKeyWindow })
        self.window = window; controller = window.rootViewController; hidden = window.isHidden; level = window.windowLevel
        window.rootViewController = UIHostingController(rootView: PathSkillsView(store: workspace.training, profile: profile))
        window.makeKeyAndVisible()
        for _ in 0..<50 {
            window.layoutIfNeeded()
            if labels(window).contains("Jump to current") { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let text = labels(window)
        XCTAssertTrue(text.contains("One journey, every movement"), text.joined(separator: " | "))
        XCTAssertTrue(text.contains("Jump to current"))
        XCTAssertTrue(text.contains { $0.contains("Foundations") })
        XCTAssertFalse(text.contains("Training path"))
        XCTAssertTrue(workspace.training.history.isEmpty)
        XCTAssertTrue(workspace.training.rewards.ledger.events.isEmpty)
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = "combined-skills-nearby"; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testLargeTextScrollAndJuniorFamilyQuestsKeepAppropriateRewards() async throws { try await renderAge(30) }
    func testFreshJuniorMapAndRewards() async throws { try await renderAge(8) }
    func testFreshFamilyQuestsAndRewards() async throws { try await renderAge(4) }
    private func renderAge(_ selectedAge: Int) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try XCTUnwrap(scene.windows.first { $0.isKeyWindow })
        self.window = window; controller = window.rootViewController; hidden = window.isHidden; level = window.windowLevel
        print("QUEST_ACTUAL_REDUCE_MOTION", UIAccessibility.isReduceMotionEnabled)
        for age in [selectedAge] {
            let scope = AccountDataScope(accountID: UUID(), profileID: UUID(), root: root)
            let profileStore = NativeProfileStore(url: scope.file("profile.json"))
            let profile = try LocalProfile(programmePreferences: .init(goals: [.balance], weekdays: Set(1...7), ageContext: .init(ageYears: age, guardianManaged: age < 18)))
            try profileStore.save(profile)
            let workspace = try AccountWorkspace(scope: scope)
            _ = try workspace.programme.prepare(profile: profile, history: [])
            if age >= 5 {
                window.rootViewController = UIHostingController(rootView: PathSkillsView(store: workspace.training, profile: profile).dynamicTypeSize(age == 30 ? .accessibility2 : .large))
            } else {
                window.rootViewController = UIHostingController(rootView: FamilyMovementView(workspace: workspace, authorization: AuthenticationServicesAccountAuthorization()).dynamicTypeSize(.accessibility2))
            }
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(600)); window.layoutIfNeeded()
            capture(window, "quest-age-\(age)-top")
            let target = age >= 18 ? "Manage rewards & reminders" : "Review check-ins"
            for index in 0..<24 {
                if visible(window, label: target) { break }
                if let scroll = scrollViews(window).first(where: { $0.contentSize.height > $0.bounds.height && $0.bounds.width > 200 }) {
                    let maximum = max(0, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
                    scroll.setContentOffset(.init(x: 0, y: min(maximum, scroll.contentOffset.y + scroll.bounds.height * 0.65)), animated: false)
                    print("QUEST_REAL_SCROLL", age, index, scroll.contentOffset.y)
                }
                try await Task.sleep(for: .milliseconds(180)); window.layoutIfNeeded()
                if index == 2 { capture(window, "quest-age-\(age)-scroll") }
            }
            XCTAssertTrue(visible(window, label: target), labels(window).joined(separator: " | "))
            capture(window, "quest-age-\(age)-rewards")
            if age < 18 {
                XCTAssertFalse(labels(window).contains("Manage rewards & reminders"))
                XCTAssertFalse(labels(window).contains { $0.localizedCaseInsensitiveContains("streak") || $0.localizedCaseInsensitiveContains("bonus window") })
            }
            XCTAssertTrue(workspace.training.history.isEmpty)
            XCTAssertTrue(workspace.training.quests?.archive.claims.isEmpty == true)
            workspace.suspend()
        }
    }
    func testIdentityKeyedScrolledSkillsReplacementRetiresAdultAndShowsJunior() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        func workspace(_ age: Int) throws -> AccountWorkspace {
            let scope = AccountDataScope(accountID: UUID(), profileID: UUID(), root: root)
            try NativeProfileStore(url: scope.file("profile.json")).save(LocalProfile(programmePreferences: .init(goals: [.balance], weekdays: Set(1...7), ageContext: .init(ageYears: age, guardianManaged: age < 18))))
            let result = try AccountWorkspace(scope: scope)
            _ = try result.programme.prepare(profile: XCTUnwrap(result.profile.profile), history: [])
            return result
        }
        let adult = try workspace(30), junior = try workspace(8)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try XCTUnwrap(scene.windows.first { $0.isKeyWindow })
        self.window = window; controller = window.rootViewController; hidden = window.isHidden; level = window.windowLevel
        let host = UIHostingController(rootView: QuestIdentitySurface(workspace: adult))
        window.rootViewController = host; window.makeKeyAndVisible()
        try await Task.sleep(for: .milliseconds(500))
        for _ in 0..<12 {
            if labels(window).contains("Manage rewards & reminders") { break }
            if let scroll = scrollViews(window).first(where: { $0.contentSize.height > $0.bounds.height && $0.bounds.width > 200 }) {
                scroll.setContentOffset(.init(x: 0, y: min(scroll.contentSize.height - scroll.bounds.height, scroll.contentOffset.y + 500)), animated: false)
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        capture(window, "identity-adult-scrolled")
        print("QUEST_IDENTITY_WILL_REPLACE")
        adult.suspend()
        host.rootView = QuestIdentitySurface(workspace: junior)
        try await Task.sleep(for: .milliseconds(700)); window.layoutIfNeeded()
        print("QUEST_IDENTITY_DID_REPLACE")
        for _ in 0..<50 {
            window.layoutIfNeeded()
            if labels(window).contains("One journey, every movement") { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(labels(window).contains("One journey, every movement"), labels(window).joined(separator: " | "))
        XCTAssertFalse(labels(window).contains("Manage rewards & reminders"))
        XCTAssertTrue(adult.training.quests?.choices(history: []).isEmpty == true)
        capture(window, "identity-junior-replaced")
        junior.suspend()
    }
    private func scrollViews(_ view: UIView) -> [UIScrollView] { ([view as? UIScrollView].compactMap { $0 }) + view.subviews.flatMap(scrollViews) }
    private func capture(_ window: UIWindow, _ name: String) {
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func visible(_ window: UIWindow, label: String) -> Bool {
        objects(window).contains { $0.accessibilityLabel == label && $0.accessibilityFrame.height > 0 && $0.accessibilityFrame.intersects(window.convert(window.bounds, to: nil)) }
    }
    private func labels(_ root: NSObject) -> [String] { objects(root).compactMap(\.accessibilityLabel) }
    private func objects(_ root: NSObject) -> [NSObject] {
        var values: [NSObject] = [], seen = Set<ObjectIdentifier>()
        func visit(_ value: NSObject) {
            guard seen.insert(ObjectIdentifier(value)).inserted else { return }
            values.append(value)
            (value as? UIView)?.subviews.forEach(visit)
            value.accessibilityElements?.compactMap { $0 as? NSObject }.forEach(visit)
            let count = value.accessibilityElementCount()
            if count > 0 && count < 500 { for index in 0..<count { if let child = value.accessibilityElement(at: index) as? NSObject { visit(child) } } }
        }
        visit(root); return values
    }
}

private struct QuestIdentitySurface: View {
    let workspace: AccountWorkspace
    var body: some View {
        PathSkillsView(store: workspace.training, profile: workspace.profile.profile)
            .id(ObjectIdentifier(workspace))
    }
}

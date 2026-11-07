import XCTest
import SwiftUI
import UIKit
import Vision
@testable import Spottr

@MainActor final class ServiceIntegrationRenderedTests: XCTestCase {
    func testInitialAdultFactoryPresentsTwoOffPrivacyChoicesInFirstOfSixStages() async throws {
        let text = try await initialSetupText(age: 30, dynamicType: .large)
        XCTAssertTrue(text.contains("account and privacy"))
        XCTAssertTrue(text.contains("share feature usage"))
        XCTAssertTrue(text.contains("share weekly workout statistics"))
        XCTAssertTrue(text.contains("privacy policy"))
        XCTAssertTrue(text.replacingOccurrences(of: " ", with: "").contains("1of6"))
    }
    func testInitialJuniorFactoryExplainsStatisticsDisabledWithLargeType() async throws {
        let text = try await initialSetupText(age: 12, dynamicType: .accessibility1)
        XCTAssertTrue(text.contains("account and privacy"))
        XCTAssertTrue(text.contains("private")); XCTAssertTrue(text.contains("not collected"))
        XCTAssertTrue(text.contains("privacy policy"))
        XCTAssertFalse(text.contains("share weekly workout statistics"))
    }
    func testExternalInitialPrivacyContinuesOffAndRequiresAdultMeasurements() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let scope = AccountDataScope(accountID: UUID(), profileID: UUID(), root: root)
        try NativeProfileStore(url: scope.file("profile.json")).save(LocalProfile(programmePreferences: .init(goals: [.balance], weekdays: [1], ageContext: .init(ageYears: 30, guardianManaged: false))))
        let workspace = try AccountWorkspace(scope: scope)
        defer { workspace.suspend() }
        let analytics = try XCTUnwrap(workspace.training.analytics)
        let setup = AccountRootView.initialSetup(workspace: workspace, authorization: ServiceGuardianAuthorization())
        XCTAssertTrue(setup.previews === workspace.training.voicePreviews); XCTAssertTrue(setup.analytics === analytics)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try XCTUnwrap(scene.windows.first { $0.isKeyWindow })
        let original = window.rootViewController, hidden = window.isHidden, level = window.windowLevel
        defer { window.rootViewController = original; window.windowLevel = level; window.isHidden = hidden; window.makeKey() }
        window.rootViewController = UIHostingController(rootView: setup)
        window.makeKeyAndVisible()
        try await Task.sleep(for: .milliseconds(300)); window.layoutIfNeeded()
        XCTAssertFalse(analytics.ledger.usage); XCTAssertFalse(analytics.ledger.workout)
        print("TASK10_PRIVACY_READY_CONTINUE_OFF")
        let firstDeadline = Date().addingTimeInterval(300)
        var bodyText = ""
        repeat {
            bodyText = try windowText(window)
            if bodyText.contains("your training profile") { break }
            try await Task.sleep(for: .milliseconds(300))
        } while Date() < firstDeadline
        XCTAssertTrue(bodyText.contains("your training profile")); XCTAssertTrue(bodyText.contains("2 of 6"))
        XCTAssertFalse(analytics.ledger.usage); XCTAssertFalse(analytics.ledger.workout)
        guard bodyText.contains("your training profile") else { return }
        let bodyOffsets = scrollOffsets(window)
        print("TASK10_PRIVACY_READY_BODY_CONTINUE_WITHOUT_MEASUREMENTS")
        let validationDeadline = Date().addingTimeInterval(300)
        var validation = ""
        repeat {
            XCTAssertEqual(scrollOffsets(window), bodyOffsets, "Validation must become visible after Continue without scrolling")
            validation = try windowText(window)
            if validation.contains("enter your height and weight to continue") { break }
            try await Task.sleep(for: .milliseconds(300))
        } while Date() < validationDeadline
        XCTAssertTrue(validation.contains("enter your height and weight to continue"), "The actual Continue action must show required measurements")
        XCTAssertTrue(validation.contains("2 of 6")); XCTAssertFalse(validation.contains("goals and rhythm"))
        XCTAssertFalse(analytics.ledger.usage); XCTAssertFalse(analytics.ledger.workout)
        XCTAssertFalse(AccountPolicy.setupComplete(profile: workspace.profile.profile))
        let attachment = XCTAttachment(image: windowImage(window)); attachment.name = "task10-privacy-actual-continue-measurements-required"; attachment.lifetime = .keepAlways; add(attachment)
        print("TASK10_PRIVACY_CONTINUED_OFF_VALIDATION_DELIVERED")
    }
    private func scrollOffsets(_ view: UIView) -> [String: Double] {
        var offsets: [String: Double] = [:]
        if let scroll = view as? UIScrollView { offsets[String(describing: ObjectIdentifier(scroll))] = scroll.contentOffset.y }
        for child in view.subviews { offsets.merge(scrollOffsets(child), uniquingKeysWith: { _, next in next }) }
        return offsets
    }
    private func windowImage(_ window: UIWindow) -> UIImage {
        window.layoutIfNeeded()
        return UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
    }
    private func windowText(_ window: UIWindow) throws -> String {
        let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
        try VNImageRequestHandler(cgImage: XCTUnwrap(windowImage(window).cgImage)).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ").lowercased()
    }
    private func initialSetupText(age: Int, dynamicType: DynamicTypeSize) async throws -> String {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let start = ProcessInfo.processInfo.systemUptime
        let scope = AccountDataScope(accountID: UUID(), profileID: UUID(), root: root)
        try NativeProfileStore(url: scope.file("profile.json")).save(LocalProfile(programmePreferences: .init(goals: [.balance], weekdays: [1], ageContext: .init(ageYears: age, guardianManaged: age < 18))))
        let workspace = try AccountWorkspace(scope: scope)
        defer { workspace.suspend() }
        let analytics = try XCTUnwrap(workspace.training.analytics)
        let setup = AccountRootView.initialSetup(workspace: workspace, authorization: ServiceGuardianAuthorization())
        XCTAssertTrue(setup.previews === workspace.training.voicePreviews)
        XCTAssertTrue(setup.analytics === analytics)
        XCTAssertFalse(analytics.ledger.usage); XCTAssertFalse(analytics.ledger.workout)
        let construction = ProcessInfo.processInfo.systemUptime - start
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try XCTUnwrap(scene.windows.first { $0.isKeyWindow })
        let original = window.rootViewController, hidden = window.isHidden, level = window.windowLevel
        defer { window.rootViewController = original; window.windowLevel = level; window.isHidden = hidden; window.makeKey() }
        window.rootViewController = UIHostingController(rootView: setup.environment(\.dynamicTypeSize, dynamicType))
        window.makeKeyAndVisible()
        try await Task.sleep(for: .milliseconds(200))
        let renderStart = ProcessInfo.processInfo.systemUptime
        window.layoutIfNeeded()
        let capture = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let captureDuration = ProcessInfo.processInfo.systemUptime - renderStart
        let attachment = XCTAttachment(image: capture); attachment.name = "task10-initial-privacy-age-\(age)"; attachment.lifetime = .keepAlways; add(attachment)
        let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
        try VNImageRequestHandler(cgImage: XCTUnwrap(capture.cgImage)).perform([request])
        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ").lowercased().replacingOccurrences(of: "_", with: " ")
        print("TASK10_SETUP_RENDER_AGE_\(age)_CONSTRUCTION_\(construction)_CAPTURE_\(captureDuration)_SETTLE_0.2_REDUCE_MOTION_\(UIAccessibility.isReduceMotionEnabled)_TEXT_\(text)")
        XCTAssertTrue(text.contains("continue"), "The actual setup must render its real continuation control")
        XCTAssertFalse(analytics.ledger.usage); XCTAssertFalse(analytics.ledger.workout)
        return text
    }
    func testPreProfileAccountAccessRequiresApprovalAndRejectsChangedCheckpoint() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let guardian = ServiceGuardianAuthorization()
        let account = NativeAccountStore(client: AccountClient(transport: AccountTestTransport()), credentials: MemoryAccountCredentials(), authorization: guardian)
        let coordinator = AccountWorkspaceCoordinator(account: account, root: root, membershipClient: ServiceMembershipClient())
        let access = coordinator.websiteAccess
        do { try await access.authorize(); XCTFail("A signed-out restore route still requires device-owner approval") } catch {}
        XCTAssertEqual(guardian.calls, 1)
        guardian.allowed = true
        try await access.authorize()
        XCTAssertEqual(guardian.calls, 2)
        guardian.onGuardian = { try? account.setCheckpoint(ageYears: 12, role: .guardian) }
        do { try await access.authorize(); XCTFail("A changed profile checkpoint must reject a delayed approval") } catch {}
        XCTAssertEqual(guardian.calls, 3)
    }
    func testSelectedProfileAccessRejectsPolicyRetirementDuringApproval() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let profile = NativeProfileStore(url: root.appendingPathComponent("profile.json"))
        try profile.save(LocalProfile(programmePreferences: .init(goals: [.balance], weekdays: [1], ageContext: .init(ageYears: 12, guardianManaged: true))))
        let guardian = ServiceGuardianAuthorization(); guardian.allowed = true
        let access = ProfileWebsiteAccess(profile: profile, guardian: guardian)
        guardian.onGuardian = { profile.invalidatePolicy() }
        do { try await access.authorize(); XCTFail("A retired policy cannot authorize a platform action") } catch {}
        XCTAssertEqual(guardian.calls, 1)
    }
    func testExternalJuniorMembershipRestoreRequiresGuardian() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let profile = NativeProfileStore(url: root.appendingPathComponent("profile.json"))
        try profile.save(LocalProfile(programmePreferences: .init(goals: [.balance], weekdays: [1], ageContext: .init(ageYears: 12, guardianManaged: true))))
        let client = ServiceMembershipClient(), guardian = ServiceGuardianAuthorization()
        let membership = MembershipStore(root: root, client: client); membership.setAccount(UUID())
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap {$0 as? UIWindowScene}.first)
        let window = try XCTUnwrap(scene.windows.first {$0.isKeyWindow})
        let original = window.rootViewController, hidden = window.isHidden, level = window.windowLevel
        defer { window.rootViewController = original; window.windowLevel = level; window.isHidden = hidden; window.makeKey() }
        window.rootViewController = UIHostingController(rootView: NavigationStack { MembershipView(store: membership).environment(\.profileWebsiteAccess, ProfileWebsiteAccess(profile: profile, guardian: guardian)) })
        window.makeKeyAndVisible()
        try await Task.sleep(for: .milliseconds(500)); window.layoutIfNeeded()
        print("TASK10_MEMBERSHIP_READY_RESTORE_DENIED")
        let deadline = Date().addingTimeInterval(300)
        while client.restores == 0 && guardian.calls == 0 && Date() < deadline { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertEqual(client.restores, 0, "Junior restore must not open an Apple action without approval")
        XCTAssertEqual(guardian.calls, 1, "Actual button must request guardian authorization")
        print("TASK10_MEMBERSHIP_DELIVERED_PLATFORM_\(client.restores)_GUARDIAN_\(guardian.calls)")
        guard client.restores == 0, guardian.calls == 1 else { return }
        guardian.allowed = true
        print("TASK10_MEMBERSHIP_READY_RESTORE_ALLOWED")
        let allowedDeadline = Date().addingTimeInterval(300)
        while client.restores == 0 && Date() < allowedDeadline { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertEqual(client.restores, 1); XCTAssertEqual(guardian.calls, 2)
        let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) })
        attachment.name = "task10-membership-illustrative-catalogue"; attachment.lifetime = .keepAlways; add(attachment)
        print("TASK10_MEMBERSHIP_COMPLETE")
    }

    private func elements(_ root: NSObject) -> [NSObject] {
        var result: [NSObject] = [], seen = Set<ObjectIdentifier>()
        func visit(_ value: NSObject) {
            guard seen.insert(ObjectIdentifier(value)).inserted else { return }
            result.append(value); (value as? UIView)?.subviews.forEach(visit)
            value.accessibilityElements?.compactMap { $0 as? NSObject }.forEach(visit)
            let count = value.accessibilityElementCount()
            if count > 0 && count < 500 { for index in 0..<count { if let child = value.accessibilityElement(at: index) as? NSObject { visit(child) } } }
        }
        visit(root); return result
    }
}
@MainActor private final class ServiceMembershipClient: MembershipClient {
    var restores = 0
    func products() async throws -> [MembershipOffer] {
        [.init(plan: .monthly, displayName: "Monthly membership", displayPrice: "£10.00", eligibleTrialDays: 14), .init(plan: .lifetime, displayName: "Lifetime membership", displayPrice: "£200.00", eligibleTrialDays: nil)]
    }
    func currentEntitlements() async -> [MembershipVerification] { [] }
    func updates() -> AsyncStream<MembershipVerification> { AsyncStream { $0.finish() } }
    func purchase(_ plan: MembershipPlan, appAccountToken: UUID) async throws -> MembershipPurchaseResult { .cancelled }
    func restore() async throws { restores += 1 }
    func finish(transactionID: UInt64) async {}
}

@MainActor private final class ServiceGuardianAuthorization: NativeAccountAuthorization {
    var calls = 0
    var allowed = false
    var onGuardian: (() -> Void)?
    func guardian() async throws { calls += 1; onGuardian?(); if !allowed { throw AccountFailure.cancelled } }
    func apple(nonce: String) async throws -> AppleIdentityResult { throw AccountFailure.cancelled }
    func register(options: PasskeyCreationOptions) async throws -> RegistrationCredential { throw AccountFailure.cancelled }
    func authenticate(options: PasskeyRequestOptions) async throws -> AssertionCredential { throw AccountFailure.cancelled }
}

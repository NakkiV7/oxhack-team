import XCTest
import SwiftUI
import UIKit
import CryptoKit
import Vision
import AuthenticationServices
@testable import Spottr

@MainActor final class AccountRevisionTests: XCTestCase {
    func testRenderedRootUsesNewHealthCapabilityAcrossAdultJuniorAdultAndSameScopeGraphReplacement() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let adult = try makeWorkspace(root: root, age: 30)
        let junior = try makeWorkspace(root: root, age: 12)
        let adultClient = RevisionHealthClient(available: true)
        let juniorClient = RevisionHealthClient(available: false)
        let replacementClient = RevisionHealthClient(available: false)
        let adultHealth = HealthDataStore(client: adultClient, defaults: try FileHealthPreferences(url: adult.scope.file("ui-health.plist")))
        let juniorHealth = HealthDataStore(client: juniorClient, defaults: try FileHealthPreferences(url: junior.scope.file("ui-health.plist")))
        let replacementHealth = HealthDataStore(client: replacementClient, defaults: try FileHealthPreferences(url: adult.scope.file("ui-health-replacement.plist")))
        let guardian = AccountTestAuthorization(); guardian.succeed = true
        let host = UIHostingController(rootView: RevisionWorkspaceView(workspace: adult, health: adultHealth, guardian: guardian))
        let window = try mount(host)
        defer { window.isHidden = true }
        for (workspace, health, expectedAdultRequests) in [(adult, adultHealth, 1), (junior, juniorHealth, 1), (adult, adultHealth, 2)] {
            host.rootView = RevisionWorkspaceView(workspace: workspace, health: health, guardian: guardian)
            try await settle(window)
            try await waitForOldSheetToClose(window)
            try activate("profile-settings", in: window)
            try await settle(window)
            try await reveal("profile-permissions", in: window)
            try activate("profile-permissions", in: window)
            try await settle(window)
            if AccountPolicy.allowsHealth(profile: workspace.profile.profile) {
                try await reveal("setup-health", in: window)
                try activate("setup-health", in: window)
                try await settle(window)
                try activate("health-connect", in: window)
                try await settle(window)
            } else {
                XCTAssertFalse(elements(window).contains { $0.accessibilityLabel == "Choose Apple Health readings" })
            }
            XCTAssertEqual(adultClient.requests, expectedAdultRequests)
            XCTAssertEqual(juniorClient.requests, 0)
        }
        let replacement = try AccountWorkspace(scope: adult.scope)
        host.rootView = RevisionWorkspaceView(workspace: replacement, health: replacementHealth, guardian: guardian)
        try await settle(window)
        try await waitForOldSheetToClose(window)
        try activate("profile-settings", in: window)
        try await settle(window)
        try await reveal("profile-permissions", in: window)
        try activate("profile-permissions", in: window)
        try await settle(window)
        try await reveal("setup-health", in: window)
        try activate("setup-health", in: window)
        try await settle(window)
        try activate("health-connect", in: window)
        try await settle(window)
        XCTAssertEqual(adultClient.requests, 2)
        XCTAssertEqual(replacementClient.requests, 0)
    }

    func testAdditionalProfileSetupRendersFreshAgeFieldsAfterInitialCheckpoint() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let account = try await trustedAccount()
        try account.setCheckpoint(ageYears: 30, role: .adultSelf)
        let coordinator = AccountWorkspaceCoordinator(account: account, root: root)
        coordinator.accountChanged()
        let host = UIHostingController(rootView: AccountSetupView(account: account, coordinator: coordinator))
        let window = try mount(host)
        defer { window.isHidden = true }
        try await settle(window)
        XCTAssertFalse(textFields(window).contains { $0.placeholder == "Training person’s age" })
        try activate(label: "Create training profile", in: window)
        try await settle(window)
        XCTAssertEqual(coordinator.directory?.profiles.count, 1)
        host.rootView = AccountSetupView(account: account, coordinator: coordinator)
        try await settle(window)
        let age = try XCTUnwrap(textFields(window).first { $0.placeholder == "Training person’s age" })
        XCTAssertEqual(age.text, "")
        age.text = "12"; age.sendActions(for: .editingChanged)
        // Selecting the guardian role and submitting use the actual rendered controls.
        let rolePicker = try XCTUnwrap(elements(window).compactMap { $0 as? UISegmentedControl }.first)
        XCTAssertEqual(rolePicker.selectedSegmentIndex, 0)
        XCTAssertEqual(rolePicker.titleForSegment(at: 2), "Adult guardian")
        rolePicker.selectedSegmentIndex = 2; rolePicker.sendActions(for: .valueChanged)
        try await settle(window)
        let authorization = try XCTUnwrap(account.authorization as? AccountTestAuthorization)
        authorization.succeed = false
        try activate(label: "Create training profile", in: window)
        try await settle(window)
        XCTAssertEqual(coordinator.directory?.profiles.count, 1)
        authorization.succeed = true
        try activate(label: "Create training profile", in: window)
        try await settle(window)
        XCTAssertEqual(coordinator.directory?.profiles.count, 2)
        XCTAssertEqual(coordinator.directory?.profiles.last?.age.ageYears, 12)
        XCTAssertEqual(coordinator.directory?.profiles.last?.age.guardianManaged, true)
        XCTAssertFalse(try XCTUnwrap(coordinator.visibleWorkspace).training.rewards.allowsTimePressureRewards)
        XCTAssertEqual(age.text, "")
        XCTAssertEqual(rolePicker.selectedSegmentIndex, 0)
    }

    func testAdditionalAdultUIRequiresFreshAgeAndRoleAfterJuniorCheckpoint() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let account = try await trustedAccount()
        try account.setCheckpoint(ageYears: 12, role: .guardian)
        let coordinator = AccountWorkspaceCoordinator(account: account, root: root)
        coordinator.accountChanged()
        let host = UIHostingController(rootView: AccountSetupView(account: account, coordinator: coordinator))
        let window = try mount(host)
        defer { window.isHidden = true }
        try await settle(window)
        try activate(label: "Create training profile", in: window)
        try await settle(window)
        XCTAssertEqual(coordinator.directory?.profiles.first?.age.ageYears, 12)
        let age = try XCTUnwrap(textFields(window).first { $0.placeholder == "Training person’s age" })
        XCTAssertEqual(age.text, "")
        age.text = "30"; age.sendActions(for: .editingChanged)
        try activate(label: "Create training profile", in: window)
        try await settle(window)
        XCTAssertEqual(coordinator.directory?.profiles.count, 1, "A fresh role must be explicitly selected")
        let picker = try XCTUnwrap(elements(window).compactMap { $0 as? UISegmentedControl }.first)
        XCTAssertEqual(picker.selectedSegmentIndex, 0)
        picker.selectedSegmentIndex = 1; picker.sendActions(for: .valueChanged)
        try activate(label: "Create training profile", in: window)
        try await settle(window)
        XCTAssertEqual(coordinator.directory?.profiles.last?.age.ageYears, 30)
        XCTAssertEqual(coordinator.directory?.profiles.last?.age.guardianManaged, false)
        XCTAssertTrue(try XCTUnwrap(coordinator.visibleWorkspace).training.rewards.allowsTimePressureRewards)
    }

    func testSuspendingManualHoldFreezesRetainedAndExportedQuantityBeforeArchiving() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let scope = AccountDataScope(accountID: UUID(), profileID: UUID(), root: root)
        var clock = 100.0
        let store = TrainingStore(historyURL: scope.file("history.json"), accountScope: scope, clock: { clock })
        store.beginAuthorizedPlan(try CoachSavedPlan.catalogue(exerciseID: "wallSit", sets: 1, target: 30, restSeconds: 30, availableSupport: ["Wall"]), availableSupport: ["Wall"])
        store.beginConfiguredSet(); clock = 107
        store.setAccountActive(false)
        try store.preservePendingWorkout()
        XCTAssertEqual(store.configured?.phase, .paused)
        XCTAssertEqual(store.configured?.measuredSeconds(at: clock), 7)
        clock = 427
        XCTAssertEqual(store.configured?.measuredSeconds(at: clock), 7)
        try store.preservePendingWorkout()
        let pending = try JSONDecoder().decode(PendingPhoneWorkout.self, from: Data(contentsOf: scope.file("pending-phone-workout.json")))
        XCTAssertEqual(pending.measuredSeconds, 7)
        XCTAssertTrue(store.history.isEmpty)
    }

    func testEveryPreservedUnfinishedSnapshotIsAvailableAfterAccountDeletionWithoutCompletedHistory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let scope = AccountDataScope(accountID: UUID(), profileID: UUID(), root: root)
        let first = TrainingStore(historyURL: scope.file("history.json"), accountScope: scope)
        first.beginAuthorizedSession(); first.switchToManualReps(); first.setManualReps(4); first.pause(); try first.preservePendingWorkout()
        let second = TrainingStore(historyURL: scope.file("history.json"), accountScope: scope)
        second.beginAuthorizedSession(); second.switchToManualReps(); second.setManualReps(9); second.pause(); try second.preservePendingWorkout()
        XCTAssertNotEqual(first.session.id, second.session.id)
        let snapshots = try scope.unfinishedSnapshots()
        XCTAssertEqual(Set(snapshots.map(\.snapshot.record.id)), [first.session.id, second.session.id])
        let exported = try scope.exportLocalData()
        defer { try? FileManager.default.removeItem(at: exported.deletingLastPathComponent()) }
        let data = try JSONDecoder().decode(AccountLocalExport.self, from: Data(contentsOf: exported))
        XCTAssertEqual(Set(data.unfinishedWorkouts.map(\.record.id)), [first.session.id, second.session.id])
        XCTAssertTrue(data.history.isEmpty)
        XCTAssertNil(data.rewards)
        let host = UIHostingController(rootView: NavigationStack { LegacyAccountRecordsView(root: scope.folder) })
        let window = try mount(host)
        defer { window.isHidden = true }
        try await settle(window)
        let labels = elements(window).compactMap(\.accessibilityLabel)
        XCTAssertTrue(labels.contains("Current unfinished workout"))
        XCTAssertTrue(labels.contains("Archived unfinished workout"))
        try activate(label: "Archived unfinished workout", in: window)
        try await settle(window)
        XCTAssertTrue(elements(window).contains { $0.accessibilityLabel?.contains("Current set recorded reps") == true })
        XCTAssertEqual(Set(data.unfinishedWorkouts.compactMap(\.actualReps)), [4, 9])
        let corrupt = scope.file("pending-" + UUID().uuidString + ".json")
        let original = Data("preserve corrupt unfinished snapshot".utf8)
        try ProtectedLocalStorage.write(original, to: corrupt)
        XCTAssertThrowsError(try scope.exportLocalData())
        XCTAssertEqual(try Data(contentsOf: corrupt), original)
    }

    private func makeWorkspace(root: URL, age: Int) throws -> AccountWorkspace {
        let directory = try AccountProfileDirectory(accountID: UUID(), root: root)
        let profile = try directory.add(age: TrainingAgeContext(ageYears: age, guardianManaged: age < 18), name: "Test profile")
        let workspace = try AccountWorkspace(scope: directory.scope(profile.id))
        try workspace.profile.save(LocalProfile(bodyMeasurements: age >= 18 ? .init(heightCM: 170, weightKG: 70) : nil,
            onboardingRevision: TrainingSetup.revision, programmePreferences: .init(goals: [.balance], weekdays: [1], startingPoint: .startingOut,
                ageContext: profile.age, comfortAnswers: Dictionary(uniqueKeysWithValues: ExerciseFamily.allCases.map { ($0, TrainingSetup.Comfort.unsure) }))))
        return workspace
    }
    private func trustedAccount() async throws -> NativeAccountStore {
        let id = UUID(); let vault = MemoryAccountCredentials()
        try vault.save(StoredAccountCredential(session: NativeAccountSession(authenticated: true, accountID: id, appAccountToken: id, deviceID: UUID(), accessToken: "access", refreshToken: "refresh", accessExpiresAt: .now.addingTimeInterval(900), refreshExpiresAt: .now.addingTimeInterval(86400)), privateKey: P256.Signing.PrivateKey().rawRepresentation))
        let wire = AccountTestTransport(); wire.failure = URLError(.notConnectedToInternet)
        let authorization = AccountTestAuthorization(); authorization.succeed = true
        let account = NativeAccountStore(client: AccountClient(transport: wire), credentials: vault, authorization: authorization)
        await account.restore(); return account
    }
    private func mount(_ host: UIViewController) throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = scene.coordinateSpace.bounds
        window.rootViewController = host; window.makeKeyAndVisible(); return window
    }
    private func settle(_ window: UIWindow) async throws {
        window.setNeedsLayout(); window.layoutIfNeeded(); try await Task.sleep(for: .milliseconds(250))
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { _ in XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)) }
        XCTAssertGreaterThan(try XCTUnwrap(image.pngData()).count, 1000)
    }
    private func scrollToBottom(_ window: UIWindow) async throws {
        for scroll in elements(window).compactMap({ $0 as? UIScrollView }) where scroll.contentSize.height > scroll.bounds.height {
            scroll.setContentOffset(CGPoint(x: 0, y: max(0, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)), animated: false)
        }
        try await settle(window)
    }
    private func reveal(_ identifier: String, in window: UIWindow) async throws {
        for _ in 0..<8 {
            let surface = window.rootViewController?.presentedViewController?.view ?? window
            if elements(surface).contains(where: { ($0 as? any UIAccessibilityIdentification)?.accessibilityIdentifier == identifier }) { return }
            for scroll in elements(surface).compactMap({ $0 as? UIScrollView }) where scroll.isScrollEnabled && scroll.contentSize.height > scroll.bounds.height {
                let bottom = max(0, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
                scroll.setContentOffset(CGPoint(x: 0, y: min(bottom, scroll.contentOffset.y + scroll.bounds.height * 0.6)), animated: false)
            }
            try await settle(window)
        }
    }
    private func waitForOldSheetToClose(_ window: UIWindow) async throws {
        for _ in 0..<20 where window.rootViewController?.presentedViewController != nil {
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertNil(window.rootViewController?.presentedViewController, "Policy replacement must dismiss the old profile sheet before another action")
    }
    private func elements(_ root: NSObject) -> [NSObject] {
        var result: [NSObject] = []; var seen = Set<ObjectIdentifier>()
        func visit(_ object: NSObject) {
            guard seen.insert(ObjectIdentifier(object)).inserted else { return }
            result.append(object)
            if let view = object as? UIView { view.subviews.forEach(visit) }
            if let array = object.accessibilityElements { array.compactMap { $0 as? NSObject }.forEach(visit) }
            let count = object.accessibilityElementCount()
            if count > 0 && count < 500 { for index in 0..<count { if let child = object.accessibilityElement(at: index) as? NSObject { visit(child) } } }
        }
        visit(root); return result
    }
    private func textFields(_ root: UIView) -> [UITextField] { elements(root).compactMap { $0 as? UITextField } }
    private func activate(_ id: String, in window: UIWindow) throws {
        let labels = ["profile-settings": "Profile and settings", "profile-permissions": "Permissions and connection", "setup-health": "Choose Apple Health readings", "health-connect": "Choose Health data"]
        let element = try XCTUnwrap(elements(window).first {
            $0.accessibilityTraits.contains(.button) && (($0 as? any UIAccessibilityIdentification)?.accessibilityIdentifier == id || $0.accessibilityLabel == labels[id])
        }, "Missing rendered accessibility button \(id). Rendered elements: \(elements(window).compactMap { $0.accessibilityLabel }.prefix(70))")
        if let control = element as? UIControl { control.sendActions(for: .touchUpInside) }
        else { XCTAssertTrue(element.accessibilityActivate(), "Rendered action did not activate: \(id)") }
    }
    private func activate(label: String, in window: UIWindow) throws {
        let element = try XCTUnwrap(elements(window).first { ($0.accessibilityLabel == label || $0.accessibilityValue == label) && $0.accessibilityTraits.contains(.button) }, "Missing rendered button \(label)")
        XCTAssertTrue(element.accessibilityActivate(), "Rendered button did not activate: \(label)")
    }

}

private struct RevisionWorkspaceView: View {
    let workspace: AccountWorkspace
    let health: HealthDataStore
    let guardian: any NativeAccountAuthorization
    var body: some View {
        // AccountRootView uses this outer workspace identity, including for same-UUID policy replacement.
        SpottrRoot(store: workspace.training, profileStore: workspace.profile, healthStore: health, guardianAuthorization: guardian)
            .id(ObjectIdentifier(workspace))
    }
}

@MainActor private final class RevisionHealthClient: HealthReadingClient {
    let isAvailable: Bool
    var requests = 0
    init(available: Bool) { isAvailable = available }
    func requestReadAuthorization() async throws { requests += 1 }
    func read(asOf: Date, dayStart: Date, dayEnd: Date) async throws -> [HealthObservation] { [] }
}

@MainActor final class AccountRetryRenderedTests: XCTestCase {
    func testWelcomeOffersNativeAppleEmailPasskeyRecoveryAndDirectMembershipWithoutInputs() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let wire = StagedAccountTransport()
        let account = NativeAccountStore(client: AccountClient(transport: wire), credentials: MemoryAccountCredentials(), authorization: RetryAccountAuthorization())
        let coordinator = AccountWorkspaceCoordinator(account: account, root: root)
        let window = try mount(AccountSetupView(account: account, coordinator: coordinator)); defer { restoreWindow() }
        try await settle(window)
        XCTAssertTrue(fields(window).isEmpty, "Welcome must defer both age and email inputs")
        XCTAssertNotNil(elements(window).first { $0 is ASAuthorizationAppleIDButton })
        let text = try renderedText(window, name: "Account welcome ordinary size")
        for choice in ["moveatyourownpace", "continuewithemail", "signinwithpasskey", "recoveraccount", "membershipapplepurchases"] {
            XCTAssertTrue(text.contains(choice), "Missing visible welcome choice \(choice)")
        }
        XCTAssertFalse(text.contains("trainingpersonsage"))
        XCTAssertTrue(wire.requests.isEmpty)
        // The real XCUI regression verifies this visible route's identifier, tap and destination.
    }

    func testActiveMFAOwnsTheScreenAtAccessibilitySize() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let wire = StagedAccountTransport()
        let account = NativeAccountStore(client: AccountClient(transport: wire), credentials: MemoryAccountCredentials(), authorization: RetryAccountAuthorization())
        await account.login()
        XCTAssertEqual(account.step, .secondFactor)
        let window = try mount(AccountSetupView(account: account, coordinator: AccountWorkspaceCoordinator(account: account, root: root)).environment(\.dynamicTypeSize, .accessibility3)); defer { restoreWindow() }
        try await settle(window)
        XCTAssertFalse(try renderedText(window, name: "Active MFA replaces welcome").contains("moveatyourownpace"))
        try await revealField("Authenticator code", in: window)
        XCTAssertNotNil(fields(window).first { $0.placeholder == "Authenticator code" })
        _ = try renderedText(window, name: "Account active MFA accessibility size")
        XCTAssertFalse(account.trusted)
    }

    func testAsyncVerificationErrorIsVisibleInReducedViewportAtAccessibilitySize() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let wire = AccountTestTransport()
        wire.replies = [Data(#"{"flowToken":"visible-email-task","expiresAt":"2030-01-01T00:00:00Z","accepted":true}"#.utf8)]
        let account = NativeAccountStore(client: AccountClient(transport: wire), credentials: MemoryAccountCredentials(), authorization: RetryAccountAuthorization())
        try account.setCheckpoint(ageYears: 30, role: .adultSelf)
        await account.startEmail(email: "owner@example.test", purpose: .enroll)
        XCTAssertEqual(account.step, .emailCode)
        wire.failure = URLError(.notConnectedToInternet)
        let window = try mount(AccountSetupView(account: account, coordinator: AccountWorkspaceCoordinator(account: account, root: root)).environment(\.dynamicTypeSize, .accessibility3))
        let host = try XCTUnwrap(window.rootViewController), originalInsets = host.additionalSafeAreaInsets
        defer { host.additionalSafeAreaInsets = originalInsets; restoreWindow() }
        try await settle(window)
        try await revealField("Email code", in: window)
        let field = try XCTUnwrap(fields(window).first { $0.placeholder == "Email code" })
        field.becomeFirstResponder(); try await settle(window)
        try enter("123456", placeholder: "Email code", in: window)
        let fullHeight = host.view.safeAreaLayoutGuide.layoutFrame.height
        host.additionalSafeAreaInsets.bottom = 300
        try await settle(window)
        XCTAssertLessThan(host.view.safeAreaLayoutGuide.layoutFrame.height, fullHeight - 250, "The hosted content must actually lose a keyboard-sized area")
        await account.verifyEmail(code: "123456")
        try await settle(window)
        XCTAssertNotNil(account.message); XCTAssertFalse(account.busy); XCTAssertEqual(wire.requests.count, 2)
        XCTAssertEqual(account.step, .emailCode); XCTAssertFalse(account.trusted)
        XCTAssertTrue(field.isFirstResponder, "Text editing remains active in the deliberately reduced viewport")
        let text = try renderedText(window, name: "Async account error accessibility reduced viewport")
        let message = try XCTUnwrap(account.message).lowercased().filter { $0.isLetter || $0.isNumber }
        XCTAssertTrue(text.contains(message), "The complete actual failure must be readable without manual scrolling")
    }

    func testRetainedSetupUsesNewAuthenticatorAfterBackupLoginThenEnrollment() async throws {
        try await retainedSetup(purpose: .enroll)
    }
    func testRetainedSetupUsesNewAuthenticatorAfterBackupLoginThenRecovery() async throws {
        try await retainedSetup(purpose: .recover)
    }
    private func retainedSetup(purpose: IdentityPurpose) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let wire = StagedAccountTransport(), auth = RetryAccountAuthorization()
        let account = NativeAccountStore(client: AccountClient(transport: wire), credentials: MemoryAccountCredentials(), authorization: auth)
        let coordinator = AccountWorkspaceCoordinator(account: account, root: root)
        let window = try mount(AccountSetupView(account: account, coordinator: coordinator))
        defer { restoreWindow(); coordinator.visibleWorkspace?.suspend() }
        try await settle(window)
        try await activate("Sign in with passkey", in: window)
        XCTAssertEqual(account.step, .secondFactor)
        let toggle = try XCTUnwrap(elements(window).first { ($0.accessibilityLabel == "Use a backup code" || $0.accessibilityValue == "Use a backup code") })
        if let control = toggle as? UISwitch { control.setOn(true, animated: false); control.sendActions(for: .valueChanged) }
        else { XCTAssertTrue(toggle.accessibilityActivate()) }
        try await settle(window)
        XCTAssertTrue(fields(window).contains { $0.placeholder == "Backup code" })
        try await activate("Cancel setup", in: window)
        try account.setCheckpoint(ageYears: 30, role: .adultSelf)
        await account.startEmail(email: "owner@example.test", purpose: purpose)
        await account.verifyEmail(code: "123456")
        try await settle(window)
        if purpose == .recover {
            try enter("unused-backup", placeholder: "Unused backup code", in: window)
            try await activate("Create replacement passkey", in: window)
        } else { try await activate("Create your verified passkey", in: window) }
        XCTAssertEqual(account.step, .authenticatorSetup)
        try enter("654321", placeholder: "Authenticator code", in: window)
        try await activate("Complete secure sign-in", in: window)
        XCTAssertEqual(wire.completedBody?["code"], "654321"); XCTAssertNil(wire.completedBody?["backupCode"])
        XCTAssertTrue(account.trusted)
        try await settle(window)
        XCTAssertTrue(labels(window).contains { $0.contains("new-backup") }, "Successful enrollment must render newly issued backup codes in the same hosted view")
    }
    func testExpiredRenderedSetupHidesSeedAndOffersUsableStartAgain() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let marker = root.appendingPathComponent("saved-record.txt")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("retained records".utf8).write(to: marker)
        let wire = StagedAccountTransport(), vault = MemoryAccountCredentials()
        let retained = retryCredential(); try vault.save(retained)
        let account = NativeAccountStore(client: AccountClient(transport: wire), credentials: vault, authorization: RetryAccountAuthorization())
        wire.expiry = .now.addingTimeInterval(2)
        await account.startEmail(email: "owner@example.test", purpose: .recover); await account.verifyEmail(code: "123456")
        await account.enrollPasskey(recoveryBackup: "unused-backup")
        let coordinator = AccountWorkspaceCoordinator(account: account, root: root)
        let window = try mount(AccountSetupView(account: account, coordinator: coordinator)); defer { restoreWindow() }
        try await settle(window)
        let validText = try renderedText(window, name: "Valid Authenticator setup")
        XCTAssertTrue(validText.contains("temporarysetupkey")); XCTAssertTrue(validText.contains("completesecuresignin"))
        try await Task.sleep(for: .milliseconds(2100)); try await settle(window)
        XCTAssertNil(account.authenticatorSecret); XCTAssertEqual(account.step, .restart)
        let expiredText = try renderedText(window, name: "Expired setup with restart")
        XCTAssertFalse(expiredText.contains("temporarysetupkey"))
        XCTAssertFalse(expiredText.contains("completesecuresignin"))
        XCTAssertTrue(labels(window).contains { $0.lowercased().contains("expired") })
        try await activate("Start again", in: window)
        XCTAssertEqual(account.step, .identity); XCTAssertNil(wire.completedBody)
        XCTAssertEqual(try vault.load(), retained); XCTAssertEqual(try Data(contentsOf: marker), Data("retained records".utf8))
        wire.expiry = .now.addingTimeInterval(300)
        await account.startEmail(email: "owner@example.test", purpose: .recover); await account.verifyEmail(code: "123456")
        await account.enrollPasskey(recoveryBackup: "unused-backup")
        XCTAssertEqual(account.step, .authenticatorSetup)
    }
    func testMonthlyMemberSeesPendingAndCancelledLifetimePurchase() async throws {
        for (result, message) in [(MembershipPurchaseResult.pending, "pending approval"), (.cancelled, "cancelled")] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let id = UUID(), client = RetryMembershipClient(accountID: id, result: result)
            let membership = MembershipStore(root: root, client: client); membership.setAccount(id)
            let profile = NativeProfileStore(url: root.appendingPathComponent("profile.json"))
            try profile.save(LocalProfile(programmePreferences: .init(goals: [.balance], weekdays: [1], ageContext: .init(ageYears: 30, guardianManaged: false))))
            let window = try mount(NavigationStack { MembershipView(store: membership).environment(\.profileWebsiteAccess, ProfileWebsiteAccess(profile: profile, guardian: RetryAccountAuthorization())) })
            defer { restoreWindow() }
            try await settle(window)
            try await activate("Explore membership options", in: window)
            try await activate("Buy lifetime membership", in: window)
            XCTAssertTrue(labels(window).contains { $0.contains(message) }, "An active monthly member must see the lifetime operation outcome")
            XCTAssertTrue(membership.hasAccess); XCTAssertFalse(membership.access.lifetime)
            XCTAssertEqual(client.purchases, [.lifetime])
        }
    }
    func testSignedOutRestoreKeepsGuardianFenceAndDeliversAfterApproval() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let client = RetryMembershipClient(accountID: UUID(), result: .cancelled), auth = RetryAccountAuthorization()
        auth.guardianAllowed = false
        let membership = MembershipStore(root: root, client: client)
        let window = try mount(NavigationStack { MembershipView(store: membership).environment(\.profileWebsiteAccess, ProfileWebsiteAccess(guardian: auth, isCurrent: { true })) })
        defer { restoreWindow() }
        try await settle(window); try await activate("Restore purchases", in: window)
        XCTAssertEqual(client.restores, 0); XCTAssertFalse(membership.hasAccess)
        XCTAssertTrue(labels(window).contains { $0.contains("Approval is needed") })
        auth.guardianAllowed = true
        try await activate("Restore purchases", in: window)
        XCTAssertEqual(client.restores, 1); XCTAssertFalse(membership.hasAccess)
        XCTAssertTrue(labels(window).contains { $0.contains("No active membership for this account") })
    }
    private var activeWindow: UIWindow?
    private var originalRoot: UIViewController?
    private var originalHidden = false
    private var originalLevel = UIWindow.Level.normal
    private func mount<V: View>(_ view: V) throws -> UIWindow {
        restoreWindow()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try XCTUnwrap(scene.windows.first { $0.isKeyWindow })
        activeWindow = window; originalRoot = window.rootViewController
        originalHidden = window.isHidden; originalLevel = window.windowLevel
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible(); return window
    }
    private func restoreWindow() {
        guard let window = activeWindow else { return }
        window.rootViewController = originalRoot; window.windowLevel = originalLevel; window.isHidden = originalHidden; window.makeKey()
        activeWindow = nil; originalRoot = nil
    }
    private func settle(_ window: UIWindow) async throws {
        window.setNeedsLayout(); window.layoutIfNeeded(); try await Task.sleep(for: .milliseconds(450)); window.layoutIfNeeded()
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { _ in XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)) }
        XCTAssertGreaterThan(try XCTUnwrap(image.pngData()).count, 1000)
    }
    private func renderedText(_ window: UIWindow, name: String) throws -> String {
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
        try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage)).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined().lowercased().filter { $0.isLetter || $0.isNumber }
    }
    private func elements(_ root: NSObject) -> [NSObject] {
        var result: [NSObject] = [], seen = Set<ObjectIdentifier>()
        func visit(_ object: NSObject) {
            guard seen.insert(ObjectIdentifier(object)).inserted else { return }
            result.append(object); (object as? UIView)?.subviews.forEach(visit)
            object.accessibilityElements?.compactMap { $0 as? NSObject }.forEach(visit)
            let count = object.accessibilityElementCount()
            if count > 0 && count < 500 { for index in 0..<count { if let child = object.accessibilityElement(at: index) as? NSObject { visit(child) } } }
        }
        visit(root); return result
    }
    private func labels(_ window: UIWindow) -> [String] { elements(window).flatMap { [$0.accessibilityLabel, $0.accessibilityValue].compactMap { $0 } } }
    private func isExposed(_ object: NSObject, in window: UIWindow) -> Bool {
        if let view = object as? UIView {
            guard view.window === window, view.convert(view.bounds, to: window).intersects(window.bounds) else { return false }
            var ancestor: UIView? = view
            while let current = ancestor {
                if current.isHidden || current.alpha < 0.01 { return false }
                ancestor = current.superview
            }
            return true
        }
        return object.accessibilityFrame.intersects(window.convert(window.bounds, to: nil))
    }
    private func fields(_ window: UIWindow) -> [UITextField] { elements(window).compactMap { $0 as? UITextField }.filter { isExposed($0, in: window) } }
    private func revealField(_ placeholder: String, in window: UIWindow) async throws {
        for _ in 0..<8 {
            if fields(window).contains(where: { $0.placeholder == placeholder }) { return }
            for scroll in elements(window).compactMap({ $0 as? UIScrollView }) where scroll.contentSize.height > scroll.bounds.height {
                let bottom = max(0, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
                scroll.setContentOffset(CGPoint(x: 0, y: min(bottom, scroll.contentOffset.y + scroll.bounds.height * 0.6)), animated: false)
            }
            try await settle(window)
        }
        XCTFail("Missing visible field \(placeholder)")
    }
    private func enter(_ text: String, placeholder: String, in window: UIWindow) throws {
        let field = try XCTUnwrap(fields(window).first { $0.placeholder == placeholder }, "Missing rendered \(placeholder)")
        field.text = text; field.sendActions(for: .editingChanged)
    }
    private func activate(_ label: String, in window: UIWindow) async throws {
        for _ in 0..<8 {
            if let element = elements(window).first(where: { isExposed($0, in: window) && $0.accessibilityTraits.contains(.button) && ($0.accessibilityLabel == label || $0.accessibilityValue == label) }) {
                if let control = element as? UIControl { control.sendActions(for: .touchUpInside) }
                else { XCTAssertTrue(element.accessibilityActivate(), "Could not activate \(label)") }
                try await settle(window); return
            }
            for scroll in elements(window).compactMap({ $0 as? UIScrollView }) where scroll.contentSize.height > scroll.bounds.height {
                let bottom = max(0, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
                scroll.setContentOffset(CGPoint(x: 0, y: min(bottom, scroll.contentOffset.y + scroll.bounds.height * 0.6)), animated: false)
            }
            try await settle(window)
        }
        XCTFail("Missing rendered button \(label): \(labels(window))")
    }
}
@MainActor private final class RetryMembershipClient: MembershipClient {
    let accountID: UUID
    let result: MembershipPurchaseResult
    var purchases: [MembershipPlan] = []
    var restores = 0
    init(accountID: UUID, result: MembershipPurchaseResult) { self.accountID = accountID; self.result = result }
    func products() async throws -> [MembershipOffer] { [.init(plan: .lifetime, displayName: "Lifetime membership", displayPrice: "£200")] }
    func currentEntitlements() async -> [MembershipVerification] { [.verified(.init(appAccountToken: accountID, productID: MembershipPlan.monthly.productID, kind: .autoRenewable, expirationDate: .now.addingTimeInterval(3600)))] }
    func updates() -> AsyncStream<MembershipVerification> { AsyncStream { $0.finish() } }
    func purchase(_ plan: MembershipPlan, appAccountToken: UUID) async throws -> MembershipPurchaseResult { purchases.append(plan); return result }
    func restore() async throws { restores += 1 }
    func finish(transactionID: UInt64) async {}
}

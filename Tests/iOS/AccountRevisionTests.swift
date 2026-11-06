import XCTest
import SwiftUI
import UIKit
import CryptoKit
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
        let host = UIHostingController(rootView: SpottrRoot(store: adult.training, profileStore: adult.profile, healthStore: adultHealth))
        let window = try mount(host)
        defer { window.isHidden = true }
        for (workspace, health, expectedAdultRequests) in [(adult, adultHealth, 1), (junior, juniorHealth, 1), (adult, adultHealth, 2)] {
            host.rootView = SpottrRoot(store: workspace.training, profileStore: workspace.profile, healthStore: health)
            try await settle(window)
            try await scrollToBottom(window)
            try activate("today-health-setup", in: window)
            try await settle(window)
            try activate("health-connect", in: window)
            try await settle(window)
            XCTAssertEqual(adultClient.requests, expectedAdultRequests)
            XCTAssertEqual(juniorClient.requests, 0)
        }
        let replacement = try AccountWorkspace(scope: adult.scope)
        host.rootView = SpottrRoot(store: replacement.training, profileStore: replacement.profile, healthStore: replacementHealth)
        try await settle(window)
        try await scrollToBottom(window)
        try activate("today-health-setup", in: window)
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
        return try AccountWorkspace(scope: directory.scope(profile.id))
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
        let labels = ["today-health-setup": "Health history & heart-rate zones", "health-connect": "Choose Health data"]
        let element = try XCTUnwrap(elements(window).first { ($0 as? any UIAccessibilityIdentification)?.accessibilityIdentifier == id || $0.accessibilityLabel == labels[id] }, "Missing rendered accessibility element \(id). Rendered elements: \(elements(window).compactMap { $0.accessibilityLabel }.prefix(70))")
        XCTAssertTrue(element.accessibilityActivate(), "Rendered action did not activate: \(id)")
    }
    private func activate(label: String, in window: UIWindow) throws {
        let element = try XCTUnwrap(elements(window).first { ($0.accessibilityLabel == label || $0.accessibilityValue == label) && $0.accessibilityTraits.contains(.button) }, "Missing rendered button \(label)")
        XCTAssertTrue(element.accessibilityActivate(), "Rendered button did not activate: \(label)")
    }

}

@MainActor private final class RevisionHealthClient: HealthReadingClient {
    let isAvailable: Bool
    var requests = 0
    init(available: Bool) { isAvailable = available }
    func requestReadAuthorization() async throws { requests += 1 }
    func read(asOf: Date, dayStart: Date, dayEnd: Date) async throws -> [HealthObservation] { [] }
}

import XCTest
import SwiftUI
import UIKit
import CryptoKit
@testable import Spottr

@MainActor final class WorkoutLaunchTests: XCTestCase {
    func testAllOriginsWaitForMembershipAndCancelledOrStaleIntentCannotStart() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let plan = try CoachSavedPlan.catalogue(exerciseID: "frontArmRaise", sets: 1, target: 6, restSeconds: 30)
        for origin in WorkoutLaunchOrigin.allCases {
            fixture.launch.request(plan: plan, origin: origin)
            XCTAssertEqual(fixture.launch.decision, .requiresMembership)
            XCTAssertEqual(fixture.workspace.training.sessionPhase, .idle)
            let token = try XCTUnwrap(fixture.launch.pendingID)
            fixture.launch.cancel()
            fixture.launch.continuePending(id: token)
            XCTAssertEqual(fixture.workspace.training.sessionPhase, .idle)
        }
        fixture.launch.request(plan: plan, origin: .coach)
        let old = try XCTUnwrap(fixture.launch.pendingID)
        fixture.generation = UUID()
        fixture.client.entitlements = [.verified(.init(appAccountToken: fixture.owner.accountID, productID: MembershipPlan.lifetime.productID, kind: .nonConsumable))]
        await fixture.membership.refreshEntitlements()
        fixture.launch.continuePending(id: old)
        XCTAssertEqual(fixture.workspace.training.sessionPhase, .idle)
        fixture.launch.request(plan: plan, origin: .library)
        XCTAssertEqual(fixture.workspace.training.configured?.current.exerciseID, plan.items.first?.exerciseID)
        fixture.workspace.training.beginConfiguredSet()
        fixture.workspace.training.setConfiguredReps(4)
        let session = fixture.workspace.training.configured?.id
        fixture.client.entitlements = []
        await fixture.membership.refreshEntitlements()
        fixture.launch.request(plan: try .catalogue(exerciseID: "squat", sets: 3, target: 10, restSeconds: 60), origin: .today)
        XCTAssertEqual(fixture.launch.decision, .resumeExisting)
        XCTAssertEqual(fixture.workspace.training.configured?.id, session)
        XCTAssertEqual(fixture.workspace.training.configured?.actualReps, 4)
    }

    func testExpectedAuthenticationRetainsIntentButCancelledAuthenticationCannotReviveIt() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let plan = try CoachSavedPlan.catalogue(exerciseID: "frontArmRaise", sets: 1, target: 6, restSeconds: 30)
        fixture.launch.request(plan: plan, origin: .today)
        let id = try XCTUnwrap(fixture.launch.pendingID)
        fixture.launch.authenticationWillBegin()
        fixture.generation = UUID()
        fixture.launch.authenticationDidComplete()
        XCTAssertEqual(fixture.launch.pendingID, id)
        fixture.client.entitlements = [.verified(.init(appAccountToken: fixture.owner.accountID, productID: MembershipPlan.lifetime.productID, kind: .nonConsumable))]
        await fixture.membership.refreshEntitlements()
        XCTAssertEqual(fixture.workspace.training.sessionPhase, .idle)
        fixture.launch.continuePending(id: id)
        XCTAssertEqual(fixture.workspace.training.configured?.current.exerciseID, "frontArmRaise")
        fixture.launch.cancel()
        fixture.launch.authenticationDidComplete()
        XCTAssertNil(fixture.launch.pendingID)
    }

    func testTrainingStoreStartsFailClosedWithoutCoordinatorAndURLCannotBypassPolicy() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        fixture.workspace.training.start()
        XCTAssertEqual(fixture.workspace.training.sessionPhase, .idle)
        fixture.workspace.training.launchCoordinator = fixture.launch
        fixture.launch.open(URL(string: "spottr://workout?exercise=frontArmRaise")!)
        XCTAssertEqual(fixture.launch.decision, .requiresMembership)
        fixture.owner = .init(accountID: UUID(), profileID: UUID())
        let token = try XCTUnwrap(fixture.launch.pendingID)
        fixture.launch.continuePending(id: token)
        XCTAssertEqual(fixture.workspace.training.sessionPhase, .idle)
        fixture.launch.open(URL(string: "spottr://workout?exercise=unknown")!)
        XCTAssertNil(fixture.launch.pendingID)
    }

    func testActualAccountWorkspaceWiresTodayURLAndCompanionWithoutIdleBypass() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID(), vault = MemoryAccountCredentials(), wire = AccountTestTransport()
        try vault.save(.init(session: NativeAccountSession(authenticated: true, accountID: id, appAccountToken: id, deviceID: UUID(), accessToken: "access", refreshToken: "refresh", accessExpiresAt: .now.addingTimeInterval(900), refreshExpiresAt: .now.addingTimeInterval(86400)), privateKey: P256.Signing.PrivateKey().rawRepresentation))
        wire.failure = URLError(.notConnectedToInternet)
        let authorization = AccountTestAuthorization(); authorization.succeed = true
        let account = NativeAccountStore(client: AccountClient(transport: wire), credentials: vault, authorization: authorization)
        let client = LaunchMembershipClient(), membership = MembershipCoordinator(client: client, claims: ProtectedMembershipClaimStore(root: root))
        let coordinator = AccountWorkspaceCoordinator(account: account, root: root, membership: membership)
        coordinator.openWorkoutURL(URL(string: "spottr://workout?exercise=frontArmRaise")!)
        await account.restore(); coordinator.accountChanged()
        let created = await coordinator.createProfile(name: "Adult", age: try .init(ageYears: 30, guardianManaged: false))
        XCTAssertTrue(created)
        let workspace = try XCTUnwrap(coordinator.visibleWorkspace)
        XCTAssertEqual(workspace.launch?.decision, .requiresSetup)
        try workspace.profile.saveMeasurements(.init(heightCM: 170, weightKG: 70))
        let pending = try XCTUnwrap(workspace.launch?.pendingID)
        workspace.launch?.continuePending(id: pending)
        XCTAssertEqual(workspace.launch?.decision, .requiresMembership)
        workspace.launch?.cancel()
        workspace.training.start()
        XCTAssertEqual(workspace.launch?.decision, .requiresMembership)
        XCTAssertTrue(workspace.training.launchCoordinator === workspace.launch)
        XCTAssertTrue(workspace.launch?.membership === membership)
        let training = workspace.training
        training.companion.onCommand?(.init(sessionID: training.session.id, generation: training.session.generation, action: .startSet))
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(training.sessionPhase, .idle)
        client.entitlements = [.verified(.init(appAccountToken: id, productID: MembershipPlan.lifetime.productID, kind: .nonConsumable))]
        await membership.refreshEntitlements()
        coordinator.openWorkoutURL(URL(string: "spottr://workout?exercise=frontArmRaise")!)
        let run = try XCTUnwrap(training.configured)
        training.companion.onCommand?(.init(sessionID: run.id, generation: run.generation, action: .startSet))
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(training.configured?.hasStarted == true)
        training.setConfiguredReps(5); training.pause()
        client.entitlements = []; await membership.refreshEntitlements()
        let paused = try XCTUnwrap(training.configured)
        training.companion.onCommand?(.init(sessionID: paused.id, generation: paused.generation, action: .resume))
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(training.configured?.actualReps, 5)
        XCTAssertEqual(training.configured?.phase, .active)
    }

    func testRenderedCatalogueStartShowsMembershipAtTheRequestingSurface() async throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        fixture.workspace.training.launchCoordinator = fixture.launch
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = scene.coordinateSpace.bounds
        window.rootViewController = UIHostingController(rootView: NavigationStack { CatalogueWorkoutSetupView(store: fixture.workspace.training, entry: ExerciseCatalog.find("frontArmRaise")!) })
        window.makeKeyAndVisible(); defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(300)); render(window)
        let button = try await waitForElement("Start workout", in: window)
        XCTAssertTrue(button.accessibilityActivate())
        try await Task.sleep(for: .milliseconds(300)); render(window)
        XCTAssertTrue(elements(window).contains { $0.accessibilityLabel?.contains("Your membership") == true })
        fixture.client.entitlements = [.verified(.init(appAccountToken: fixture.owner.accountID, productID: MembershipPlan.lifetime.productID, kind: .nonConsumable))]
        await fixture.membership.refreshEntitlements()
        let next = try await waitForElement("Continue to workout", in: window)
        XCTAssertTrue(next.accessibilityActivate())
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(fixture.workspace.training.configured?.current.exerciseID, "frontArmRaise")
        XCTAssertTrue(fixture.workspace.training.presented)
    }

    func testRequiredSetupOffersMeasurementEntryWithoutLosingSelectedPlan() async throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let preferences = try XCTUnwrap(fixture.workspace.profile.profile?.programmePreferences)
        try fixture.workspace.profile.save(.init(programmePreferences: preferences))
        let plan = try CoachSavedPlan.catalogue(exerciseID: "frontArmRaise", sets: 1, target: 6, restSeconds: 30)
        fixture.launch.request(plan: plan, origin: .today)
        let id = try XCTUnwrap(fixture.launch.pendingID)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = scene.coordinateSpace.bounds
        window.rootViewController = UIHostingController(rootView: WorkoutLaunchAccessView(launch: fixture.launch))
        window.makeKeyAndVisible(); defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(400)); render(window)
        _ = try await waitForElement("Add required measurements", in: window)
        try fixture.workspace.profile.saveMeasurements(.init(heightCM: 170, weightKG: 70))
        fixture.launch.continuePending(id: id)
        XCTAssertEqual(fixture.launch.pendingID, id)
        XCTAssertEqual(fixture.launch.decision, .requiresMembership)
    }

    func testRenderedTodayContinuesIntoSelectedWorkoutAfterVerifiedMembership() async throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        fixture.workspace.training.launchCoordinator = fixture.launch
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = scene.coordinateSpace.bounds
        window.rootViewController = UIHostingController(rootView: SpottrRoot(store: fixture.workspace.training, profileStore: fixture.workspace.profile, membership: fixture.membership))
        window.makeKeyAndVisible(); defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(300)); render(window)
        fixture.workspace.training.start()
        try await Task.sleep(for: .milliseconds(500)); render(window)
        XCTAssertEqual(fixture.launch.decision, .requiresMembership)
        fixture.client.entitlements = [.verified(.init(appAccountToken: fixture.owner.accountID, productID: MembershipPlan.lifetime.productID, kind: .nonConsumable))]
        await fixture.membership.refreshEntitlements()
        try await Task.sleep(for: .milliseconds(200)); render(window)
        let accessController = try XCTUnwrap(window.rootViewController?.presentedViewController)
        let pending = try XCTUnwrap(fixture.launch.pendingID)
        fixture.launch.continuePending(id: pending)
        for _ in 0..<20 where window.rootViewController?.presentedViewController === accessController {
            try await Task.sleep(for: .milliseconds(100))
        }
        render(window)
        XCTAssertEqual(fixture.workspace.training.configured?.current.exerciseID, "squat")
        let workoutController = try XCTUnwrap(window.rootViewController?.presentedViewController)
        XCTAssertFalse(workoutController === accessController)
        XCTAssertTrue([UIModalPresentationStyle.fullScreen, .overFullScreen].contains(workoutController.modalPresentationStyle))
        XCTAssertNotNil(workoutController.view.window)
        XCTAssertTrue(fixture.workspace.training.presented)
    }

    private func waitForElement(_ label: String, in window: UIWindow) async throws -> NSObject {
        for _ in 0..<20 {
            render(window)
            if let found = elements(window).first(where: { $0.accessibilityLabel == label }) { return found }
            try await Task.sleep(for: .milliseconds(100))
        }
        return try XCTUnwrap(elements(window).first { $0.accessibilityLabel == label }, "Missing rendered action \(label); \(elements(window).compactMap { $0.accessibilityLabel })")
    }

    private func render(_ window: UIWindow) {
        window.setNeedsLayout(); window.layoutIfNeeded()
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        UIAccessibility.post(notification: .screenChanged, argument: window.rootViewController?.view)
        let attachment = XCTAttachment(image: image); attachment.name = "Task4 rendered membership"; attachment.lifetime = .keepAlways; add(attachment)
    }

    private func elements(_ root: NSObject) -> [NSObject] {
        var result: [NSObject] = [], seen = Set<ObjectIdentifier>()
        func visit(_ object: NSObject) {
            guard seen.insert(ObjectIdentifier(object)).inserted else { return }
            result.append(object)
            if let view = object as? UIView { view.subviews.forEach(visit) }
            object.accessibilityElements?.compactMap { $0 as? NSObject }.forEach(visit)
            let count = object.accessibilityElementCount()
            if count > 0 && count < 500 { for i in 0..<count { if let child = object.accessibilityElement(at: i) as? NSObject { visit(child) } } }
        }
        visit(root); return result
    }

    func testMembershipSurfaceRequiresAccountAndKeepsRestoreWhenProductsFail() async throws {
        let store = MembershipCoordinator(client: LaunchMembershipClient(), claims: ProtectedMembershipClaimStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = scene.coordinateSpace.bounds
        let host = UIHostingController(rootView: NavigationStack { MembershipView(store: store) })
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(400))
        render(window)
        try await Task.sleep(for: .milliseconds(200))
        var labels: [String] = []
        for _ in 0..<10 {
            labels = elements(window).compactMap { $0.accessibilityLabel }
            if labels.contains(where: { $0.contains("Your membership") }) { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(labels.contains { $0.contains("Your membership") }, labels.joined(separator: "; "))
        XCTAssertFalse(labels.contains { $0.contains("All features available during beta") })
        XCTAssertTrue(labels.contains { $0.contains("Restore purchases") })
    }

    @MainActor private final class Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let workspace: AccountWorkspace
        let client = LaunchMembershipClient()
        let membership: MembershipCoordinator
        var owner: WorkoutOwner
        var generation = UUID()
        lazy var launch = WorkoutLaunchCoordinator(training: workspace.training, profile: workspace.profile, membership: membership,
                                                   owner: { [unowned self] in self.owner }, generation: { [unowned self] in self.generation })
        init() throws {
            let scope = AccountDataScope(accountID: UUID(), profileID: UUID(), root: root)
            workspace = try AccountWorkspace(scope: scope)
            owner = .init(accountID: scope.accountID, profileID: scope.profileID)
            membership = MembershipCoordinator(client: client, claims: ProtectedMembershipClaimStore(root: root)); membership.setAccount(scope.accountID)
            try workspace.profile.save(.init(bodyMeasurements: .init(heightCM: 170, weightKG: 70), programmePreferences: .init(goals: [.balance], weekdays: [1], ageContext: .init(ageYears: 30, guardianManaged: false))))
        }
        func clean() { try? FileManager.default.removeItem(at: root) }
    }
}

@MainActor private final class LaunchMembershipClient: MembershipClient {
    var entitlements: [MembershipVerification] = []
    func products() async throws -> [MembershipOffer] { [] }
    func currentEntitlements() async -> [MembershipVerification] { entitlements }
    func updates() -> AsyncStream<MembershipVerification> { AsyncStream { $0.finish() } }
    func purchase(_ plan: MembershipPlan, appAccountToken: UUID) async throws -> MembershipPurchaseResult { .cancelled }
    func restore() async throws {}
    func finish(transactionID: UInt64) async {}
}

import XCTest
import SwiftUI
import UIKit
import Observation
import CryptoKit
@testable import Spottr

@MainActor final class SetupRenderedAcceptanceTests: XCTestCase {
    private var originalWindow: UIWindow?
    private var originalController: UIViewController?
    private var originalHidden = false
    private var originalLevel = UIWindow.Level.normal
    private weak var priorKeyWindow: UIWindow?
    override func tearDown() {
        originalWindow?.rootViewController = originalController
        originalWindow?.windowLevel = originalLevel
        originalWindow?.isHidden = originalHidden
        priorKeyWindow?.makeKey()
        originalWindow = nil; originalController = nil
        super.tearDown()
    }
    func testCatalogueKeepsPendingRequestWhenItsRenderedBranchChanges() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let scope = AccountDataScope(accountID: UUID(), profileID: UUID(), root: root)
        let workspace = try AccountWorkspace(scope: scope)
        try workspace.profile.save(acceptedProfile())
        let membership = MembershipCoordinator(client: SetupRenderedMembershipClient(), claims: ProtectedMembershipClaimStore(root: root))
        membership.setAccount(scope.accountID)
        let generation = UUID()
        let launch = WorkoutLaunchCoordinator(training: workspace.training, profile: workspace.profile, membership: membership,
            owner: { .init(accountID: scope.accountID, profileID: scope.profileID) }, generation: { generation })
        workspace.training.launchCoordinator = launch
        let window = try host(NavigationStack { CatalogueWorkoutSetupView(store: workspace.training, entry: ExerciseCatalog.find("frontArmRaise")!) }
            .fullScreenCover(isPresented: Binding(get: { workspace.training.presented }, set: { workspace.training.presented = $0 })) { SessionView(store: workspace.training) })
        try await Task.sleep(for: .milliseconds(200)); capture(window, "catalogue-before-public-start")
        workspace.training.startPlan(try .catalogue(exerciseID: "frontArmRaise", sets: 3, target: 10, restSeconds: 60), availableSupport: [])
        let pending = try XCTUnwrap(launch.pendingID)
        try await Task.sleep(for: .milliseconds(500)); capture(window, "catalogue-after-public-start")
        XCTAssertEqual(launch.pendingID, pending)
        XCTAssertEqual(launch.decision, .requiresMembership)
        XCTAssertEqual(workspace.training.sessionPhase, .idle)
    }

    func testExternalCatalogueMembershipContinueUsesExactSelection() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let scope = AccountDataScope(accountID: UUID(), profileID: UUID(), root: root)
        let workspace = try AccountWorkspace(scope: scope)
        try workspace.profile.save(acceptedProfile())
        let client = SetupRenderedMembershipClient()
        let membership = MembershipCoordinator(client: client, claims: ProtectedMembershipClaimStore(root: root))
        membership.setAccount(scope.accountID)
        let generation = UUID()
        let launch = WorkoutLaunchCoordinator(training: workspace.training, profile: workspace.profile, membership: membership,
            owner: { .init(accountID: scope.accountID, profileID: scope.profileID) }, generation: { generation })
        workspace.training.launchCoordinator = launch
        let window = try host(NavigationStack { CatalogueWorkoutSetupView(store: workspace.training, entry: ExerciseCatalog.find("frontArmRaise")!) }
            .fullScreenCover(isPresented: Binding(get: { workspace.training.presented }, set: { workspace.training.presented = $0 })) { SessionView(store: workspace.training) })
        defer { window.isHidden = true }
        capture(window, "catalogue-before-start")
        let requested = expectation(description: "Actual Start mutates pending intent")
        withObservationTracking { _ = launch.pendingID } onChange: {
            print("SETUP_PUBLIC_PENDING_MUTATION")
            requested.fulfill()
        }
        await fulfillment(of: [requested], timeout: 90)
        XCTAssertEqual(launch.decision, .requiresMembership)

        XCTAssertEqual(workspace.training.sessionPhase, .idle)
        let pending = try XCTUnwrap(launch.pendingID)
        capture(window, "membership-before-verification")
        try await Task.sleep(for: .seconds(15))
        client.entitlements = [.verified(.init(appAccountToken: scope.accountID, productID: MembershipPlan.lifetime.productID, kind: .nonConsumable))]
        await membership.refreshEntitlements()
        XCTAssertEqual(launch.pendingID, pending)
        XCTAssertEqual(workspace.training.sessionPhase, .idle)
        capture(window, "membership-verified-continue")
        try await wait { workspace.training.configured != nil }
        XCTAssertEqual(workspace.training.configured?.current.exerciseID, "frontArmRaise")
        XCTAssertNil(launch.pendingID)
        XCTAssertTrue(workspace.training.presented)
        try await Task.sleep(for: .seconds(1))
        XCTAssertNotNil(window.rootViewController?.presentedViewController?.view.window)
        capture(window, "selected-session-launched")
        try await Task.sleep(for: .seconds(5))
    }

    func testExternalOnboardingRetainsMeasurementsAndExactPendingIntent() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let scope = AccountDataScope(accountID: UUID(), profileID: UUID(), root: root)
        let workspace = try AccountWorkspace(scope: scope)
        try workspace.profile.save(LocalProfile(name: "Adult", onboardingRevision: 0, programmePreferences: .init(goals: [.balance], weekdays: [1, 3, 5], ageContext: .init(ageYears: 30, guardianManaged: false))))
        let client = SetupRenderedMembershipClient()
        let member = MembershipCoordinator(client: client, claims: ProtectedMembershipClaimStore(root: root))
        member.setAccount(scope.accountID)
        let generation = UUID()
        let launch = WorkoutLaunchCoordinator(training: workspace.training, profile: workspace.profile, membership: member,
            owner: { .init(accountID: scope.accountID, profileID: scope.profileID) }, generation: { generation })
        launch.healthStore = workspace.health
        launch.request(plan: try .catalogue(exerciseID: "frontArmRaise", sets: 1, target: 6, restSeconds: 30), origin: .today)
        let pending = try XCTUnwrap(launch.pendingID)
        XCTAssertEqual(launch.decision, .requiresSetup)
        let window = try host(WorkoutLaunchAccessView(launch: launch)); defer { window.isHidden = true }
        capture(window, "required-setup")
        try await wait(seconds: 360) { AccountPolicy.setupComplete(profile: workspace.profile.profile) }
        XCTAssertEqual(launch.pendingID, pending)
        XCTAssertEqual(workspace.profile.profile?.bodyMeasurements?.heightCM, 170)
        XCTAssertEqual(workspace.profile.profile?.bodyMeasurements?.weightKG, 70)
        XCTAssertEqual(workspace.training.sessionPhase, .idle)
        launch.continuePending(id: pending)
        XCTAssertEqual(launch.decision, .requiresMembership)
        XCTAssertTrue(workspace.training.history.isEmpty)
        capture(window, "setup-complete-intent-retained")
    }

    func testExternalAccountCheckpointDoesNotEstablishTrust() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let account = NativeAccountStore(client: AccountClient(transport: AccountTestTransport()), credentials: MemoryAccountCredentials(), authorization: SetupRenderedAuthorization())
        let coordinator = AccountWorkspaceCoordinator(account: account, root: root, membershipClient: SetupRenderedMembershipClient())
        let window = try host(AccountSetupView(account: account, coordinator: coordinator))
        try await Task.sleep(for: .milliseconds(300))
        capture(window, "account-stage-one-concise")
        try await wait(seconds: 90) { account.checkpoint?.ageYears == 30 }
        XCTAssertFalse(try XCTUnwrap(account.checkpoint).guardianManaged)
        XCTAssertFalse(account.trusted)
        XCTAssertEqual(account.step, .identity)
        XCTAssertNil(coordinator.workspace)
        capture(window, "account-age-confirmed-still-requires-sign-in")
    }

    func testExternalSignedOutRestoreHelpAndRetainedRecords() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = try AccountProfileDirectory(accountID: UUID(), root: root)
        let person = try directory.add(age: .init(ageYears: 30, guardianManaged: false), name: "Retained adult")
        let scope = directory.scope(person.id)
        let original = try Data(contentsOf: scope.file("profile.json"))
        let authorization = SetupRenderedAuthorization()
        let account = NativeAccountStore(client: AccountClient(transport: AccountTestTransport()), credentials: MemoryAccountCredentials(), authorization: authorization)
        let client = SetupRenderedMembershipClient()
        let coordinator = AccountWorkspaceCoordinator(account: account, root: root, membershipClient: client)
        var supportOpened = false
        let window = try host(AccountSetupView(account: account, coordinator: coordinator)
            .environment(\.openURL, OpenURLAction { url in supportOpened = url.path == "/support"; return .handled }))
        capture(window, "signed-out-account-stage-one")
        try await wait(seconds: 150) { client.restoreCalls == 1 }
        XCTAssertNil(coordinator.membership.accountID)
        XCTAssertFalse(coordinator.membership.hasAccess)
        capture(window, "signed-out-restore")
        try await wait(seconds: 150) { supportOpened }
        try await wait(seconds: 150) { authorization.guardianCalls == 1 }
        try await Task.sleep(for: .seconds(30))
        capture(window, "retained-records-navigation")
        XCTAssertEqual(try Data(contentsOf: scope.file("profile.json")), original)
        XCTAssertFalse(account.trusted)
        XCTAssertNil(coordinator.workspace)
    }

    func testExternalJuniorSetupLargeType() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NativeProfileStore(url: root.appendingPathComponent("profile.json"))
        try store.save(LocalProfile(name: "Junior", programmePreferences: .init(goals: [.balance], weekdays: [1, 3, 5], startingPoint: .startingOut,
            ageContext: .init(ageYears: 10, guardianManaged: true),
            comfortAnswers: Dictionary(uniqueKeysWithValues: ExerciseFamily.allCases.map { ($0, TrainingSetup.Comfort.unsure) }))))
        let authorization = SetupRenderedAuthorization()
        let window = try host(OnboardingView(profileStore: store, guardianAuthorization: authorization)
            .environment(\.dynamicTypeSize, .accessibility2).transaction { $0.disablesAnimations = true })
        capture(window, "junior-large-type-body")
        try await wait(seconds: 240) { AccountPolicy.setupComplete(profile: store.profile) }
        XCTAssertEqual(authorization.guardianCalls, 1, "The optional measurement action requires a fresh guardian check")
        XCTAssertNil(store.profile?.bodyMeasurements)
        XCTAssertFalse(AccountPolicy.allowsHealth(profile: store.profile))
        XCTAssertFalse(store.profile?.trainingGoals.contains(.weightManagement) == true)
        capture(window, "junior-large-type-setup-complete")
    }

    func testExternalAdditionalPersonRequiresFreshAgeAndGuardian() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let accountID = UUID(), credentials = MemoryAccountCredentials(), transport = AccountTestTransport()
        try credentials.save(.init(session: NativeAccountSession(authenticated: true, accountID: accountID, appAccountToken: accountID,
            deviceID: UUID(), accessToken: "fixture", refreshToken: "fixture", accessExpiresAt: .now.addingTimeInterval(900), refreshExpiresAt: .now.addingTimeInterval(3600)),
            privateKey: P256.Signing.PrivateKey().rawRepresentation))
        transport.failure = URLError(.notConnectedToInternet)
        let authorization = SetupRenderedAuthorization()
        let account = NativeAccountStore(client: AccountClient(transport: transport), credentials: credentials, authorization: authorization)
        let coordinator = AccountWorkspaceCoordinator(account: account, root: root, membershipClient: SetupRenderedMembershipClient())
        await account.restore(); coordinator.accountChanged()
        let created = await coordinator.createProfile(name: "Adult", age: try .init(ageYears: 30, guardianManaged: false))
        XCTAssertTrue(created)
        let firstID = try XCTUnwrap(coordinator.directory?.selectedID)
        let window = try host(AccountSetupView(account: account, coordinator: coordinator))
        capture(window, "additional-person-fresh-age")
        try await wait(seconds: 180) { coordinator.directory?.profiles.count == 2 }
        XCTAssertEqual(coordinator.directory?.profiles.first(where: { $0.id == firstID })?.age.ageYears, 30)
        XCTAssertEqual(coordinator.visibleWorkspace?.profile.profile?.programmePreferences?.ageContext?.ageYears, 10)
        XCTAssertTrue(coordinator.visibleWorkspace?.profile.profile?.programmePreferences?.ageContext?.guardianManaged == true)
        XCTAssertEqual(authorization.guardianCalls, 1)
        XCTAssertFalse(AccountPolicy.setupComplete(profile: coordinator.visibleWorkspace?.profile.profile))
        capture(window, "additional-junior-created")
    }

    private func acceptedProfile() throws -> LocalProfile {
        try LocalProfile(name: "Adult", bodyMeasurements: .init(heightCM: 170, weightKG: 70), onboardingRevision: TrainingSetup.revision,
            programmePreferences: .init(goals: [.balance], weekdays: [1, 3, 5], startingPoint: .startingOut,
                ageContext: .init(ageYears: 30, guardianManaged: false),
                comfortAnswers: Dictionary(uniqueKeysWithValues: ExerciseFamily.allCases.map { ($0, TrainingSetup.Comfort.unsure) })))
    }
    private func host<Content: View>(_ view: Content) throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try XCTUnwrap(scene.windows.first { $0.isKeyWindow })
        priorKeyWindow = window; originalWindow = window
        originalController = window.rootViewController; originalHidden = window.isHidden; originalLevel = window.windowLevel
        window.rootViewController = UIHostingController(rootView: view); window.makeKeyAndVisible()
        return window
    }
    private func wait(seconds: Int = 90, until predicate: () -> Bool) async throws {
        for _ in 0..<(seconds * 5) {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(200))
        }
        XCTFail("The actual rendered public action did not reach its expected state")
        throw CocoaError(.userCancelled)
    }
    private func capture(_ window: UIWindow, _ name: String) {
        window.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        print("SETUP_RENDER_READY \(name) keyWindow \(window.isKeyWindow) interaction \(window.isUserInteractionEnabled) ignoring \(UIApplication.shared.isIgnoringInteractionEvents)")
    }
}

@MainActor private final class SetupRenderedMembershipClient: MembershipClient {
    var entitlements: [MembershipVerification] = []
    var restoreCalls = 0
    func products() async throws -> [MembershipOffer] { [] }
    func currentEntitlements() async -> [MembershipVerification] { entitlements }
    func updates() -> AsyncStream<MembershipVerification> { AsyncStream { $0.finish() } }
    func purchase(_ plan: MembershipPlan, appAccountToken: UUID) async throws -> MembershipPurchaseResult { .cancelled }
    func restore() async throws { restoreCalls += 1 }
    func finish(transactionID: UInt64) async {}
}

@MainActor private final class SetupRenderedAuthorization: NativeAccountAuthorization {
    var guardianCalls = 0
    func apple(nonce: String) async throws -> AppleIdentityResult { throw AccountFailure.cancelled }
    func register(options: PasskeyCreationOptions) async throws -> RegistrationCredential { throw AccountFailure.cancelled }
    func authenticate(options: PasskeyRequestOptions) async throws -> AssertionCredential { throw AccountFailure.cancelled }
    func guardian() async throws { guardianCalls += 1 }
}

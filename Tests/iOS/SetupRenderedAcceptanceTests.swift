import XCTest
import SwiftUI
import UIKit
import Observation
import CryptoKit
import Vision
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
    func testTrainingBodyKeepsPolicyDetailsCollapsedUntilRequested() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NativeProfileStore(url: root.appendingPathComponent("profile.json"))
        try store.save(acceptedProfile())
        let window = try host(OnboardingView(profileStore: store))
        try await Task.sleep(for: .milliseconds(450))
        let text = try trainingRenderedText(window, name: "training-body-ordinary")
        XCTAssertTrue(text.contains("heightandweight"), text)
        XCTAssertTrue(text.contains("profiledetails"), text)
        XCTAssertFalse(text.contains("yourlocalageanswer"), text)
    }

    func testTrainingPermissionsInitiallyShowsCoreRowsAndHidesVoiceOptions() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NativeProfileStore(url: root.appendingPathComponent("profile.json"))
        try store.save(acceptedProfile())
        let window = try host(NavigationStack {
            ScrollView { PhonePermissionsView(profileStore: store, healthStore: HealthDataStore()).padding(24) }
        })
        try await Task.sleep(for: .milliseconds(450))
        let text = try trainingRenderedText(window, name: "training-permissions-collapsed-ordinary")
        XCTAssertTrue(text.contains("camerasessions"), text)
        XCTAssertTrue(text.contains("voiceloggingandreminders"), text)
        XCTAssertTrue(text.contains("watchsetup"), text)
        XCTAssertFalse(text.contains("spokenloggingmicrophone"), text)
        XCTAssertFalse(text.contains("ondevicespeech"), text)
        XCTAssertFalse(text.contains("scheduledreminders"), text)
    }

    func testPermissionRenderReadsStatusesWithoutRequestingAccess() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let profile = NativeProfileStore(url: root.appendingPathComponent("profile.json"))
        try profile.save(acceptedProfile())
        let client = TrainingPermissionClient()
        let permissions = PhonePermissionStore(client: client)
        let healthClient = TrainingHealthClient()
        let health = HealthDataStore(client: healthClient, defaults: profile.preferencesDefaults)
        let window = try host(NavigationStack {
            ScrollView { PhonePermissionsView(profileStore: profile, healthStore: health, permissions: permissions).padding(24) }
        })
        try await Task.sleep(for: .milliseconds(450))
        XCTAssertEqual(permissions.camera, .denied)
        XCTAssertEqual(permissions.microphone, .allowed)
        XCTAssertEqual(permissions.speech, .unavailable)
        XCTAssertTrue(client.requests.isEmpty)
        XCTAssertEqual(healthClient.requests, 0)
        let text = try trainingRenderedText(window, name: "training-permission-statuses-without-request")
        XCTAssertTrue(text.contains("notallowed"), text)
        XCTAssertFalse(text.contains("spokenloggingmicrophone"), text)
    }

    func testExpandedVoiceOptionsShowStatusAndNeverRequestAccessOnExpansion() async throws {
        let client = TrainingPermissionClient()
        let permissions = PhonePermissionStore(client: client)
        await permissions.refresh()
        let window = try host(NavigationStack {
            ScrollView { VoiceLoggingPermissionDisclosure(permissions: permissions, isExpanded: .constant(true)).padding(24) }
        })
        try await Task.sleep(for: .milliseconds(450))
        let text = try trainingRenderedText(window, name: "training-permissions-expanded")
        XCTAssertTrue(text.contains("spokenloggingmicrophone"), text)
        XCTAssertTrue(text.contains("available"), text)
        XCTAssertTrue(text.contains("ondevicespeech"), text)
        XCTAssertTrue(text.contains("unavailable"), text)
        XCTAssertTrue(text.contains("scheduledreminders"), text)
        XCTAssertTrue(client.requests.isEmpty)
    }

    func testTrainingStageComponentsShowOnlyTheirChoicesAtOrdinaryAndAccessibilitySizes() async throws {
        let window = try host(Color.white)
        for size in [DynamicTypeSize.large, .accessibility2] {
            let suffix = size.isAccessibilitySize ? "accessibility2" : "ordinary"
            for step in [TrainingSetupPresentation.RhythmStep.goals, .schedule, .support] {
                let content = TrainingRhythmContent(step: step, goals: .constant([.strength]), weekdays: .constant([1, 3]),
                    minutes: .constant(20), hour: .constant(18), support: .constant([]), floor: .constant(true), adult: true)
                window.rootViewController = UIHostingController(rootView: NavigationStack {
                    ScrollView { content.padding(24) }.environment(\.dynamicTypeSize, size)
                })
                try await Task.sleep(for: .milliseconds(300))
                let text = try trainingRenderedText(window, name: "training-\(step.rawValue)-\(suffix)")
                switch step {
                case .goals:
                    XCTAssertTrue(text.contains("strength"), text)
                    XCTAssertFalse(text.contains("minutespersession"), text)
                    XCTAssertFalse(text.contains("floormovements"), text)
                case .schedule:
                    XCTAssertTrue(text.contains("minutespersession"), text)
                    XCTAssertFalse(text.contains("weightmanagement"), text)
                    XCTAssertFalse(text.contains("floormovements"), text)
                case .support:
                    XCTAssertTrue(text.contains("stablesupport"), text)
                    XCTAssertFalse(text.contains("minutespersession"), text)
                }
            }
            window.rootViewController = UIHostingController(rootView: NavigationStack {
                ScrollView { TrainingStartingPointChoices(selection: .constant(.somePractice)).padding(24) }
                    .environment(\.dynamicTypeSize, size)
            })
            try await Task.sleep(for: .milliseconds(300))
            let text = try trainingRenderedText(window, name: "training-starting-point-\(suffix)")
            XCTAssertTrue(text.contains("startingout"), text)
            if !size.isAccessibilitySize {
                XCTAssertTrue(text.contains("somepractice"), text)
                XCTAssertTrue(text.contains("regularpractice"), text)
                XCTAssertTrue(text.contains("experienced"), text)
            }
            let preferences = try ProgrammePreferences(goals: [.balance], weekdays: [1], ageContext: .init(ageYears: 30, guardianManaged: false))
            let choices = ExerciseCatalog.all.filter { $0.family == .legs && preferences.canUse($0) }
            window.rootViewController = UIHostingController(rootView: NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ScreenHeading(title: "Lower body")
                        TrainingComfortFamily(family: .legs, choices: choices, answer: nil, expanded: false, onExpand: {}, onAnswer: { _ in })
                    }.padding(24)
                }.environment(\.dynamicTypeSize, size)
            })
            try await Task.sleep(for: .milliseconds(300))
            let familyText = try trainingRenderedText(window, name: "training-one-family-\(suffix)")
            XCTAssertTrue(familyText.contains("lowerbody"), familyText)
            XCTAssertFalse(familyText.contains("conditioning"), familyText)
            XCTAssertFalse(familyText.contains("pushups"), familyText)
        }
    }

    func testTrainingPrivacyKeepsOptionalChoicesOffAndJuniorCollectionClosed() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let window = try host(Color.white)
        for years in [30, 10] {
            let scope = AccountDataScope(accountID: UUID(), profileID: UUID(), root: root)
            let profile = NativeProfileStore(url: scope.file("profile.json"))
            try profile.save(LocalProfile(programmePreferences: .init(goals: [.balance], weekdays: [1],
                ageContext: .init(ageYears: years, guardianManaged: years < 18))))
            var requests = 0
            let analytics = ConsentedAnalyticsStore(scope: scope, profile: profile, send: { _ in requests += 1; return 202 })
            window.rootViewController = UIHostingController(rootView: OnboardingView(profileStore: profile, analytics: analytics))
            try await Task.sleep(for: .milliseconds(350))
            let text = try trainingRenderedText(window, name: "training-privacy-age-\(years)")
            XCTAssertTrue(text.contains("privacypolicy"), text)
            XCTAssertTrue(text.contains("sharingdetails"), text)
            if years >= 18 {
                XCTAssertTrue(text.contains("sharefeatureusage"), text)
                XCTAssertTrue(text.contains("shareweeklyworkoutstatistics"), text)
            } else {
                XCTAssertTrue(text.contains("notcollected"), text)
                XCTAssertFalse(text.contains("sharefeatureusage"), text)
                XCTAssertFalse(text.contains("shareweeklyworkoutstatistics"), text)
            }
            XCTAssertFalse(analytics.ledger.usage)
            XCTAssertFalse(analytics.ledger.workout)
            XCTAssertEqual(requests, 0)
        }
    }

    func testJuniorTrainingBodyKeepsOptionalMeasurementsAndStickyContinueAtAccessibilitySize() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NativeProfileStore(url: root.appendingPathComponent("profile.json"))
        try store.save(LocalProfile(name: "Junior", programmePreferences: .init(goals: [.balance], weekdays: [1],
            ageContext: .init(ageYears: 10, guardianManaged: true))))
        let guardian = SetupRenderedAuthorization()
        let window = try host(OnboardingView(profileStore: store, guardianAuthorization: guardian)
            .environment(\.dynamicTypeSize, .accessibility2))
        try await Task.sleep(for: .milliseconds(350))
        let text = try trainingRenderedText(window, name: "training-junior-body-accessibility2")
        XCTAssertTrue(text.contains("measurementsareoptional"), text)
        XCTAssertTrue(text.contains("continue"), text)
        XCTAssertEqual(guardian.guardianCalls, 0)
        XCTAssertNil(store.profile?.bodyMeasurements)
        XCTAssertFalse(AccountPolicy.allowsHealth(profile: store.profile))
        XCTAssertFalse(store.profile?.trainingGoals.contains(.weightManagement) == true)
    }

    func testPreparedWeekKeepsFullMovementListInsideClosedWeekDisclosure() async throws {
        let date = Date(timeIntervalSince1970: 1_794_275_200)
        let plan = try CoachSavedPlan(items: [
            .init(exerciseID: "squat", sets: 1, target: 8, unit: .reps, restSeconds: 60),
            .init(exerciseID: "pushup", sets: 1, target: 8, unit: .reps, restSeconds: 60)
        ], availableSupport: [], createdAt: date, rationale: "A local prepared week")
        var days: [TrainingProgramme.Day] = []
        for index in 0..<7 {
            let dayDate = date.addingTimeInterval(TimeInterval(index) * 86400)
            let kind: TrainingProgramme.DayKind = index == 0 ? .workout : .rest
            let savedPlan: CoachSavedPlan? = index == 0 ? plan : nil
            let day = TrainingProgramme.Day(id: "day-\(index)", localDate: "day-\(index)", date: dayDate, kind: kind, plan: savedPlan)
            days.append(day)
        }
        let week = TrainingProgramme(id: "local-week", timeZoneID: "Europe/London", revision: 1, days: days)
        let window = try host(Color.white)
        for size in [DynamicTypeSize.large, .accessibility2] {
            window.rootViewController = UIHostingController(rootView: NavigationStack {
                ScrollView { TrainingWeekPreview(week: week).padding(24) }.environment(\.dynamicTypeSize, size)
            })
            try await Task.sleep(for: .milliseconds(350))
            let text = try trainingRenderedText(window, name: size.isAccessibilitySize ? "training-week-accessibility2" : "training-week-ordinary")
            XCTAssertTrue(text.contains("nextpractice"), text)
            XCTAssertTrue(text.contains("2movements"), text)
            XCTAssertTrue(text.contains("viewmyweek"), text)
            XCTAssertFalse(text.contains("pushups"), text)
        }
    }

    private func trainingRenderedText(_ window: UIWindow, name: String) throws -> String {
        window.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
        try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage)).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            .joined().lowercased().filter { $0.isLetter || $0.isNumber }
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
        try await Task.sleep(for: .seconds(15))
        capture(window, "account-sign-in-controls-review")
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

    func testExternalMonthlyMemberCanChooseLifetimeWithoutStartingPendingWorkout() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let scope = AccountDataScope(accountID: UUID(), profileID: UUID(), root: root)
        let workspace = try AccountWorkspace(scope: scope)
        try workspace.profile.save(acceptedProfile())
        let client = SetupRenderedMembershipClient()
        client.offers = [.init(plan: .monthly, displayName: "Monthly from Apple", displayPrice: "£6.49"),
                         .init(plan: .lifetime, displayName: "Lifetime from Apple", displayPrice: "£87.99")]
        let membership = MembershipCoordinator(client: client, claims: ProtectedMembershipClaimStore(root: root))
        membership.setAccount(scope.accountID)
        let generation = UUID()
        let launch = WorkoutLaunchCoordinator(training: workspace.training, profile: workspace.profile, membership: membership,
            owner: { .init(accountID: scope.accountID, profileID: scope.profileID) }, generation: { generation })
        workspace.training.launchCoordinator = launch
        workspace.training.startPlan(try .catalogue(exerciseID: "frontArmRaise", sets: 3, target: 10, restSeconds: 60), availableSupport: [])
        let pending = try XCTUnwrap(launch.pendingID)
        client.entitlements = [.verified(.init(id: 91, appAccountToken: scope.accountID, productID: MembershipPlan.monthly.productID,
            kind: .autoRenewable, expirationDate: .now.addingTimeInterval(86400)))]
        await membership.load()
        XCTAssertTrue(membership.access.mayPurchase(.lifetime))
        let window = try host(WorkoutLaunchAccessView(launch: launch))
        try await Task.sleep(for: .seconds(1))
        try await wait(seconds: 30) { self.renderedElements(window).contains { $0.accessibilityLabel == "Explore membership options" } }
        capture(window, "monthly-active-default")
        XCTAssertTrue(renderedElements(window).contains { $0.accessibilityLabel == "Explore membership options" })
        try await wait(seconds: 90) { self.renderedElements(window).contains { $0.accessibilityLabel?.contains("£87.99") == true } }
        XCTAssertTrue(renderedElements(window).contains { $0.accessibilityLabel?.contains("Lifetime from Apple") == true })
        XCTAssertTrue(renderedElements(window).contains { $0.accessibilityLabel?.contains("£87.99") == true })
        XCTAssertTrue(renderedElements(window).contains { $0.accessibilityLabel?.contains("Lifetime does not cancel") == true })
        capture(window, "monthly-lifetime-offer-visible")
        try await wait(seconds: 90) { client.purchases.count == 1 && !membership.busy }
        XCTAssertEqual(client.purchases.first?.0, .lifetime)
        XCTAssertEqual(client.purchases.first?.1, scope.accountID)
        XCTAssertTrue(membership.access.hasOverlappingSubscription)
        XCTAssertEqual(launch.pendingID, pending)
        XCTAssertEqual(workspace.training.sessionPhase, .idle)
        XCTAssertFalse(workspace.training.presented)
        XCTAssertGreaterThan(renderedElements(window).compactMap(\.accessibilityLabel).count, 5, "Absence checks require a populated rendered tree")
        XCTAssertFalse(renderedElements(window).contains { $0.accessibilityLabel == "Explore membership options" || $0.accessibilityLabel == "Hide membership options" || ($0 as? any UIAccessibilityIdentification)?.accessibilityIdentifier == "membershipOtherPlans" })
        XCTAssertFalse(renderedElements(window).contains { ($0 as? any UIAccessibilityIdentification)?.accessibilityIdentifier?.hasPrefix("membershipPurchase-") == true || $0.accessibilityLabel == "Buy lifetime membership" || $0.accessibilityLabel == "Subscribe monthly" })
        client.productsFail = true
        await membership.load()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(membership.hasAccess)
        XCTAssertTrue(renderedElements(window).contains { $0.accessibilityLabel == "Continue to workout" })
        XCTAssertFalse(renderedElements(window).contains { $0.accessibilityLabel == "Plans are temporarily unavailable" })
        capture(window, "lifetime-overlap-offline-pending-preserved")
    }

    func testExternalJuniorOnboardingWatchLinksRequireCurrentGuardianApproval() async throws {
        let originalWatchModel = UserDefaults.standard.object(forKey: "Spottr.watch-model")
        defer {
            if let originalWatchModel { UserDefaults.standard.set(originalWatchModel, forKey: "Spottr.watch-model") }
            else { UserDefaults.standard.removeObject(forKey: "Spottr.watch-model") }
            XCTAssertEqual(UserDefaults.standard.string(forKey: "Spottr.watch-model"), originalWatchModel as? String)
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NativeProfileStore(url: root.appendingPathComponent("profile.json"))
        try store.save(LocalProfile(name: "Junior", onboardingRevision: 2, programmePreferences: .init(goals: [.balance], weekdays: [1], startingPoint: .startingOut,
            ageContext: .init(ageYears: 12, guardianManaged: true),
            comfortAnswers: Dictionary(uniqueKeysWithValues: ExerciseFamily.allCases.map { ($0, TrainingSetup.Comfort.unsure) }))))
        let authorization = SetupRenderedAuthorization()
        authorization.guardianAllowed = false
        var opened: [URL] = []
        let window = try host(OnboardingView(profileStore: store, guardianAuthorization: authorization)
            .environment(\.openURL, OpenURLAction { opened.append($0); return .handled }))
        capture(window, "junior-revision-watch-link-gate")
        try await wait(seconds: 120) { authorization.guardianCalls >= 1 || !opened.isEmpty }
        XCTAssertEqual(authorization.guardianCalls, 1, "The actual Watch link must request guardian authorization")
        XCTAssertTrue(opened.isEmpty, "Denied authorization must not open TestFlight")
        guard authorization.guardianCalls == 1, opened.isEmpty else { throw CocoaError(.userCancelled) }
        print("LINK_GATE_DENIED_TESTFLIGHT")
        try await wait { authorization.guardianCalls == 2 }
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(opened.isEmpty, "Denied authorization must not open Apple support")
        authorization.guardianAllowed = true
        print("LINK_GATE_ALLOW_BOTH")
        try await wait { opened.count == 2 }
        XCTAssertEqual(opened.map(\.absoluteString), ["https://testflight.apple.com/join/f3MhePbf", "https://support.apple.com/guide/watch/get-apps-apd99e3c6a68/watchos"])
        XCTAssertEqual(authorization.guardianCalls, 4)
        authorization.holdGuardian = true
        print("LINK_GATE_STALE_NEXT")
        try await wait { authorization.pendingGuardian != nil }
        store.invalidatePolicy()
        authorization.pendingGuardian?.resume(); authorization.pendingGuardian = nil
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(opened.count, 2, "Retired junior policy must not open a website after a late approval")
        XCTAssertEqual(authorization.guardianCalls, 5)
        capture(window, "junior-watch-stale-approval-blocked")
    }

    private func renderedElements(_ root: NSObject) -> [NSObject] {
        var result: [NSObject] = []; var seen = Set<ObjectIdentifier>()
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
    var offers: [MembershipOffer] = []
    var productsFail = false
    var purchases: [(MembershipPlan, UUID)] = []
    func products() async throws -> [MembershipOffer] { if productsFail { throw URLError(.notConnectedToInternet) }; return offers }
    func currentEntitlements() async -> [MembershipVerification] { entitlements }
    func updates() -> AsyncStream<MembershipVerification> { AsyncStream { $0.finish() } }
    func purchase(_ plan: MembershipPlan, appAccountToken: UUID) async throws -> MembershipPurchaseResult {
        purchases.append((plan, appAccountToken))
        let transaction = MembershipTransaction(id: 92, appAccountToken: appAccountToken, productID: plan.productID, kind: plan.kind)
        entitlements.append(.verified(transaction))
        return .completed(.verified(transaction))
    }
    func restore() async throws { restoreCalls += 1 }
    func finish(transactionID: UInt64) async {}
}

@MainActor private final class SetupRenderedAuthorization: NativeAccountAuthorization {
    var guardianCalls = 0
    var guardianAllowed = true
    var holdGuardian = false
    var pendingGuardian: CheckedContinuation<Void, Never>?
    func apple(nonce: String) async throws -> AppleIdentityResult { throw AccountFailure.cancelled }
    func register(options: PasskeyCreationOptions) async throws -> RegistrationCredential { throw AccountFailure.cancelled }
    func authenticate(options: PasskeyRequestOptions) async throws -> AssertionCredential { throw AccountFailure.cancelled }
    func guardian() async throws {
        guardianCalls += 1
        if holdGuardian { await withCheckedContinuation { pendingGuardian = $0 } }
        guard guardianAllowed else { throw AccountFailure.cancelled }
    }
}

@MainActor private final class TrainingPermissionClient: PhonePermissionClient {
    var requests: [PhonePermissionFeature] = []
    func status(_ feature: PhonePermissionFeature) async -> PhonePermissionState {
        switch feature {
        case .camera: .denied
        case .microphone: .allowed
        case .speech: .unavailable
        case .notifications: .notRequested
        }
    }
    func request(_ feature: PhonePermissionFeature) async { requests.append(feature) }
}
@MainActor private final class TrainingHealthClient: HealthReadingClient {
    var isAvailable = true
    var requests = 0
    func requestReadAuthorization() async throws { requests += 1 }
    func read(asOf: Date, dayStart: Date, dayEnd: Date) async throws -> [HealthObservation] { [] }
}

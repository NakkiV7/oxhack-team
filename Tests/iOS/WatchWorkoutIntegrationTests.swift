import XCTest
import SwiftUI
import CryptoKit
@testable import Spottr

@MainActor final class WatchWorkoutIntegrationTests: XCTestCase {
    func testSharingIsExplicitAndScopedAndPolicyReplacementDoesNotInheritConsent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let adult = try TrainingAgeContext(ageYears: 30, guardianManaged: false)
        let scope = AccountDataScope(accountID: UUID(), profileID: UUID(), root: root)
        let store = try WatchSharingStore(scope: scope, age: adult)
        XCTAssertFalse(store.enabled)
        try store.setEnabled(true)
        XCTAssertTrue(store.enabled)
        let reopened = try WatchSharingStore(scope: scope, age: adult)
        XCTAssertTrue(reopened.enabled); XCTAssertEqual(reopened.policyID, store.policyID)
        let other = try WatchSharingStore(scope: .init(accountID: scope.accountID, profileID: UUID(), root: root), age: adult)
        XCTAssertFalse(other.enabled)
        let corrected = try WatchSharingStore(scope: scope, age: TrainingAgeContext(ageYears: 12, guardianManaged: true))
        XCTAssertFalse(corrected.enabled); XCTAssertNotEqual(corrected.policyID, store.policyID)
        try corrected.setEnabled(false)
        XCTAssertFalse(try WatchSharingStore(scope: scope, age: TrainingAgeContext(ageYears: 12, guardianManaged: true)).enabled)
    }
    func testWatchImportIsDurableIdempotentAndDeletedWorkCannotReturnAfterLostAck() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let scope = AccountDataScope(accountID: UUID(), profileID: UUID(), root: root)
        try scope.prepare()
        let training = TrainingStore(historyURL: scope.file("history.json"), accountScope: scope)
        let date = Date().addingTimeInterval(-100)
        let grant = WatchAccessGrant(owner: .init(accountID: scope.accountID, profileID: scope.profileID), policyID: UUID(), age: try TrainingAgeContext(ageYears: 30, guardianManaged: false), verifiedAt: date, membershipDeadline: nil)
        var journal = try WatchWorkoutJournal(grant: grant, plan: .catalogue(exerciseID: "squat", sets: 2, target: 8, restSeconds: 60), support: [], plannedWorkoutID: nil, at: date)
        try journal.beginSet(); try journal.setReps(3); journal.advance(seconds: 4); try journal.endSet(); try journal.effort(.hard); journal.finish(at: date.addingTimeInterval(40))
        XCTAssertTrue(try training.importWatchWorkout(journal))
        XCTAssertEqual(training.history.count, 1)
        XCTAssertEqual(training.history.first?.loggedSets.first?.reps, 3)
        XCTAssertEqual(training.history.first?.loggedSets.first?.effort, .hard)
        XCTAssertEqual(training.history.first?.trainingContext?.owner, grant.owner)
        XCTAssertTrue(try training.importWatchWorkout(journal))
        XCTAssertEqual(training.history.count, 1)
        let reopened = TrainingStore(historyURL: scope.file("history.json"), accountScope: scope)
        XCTAssertTrue(try reopened.importWatchWorkout(journal)); XCTAssertEqual(reopened.history.count, 1)
        try reopened.clearHistory()
        XCTAssertTrue(try reopened.importWatchWorkout(journal)); XCTAssertTrue(reopened.history.isEmpty)
        let other = AccountDataScope(accountID: scope.accountID, profileID: UUID(), root: root)
        let wrongOwner = TrainingStore(historyURL: other.file("history.json"), accountScope: other)
        XCTAssertThrowsError(try wrongOwner.importWatchWorkout(journal))
        XCTAssertTrue(wrongOwner.history.isEmpty)
    }
    func testFailedRewardSaveNeverAcknowledgesAndRetryRepairsSavedHistoryBeforeAck() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let scope = AccountDataScope(accountID: UUID(), profileID: UUID(), root: root)
        try scope.prepare()
        try Data("broken rewards".utf8).write(to: scope.file("rewards.json"))
        let date = Date().addingTimeInterval(-100)
        let grant = WatchAccessGrant(owner: .init(accountID: scope.accountID, profileID: scope.profileID), policyID: UUID(), age: try TrainingAgeContext(ageYears: 30, guardianManaged: false), verifiedAt: date, membershipDeadline: nil)
        var journal = try WatchWorkoutJournal(grant: grant, plan: .catalogue(exerciseID: "squat", sets: 1, target: 8, restSeconds: 60), support: [], plannedWorkoutID: nil, at: date)
        try journal.beginSet(); try journal.setReps(3); journal.advance(seconds: 2); try journal.endSet(); journal.finish(at: date.addingTimeInterval(40))
        let first = TrainingStore(historyURL: scope.file("history.json"), accountScope: scope)
        XCTAssertThrowsError(try first.importWatchWorkout(journal))
        XCTAssertEqual(try HistoryStore(url: scope.file("history.json")).load().map(\.id), [journal.id])
        XCTAssertEqual(try String(contentsOf: scope.file("rewards.json"), encoding: .utf8), "broken rewards")
        try FileManager.default.removeItem(at: scope.file("rewards.json"))
        let retry = TrainingStore(historyURL: scope.file("history.json"), accountScope: scope)
        XCTAssertTrue(try retry.importWatchWorkout(journal))
        XCTAssertEqual(retry.history.count, 1)
        XCTAssertTrue(try retry.importWatchWorkout(journal))
        XCTAssertEqual(retry.history.count, 1)
    }
    func testLateWatchAwardUsesCompletionLocalCalendar() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let scope = AccountDataScope(accountID: UUID(), profileID: UUID(), root: root)
        try scope.prepare()
        var london = Calendar(identifier: .gregorian); london.timeZone = TimeZone(identifier: "Europe/London")!
        let newYork = TimeZone(identifier: "America/New_York")!
        let created = ISO8601DateFormatter().date(from: "2026-11-01T00:00:00Z")!
        let start = ISO8601DateFormatter().date(from: "2026-11-03T15:29:00Z")!
        let rewards = NativeRewardsStore(url: scope.file("rewards.json"), createdAt: created, calendar: london)
        try rewards.schedule(startHour: 10, at: created, calendar: london)
        let grant = WatchAccessGrant(owner: .init(accountID: scope.accountID, profileID: scope.profileID), policyID: UUID(), age: try TrainingAgeContext(ageYears: 30, guardianManaged: false), verifiedAt: created, membershipDeadline: nil)
        let support = Set([try XCTUnwrap(ExerciseCatalog.find("wallPushup")?.support)])
        var journal = try WatchWorkoutJournal(grant: grant, plan: .catalogue(exerciseID: "wallPushup", sets: 1, target: 20, restSeconds: 60, availableSupport: support), support: support, plannedWorkoutID: nil, at: start, timeZone: london.timeZone)
        try journal.beginSet(); try journal.setReps(20); journal.advance(seconds: 30); try journal.endSet(); journal.finish(at: start.addingTimeInterval(60), timeZone: newYork)
        let training = TrainingStore(historyURL: scope.file("history.json"), rewardsStore: rewards, accountScope: scope)
        XCTAssertTrue(try training.importWatchWorkout(journal))
        XCTAssertGreaterThan(rewards.ledger.totalBonusXP, 0)
        XCTAssertEqual(rewards.ledger.events.first?.completedAt, start.addingTimeInterval(60))
        let bonus = rewards.ledger.totalBonusXP
        XCTAssertTrue(try training.importWatchWorkout(journal)); XCTAssertEqual(rewards.ledger.totalBonusXP, bonus)
    }
    func testRenderedSharingStaysOffForNewProfileWithExistingModelChoice() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let namespace = ProcessInfo.processInfo.environment["SPOTTR_DATA_NAMESPACE"].flatMap(UUID.init(uuidString:))
        let defaults = namespace.flatMap { UserDefaults(suiteName: "Spottr.Watch.\($0.uuidString)") } ?? .standard
        let original = defaults.object(forKey: "Spottr.watch-model")
        defer { if let original { defaults.set(original, forKey: "Spottr.watch-model") } else { defaults.removeObject(forKey: "Spottr.watch-model") } }
        defaults.set(WatchModelPreference.se.rawValue, forKey: "Spottr.watch-model")
        let scope = AccountDataScope(accountID: UUID(), profileID: UUID(), root: root)
        let age = try TrainingAgeContext(ageYears: 30, guardianManaged: false)
        let sharing = try WatchSharingStore(scope: scope, age: age)
        let profile = NativeProfileStore(url: scope.file("profile.json"))
        try profile.save(LocalProfile(programmePreferences: ProgrammePreferences(goals: [.balance], weekdays: [1], ageContext: age)))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try XCTUnwrap(scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first)
        let controller = window.rootViewController, hidden = window.isHidden, level = window.windowLevel
        defer { window.rootViewController = controller; window.isHidden = hidden; window.windowLevel = level }
        window.rootViewController = UIHostingController(rootView: NavigationStack { WatchSetupView() }
            .environment(\.watchSharing, sharing).environment(\.profileWebsiteAccess, ProfileWebsiteAccess(profile: profile, guardian: nil)))
        window.makeKeyAndVisible()
        try await Task.sleep(for: .milliseconds(600))
        window.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = "watch-sharing-new-profile-off"; attachment.lifetime = .keepAlways; add(attachment)
        XCTAssertFalse(sharing.enabled)
        XCTAssertEqual(defaults.string(forKey: "Spottr.watch-model"), WatchModelPreference.se.rawValue)
    }
    func testProductionModelSelectionPreservesExplicitOffAndOnlyToggleEnablesSharing() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "WatchConsentTest." + UUID().uuidString))
        defer { defaults.removeObject(forKey: "Spottr.watch-model") }
        let store = WatchSetupStore(defaults: defaults, observe: { .init() }, request: {})
        let sharing = try WatchSharingStore(scope: .init(accountID: UUID(), profileID: UUID(), root: root), age: .init(ageYears: 30, guardianManaged: false))
        try WatchSetupView.selectModel(.se, store: store, sharing: sharing)
        XCTAssertFalse(sharing.enabled)
        try WatchSetupView.selectModel(.notSure, store: store, sharing: sharing)
        XCTAssertFalse(sharing.enabled)
        try sharing.setEnabled(true)
        try WatchSetupView.selectModel(.se, store: store, sharing: sharing)
        XCTAssertTrue(sharing.enabled)
        try WatchSetupView.selectModel(.noWatch, store: store, sharing: sharing)
        XCTAssertFalse(sharing.enabled)
        XCTAssertEqual(store.selectedModel, .noWatch)
    }
    func testFailedClearIntentCannotAcknowledgeUntilDeletionAndRewardsRecoverAfterRestart() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let scope = AccountDataScope(accountID: UUID(), profileID: UUID(), root: root)
        let locked = scope.file("watch-inbox.json").appendingPathComponent("locked")
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path); try? FileManager.default.removeItem(at: root) }
        try scope.prepare()
        try Data("broken rewards".utf8).write(to: scope.file("rewards.json"))
        let date = Date().addingTimeInterval(-100)
        let grant = WatchAccessGrant(owner: .init(accountID: scope.accountID, profileID: scope.profileID), policyID: UUID(), age: try .init(ageYears: 30, guardianManaged: false), verifiedAt: date, membershipDeadline: nil)
        var journal = try WatchWorkoutJournal(grant: grant, plan: .catalogue(exerciseID: "squat", sets: 1, target: 8, restSeconds: 30), support: [], plannedWorkoutID: nil, at: date)
        try journal.beginSet(); try journal.setReps(3); try journal.endSet(); journal.finish(at: date.addingTimeInterval(10))
        let store = TrainingStore(historyURL: scope.file("history.json"), accountScope: scope)
        XCTAssertThrowsError(try store.importWatchWorkout(journal))
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try Data("blocked removal".utf8).write(to: locked.appendingPathComponent("child"))
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        XCTAssertThrowsError(try store.clearHistory())
        XCTAssertEqual(try HistoryStore(url: scope.file("history.json")).load().map(\.id), [journal.id])
        let reopened = TrainingStore(historyURL: scope.file("history.json"), accountScope: scope)
        XCTAssertThrowsError(try reopened.importWatchWorkout(journal), "Incomplete deletion must not authorize ACK")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
        XCTAssertTrue(try reopened.importWatchWorkout(journal))
        XCTAssertTrue(try HistoryStore(url: scope.file("history.json")).load().isEmpty)
        XCTAssertTrue(reopened.rewards.ledger.events.isEmpty)
        XCTAssertNil(reopened.rewards.loadError)
        XCTAssertTrue(try TrainingStore(historyURL: scope.file("history.json"), accountScope: scope).importWatchWorkout(journal))
        XCTAssertTrue(try HistoryStore(url: scope.file("history.json")).load().isEmpty)
    }

    func testDeletionIntentRecoversAfterHistoryRemovalBeforeRewardSaveWithoutDeletingNewerWork() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let scope = AccountDataScope(accountID: UUID(), profileID: UUID(), root: root)
        let rewardFolder = root.appendingPathComponent("reward-store"), rewardURL = rewardFolder.appendingPathComponent("rewards.json")
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: rewardFolder.path); try? FileManager.default.removeItem(at: root) }
        try scope.prepare()
        let date = Date().addingTimeInterval(-100)
        let rewards = NativeRewardsStore(url: rewardURL, createdAt: date.addingTimeInterval(-1000))
        try rewards.schedule(startHour: 10, at: date.addingTimeInterval(-1000))
        let grant = WatchAccessGrant(owner: .init(accountID: scope.accountID, profileID: scope.profileID), policyID: UUID(), age: try .init(ageYears: 30, guardianManaged: false), verifiedAt: date, membershipDeadline: nil)
        var journal = try WatchWorkoutJournal(grant: grant, plan: .catalogue(exerciseID: "squat", sets: 1, target: 8, restSeconds: 30), support: [], plannedWorkoutID: nil, at: date)
        try journal.beginSet(); try journal.setReps(3); try journal.endSet(); journal.finish(at: date.addingTimeInterval(10))
        let store = TrainingStore(historyURL: scope.file("history.json"), rewardsStore: rewards, accountScope: scope)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: rewardFolder.path)
        XCTAssertThrowsError(try store.importWatchWorkout(journal))
        XCTAssertThrowsError(try store.clearHistory())
        XCTAssertTrue(try HistoryStore(url: scope.file("history.json")).load().isEmpty)
        let retryRewards = NativeRewardsStore(url: rewardURL)
        let reopened = TrainingStore(historyURL: scope.file("history.json"), rewardsStore: retryRewards, accountScope: scope)
        XCTAssertThrowsError(try reopened.importWatchWorkout(journal), "Reward deletion is still not durable")
        let newer = try LoggedWorkout.make(exerciseID: "squat", count: 3, sets: 1, date: Date())
        try HistoryStore(url: scope.file("history.json")).save(newer)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: rewardFolder.path)
        XCTAssertTrue(try reopened.importWatchWorkout(journal))
        XCTAssertEqual(try HistoryStore(url: scope.file("history.json")).load().map(\.id), [newer.id])
        XCTAssertTrue(retryRewards.ledger.events.isEmpty)
        XCTAssertTrue(try reopened.importWatchWorkout(journal))
        XCTAssertEqual(try HistoryStore(url: scope.file("history.json")).load().map(\.id), [newer.id])
    }

    func testNoWatchWriteFailureImmediatelyWithdrawsRealBridgeAuthorityAndRejectsLateSensors() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var folder: URL?
        defer { if let folder { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }; try? FileManager.default.removeItem(at: root) }
        let accountID = UUID(), wire = AccountTestTransport(), vault = MemoryAccountCredentials()
        try vault.save(.init(session: .init(authenticated: true, accountID: accountID, appAccountToken: accountID, deviceID: UUID(), accessToken: "access", refreshToken: "refresh", accessExpiresAt: Date().addingTimeInterval(900), refreshExpiresAt: Date().addingTimeInterval(86400)), privateKey: P256.Signing.PrivateKey().rawRepresentation, lastTrustedVerification: Date()))
        wire.failure = URLError(.notConnectedToInternet)
        let account = NativeAccountStore(client: AccountClient(transport: wire), credentials: vault, authorization: AccountTestAuthorization())
        await account.restore()
        let client = WatchConsentMembershipClient(accountID: accountID)
        let coordinator = AccountWorkspaceCoordinator(account: account, root: root, membershipClient: client)
        coordinator.accountChanged()
        let age = try TrainingAgeContext(ageYears: 30, guardianManaged: false)
        await coordinator.createProfile(name: "Consent failure", age: age)
        let workspace = try XCTUnwrap(coordinator.visibleWorkspace)
        folder = workspace.scope.file("watch-sharing.json").deletingLastPathComponent()
        try workspace.profile.save(.init(bodyMeasurements: .init(heightCM: 170, weightKG: 70), onboardingRevision: TrainingSetup.revision, programmePreferences: .init(goals: [.balance], weekdays: Set(1...7), startingPoint: .startingOut, ageContext: age, comfortAnswers: Dictionary(uniqueKeysWithValues: ExerciseFamily.allCases.map { ($0, TrainingSetup.Comfort.unsure) }))))
        _ = try workspace.programme.prepare(profile: try XCTUnwrap(workspace.profile.profile), history: [])
        await coordinator.membership.refreshEntitlements()
        XCTAssertTrue(account.trusted, "Fixture must have canonical trusted account")
        XCTAssertNotNil(account.lastTrustedVerification, "Fixture must have retained genuine-verification metadata")
        XCTAssertTrue(AccountPolicy.setupComplete(profile: workspace.profile.profile), "Fixture must satisfy real adult setup gate")
        XCTAssertTrue(coordinator.membership.hasAccess, "Fixture must have verified owner-bound membership")
        try workspace.watchSharing.setEnabled(true)
        let bridge = try XCTUnwrap(workspace.watchBridge)
        workspace.training.publish()
        let initialGrant = try XCTUnwrap(bridge.lastTransport?.grant, "Fixture must publish a valid complete programme before testing OFF")
        XCTAssertEqual(initialGrant.owner, workspace.watchSharing.owner)
        XCTAssertTrue(initialGrant.permitsStart(at: Date()))
        let plan = try CoachSavedPlan.catalogue(exerciseID: "frontArmRaise", sets: 1, target: 6, restSeconds: 30)
        workspace.launch?.request(plan: plan, origin: .coach)
        workspace.training.beginConfiguredSet(); workspace.training.setConfiguredReps(3)
        let active = try XCTUnwrap(workspace.training.configured, "Fixture must pass the canonical launch gate")
        XCTAssertEqual(active.manualReps, 3, "Fixture must retain actual manual work before opt-out")
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "WatchOffFailure." + UUID().uuidString))
        defer { defaults.removeObject(forKey: "Spottr.watch-model") }
        let setup = WatchSetupStore(defaults: defaults, observe: { .init() }, request: {})
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder!.path)
        XCTAssertThrowsError(try WatchSetupView.selectModel(.noWatch, store: setup, sharing: workspace.watchSharing))
        XCTAssertFalse(workspace.watchSharing.enabled)
        XCTAssertFalse(try WatchSharingStore(scope: workspace.scope, age: age).enabled, "Same-owner reconstruction cannot reopen a known unsaved OFF choice")
        workspace.training.publish()
        XCTAssertEqual(bridge.lastTransport?.sharing, false)
        XCTAssertNil(bridge.lastTransport?.grant)
        let measured = Date()
        workspace.training.companion.onTelemetry?(.init(sessionID: active.id, sentAt: measured, heartRate: .init(value: 80, date: measured), accelerationG: nil, rotationRadiansPerSecond: nil))
        for _ in 0..<100 { await Task.yield() }
        XCTAssertTrue(workspace.training.configured?.record.telemetry.isEmpty == true)
        XCTAssertEqual(workspace.training.configured?.id, active.id)
        XCTAssertEqual(workspace.training.configured?.manualReps, 3)
        XCTAssertEqual(workspace.training.configured?.trainingContext?.owner, workspace.watchSharing.owner)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder!.path)
        workspace.training.publish()
        XCTAssertFalse(try WatchSharingStore(scope: workspace.scope, age: age).enabled)
    }

}

@MainActor private final class WatchConsentMembershipClient: MembershipClient {
    let accountID: UUID
    init(accountID: UUID) { self.accountID = accountID }
    func products() async throws -> [MembershipOffer] { [] }
    func currentEntitlements() async -> [MembershipVerification] { [.verified(.init(appAccountToken: accountID, productID: MembershipPlan.lifetime.productID, kind: .nonConsumable))] }
    func updates() -> AsyncStream<MembershipVerification> { AsyncStream { $0.finish() } }
    func purchase(_ plan: MembershipPlan, appAccountToken: UUID) async throws -> MembershipPurchaseResult { .cancelled }
    func restore() async throws {}
    func finish(transactionID: UInt64) async {}
}

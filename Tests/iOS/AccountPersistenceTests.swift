import XCTest
import CryptoKit
@testable import Spottr

@MainActor final class AccountPersistenceTests: XCTestCase {
    func testRestoredMembershipClaimUsesProtectedAccountRootAcrossTrustedReconstruction() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID(), vault = MemoryAccountCredentials(), wire = AccountTestTransport()
        try vault.save(.init(session: NativeAccountSession(authenticated: true, accountID: id, appAccountToken: id, deviceID: UUID(), accessToken: "access", refreshToken: "refresh", accessExpiresAt: .now.addingTimeInterval(900), refreshExpiresAt: .now.addingTimeInterval(86400)), privateKey: P256.Signing.PrivateKey().rawRepresentation))
        wire.failure = URLError(.notConnectedToInternet)
        func account() -> NativeAccountStore {
            NativeAccountStore(client: AccountClient(transport: wire), credentials: vault, authorization: AccountTestAuthorization())
        }
        let apple = ClaimMembershipClient()
        let first = AccountWorkspaceCoordinator(account: account(), root: root, membershipClient: apple)
        await first.account.restore(); first.accountChanged()
        XCTAssertTrue(first.account.trusted)
        await first.membership.restore()
        XCTAssertTrue(first.membership.hasAccess)
        let file = root.appendingPathComponent("Accounts/\(id.uuidString)/membership-claims.json")
        XCTAssertTrue(try file.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        XCTAssertTrue(try file.deletingLastPathComponent().resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        #if !targetEnvironment(simulator)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: file.path)[.protectionKey] as? FileProtectionType, .completeUntilFirstUserAuthentication)
        #endif
        let returned = AccountWorkspaceCoordinator(account: account(), root: root, membershipClient: apple)
        await returned.account.restore(); returned.accountChanged()
        XCTAssertTrue(returned.account.trusted)
        XCTAssertFalse(returned.membership.hasAccess)
        await returned.membership.load()
        XCTAssertTrue(returned.membership.hasAccess)
        XCTAssertEqual(apple.restores, 1)
        let differentRoot = root.appendingPathComponent("separate-install-namespace")
        let separate = AccountWorkspaceCoordinator(account: account(), root: differentRoot, membershipClient: apple)
        await separate.account.restore(); separate.accountChanged()
        await separate.membership.load()
        XCTAssertFalse(separate.membership.hasAccess)
        apple.entitlements = []
        await returned.membership.load()
        XCTAssertFalse(returned.membership.hasAccess)
    }

    func testMeasurementAndProfileEditsPreserveAgeAndProgrammePreferences() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NativeProfileStore(url: root.appendingPathComponent("profile.json"))
        let preferences = try ProgrammePreferences(goals: [.balance], weekdays: [2, 5], ageContext: TrainingAgeContext(ageYears: 12, guardianManaged: true))
        try store.save(LocalProfile(programmePreferences: preferences))
        try store.saveMeasurements(LocalBodyMeasurements(heightCM: 150, weightKG: 45))
        XCTAssertEqual(store.profile?.programmePreferences, preferences)
        XCTAssertTrue(ProfileDraftPersistence(store: store).save(name: "Local", weeklyTarget: 3, goals: [.mobility]))
        XCTAssertEqual(store.profile?.programmePreferences, preferences)
    }

    func testMeasurementPreviewNeverUsesAdultBandsForUnknownOrJuniorAge() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let profile = NativeProfileStore(url: root.appendingPathComponent("profile.json"))
        let measurements = try LocalBodyMeasurements(heightCM: 150, weightKG: 45, bmiEligible: true, thresholds: .standard)
        XCTAssertNil(try profile.assessment(for: measurements).value)
        let prefs = try ProgrammePreferences(goals: [.balance], weekdays: [1], ageContext: TrainingAgeContext(ageYears: 12, guardianManaged: true))
        try profile.save(LocalProfile(programmePreferences: prefs))
        XCTAssertNotNil(try profile.assessment(for: measurements).value)
        XCTAssertNil(try profile.assessment(for: measurements).adultCategory)
        XCTAssertNil(try profile.assessment(for: measurements).adultReference)
    }

    func testJuniorRewardsNeverScheduleOrAwardTimePressureBonus() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let rewards = NativeRewardsStore(url: root.appendingPathComponent("rewards.json"), allowsTimePressureRewards: false)
        XCTAssertThrowsError(try rewards.schedule(startHour: 10, at: .now))
        let record = try LoggedWorkout.make(exerciseID: "wallPushup", count: 20, sets: 1)
        try rewards.award(record: record, before: [], history: [record], completedAt: .now)
        XCTAssertTrue(rewards.ledger.events.isEmpty)
        XCTAssertEqual(rewards.ledger.totalBonusXP, 0)
        XCTAssertEqual(rewards.totalXP(history: [record]), 10)
    }

    func testProtectedLocalArchivesRemainExportableWithoutOnlineCredentials() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let scope = AccountDataScope(accountID: UUID(), profileID: UUID(), root: root)
        try scope.prepare()
        let record = try LoggedWorkout.make(exerciseID: "wallPushup", count: 4, sets: 1)
        try HistoryStore(url: scope.file("history.json")).save(record)
        XCTAssertEqual(try AccountLocalArchives.scopes(root: root), [scope])
        let exported = try scope.exportLocalData()
        defer { try? FileManager.default.removeItem(at: exported.deletingLastPathComponent()) }
        let archive = try JSONDecoder().decode(AccountLocalExport.self, from: Data(contentsOf: exported))
        XCTAssertEqual(archive.accountID, scope.accountID)
        XCTAssertEqual(archive.profileID, scope.profileID)
        XCTAssertEqual(archive.history, [record])
        XCTAssertEqual(try HistoryStore(url: scope.file("history.json")).load(), [record])
    }

    func testOpeningAccountCoordinatorProtectsLegacyContainerWithoutReplacingFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let original = Data("unreadable original must survive".utf8)
        let file = root.appendingPathComponent("profile.json")
        try original.write(to: file)
        _ = AccountWorkspaceCoordinator(root: root)
        XCTAssertEqual(try Data(contentsOf: file), original)
        XCTAssertTrue(try root.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        XCTAssertTrue(try file.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }

    func testPhysicalDeviceProtectionClassReadback() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Simulator does not expose iOS data-protection classes. Physical-device readback remains required.")
        #else
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let scope = AccountDataScope(accountID: UUID(), profileID: UUID(), root: root)
        try scope.prepare()
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: scope.folder.path)[.protectionKey] as? FileProtectionType, .completeUntilFirstUserAuthentication)
        #endif
    }

    func testScopeKeepsHealthPreferencesAndPendingWorkoutInProtectedFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let a = AccountDataScope(accountID: UUID(), profileID: UUID(), root: root)
        let b = AccountDataScope(accountID: a.accountID, profileID: UUID(), root: root)
        try a.prepare(); try b.prepare()
        let preferences = try FileHealthPreferences(url: a.file("health-preferences.plist"))
        preferences.set(180.0, forKey: "health.zoneMaximum")
        XCTAssertEqual(try FileHealthPreferences(url: a.file("health-preferences.plist")).double(forKey: "health.zoneMaximum"), 180)
        XCTAssertEqual(try FileHealthPreferences(url: b.file("health-preferences.plist")).double(forKey: "health.zoneMaximum"), 0)
        XCTAssertTrue(try a.file("health-preferences.plist").resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        let training = TrainingStore(historyURL: a.file("history.json"), accountScope: a)
        training.beginAuthorizedSession()
        training.pause()
        try training.preservePendingWorkout()
        let saved = try JSONDecoder().decode(PendingPhoneWorkout.self, from: Data(contentsOf: a.file("pending-phone-workout.json")))
        XCTAssertEqual(saved.accountID, a.accountID)
        XCTAssertEqual(saved.profileID, a.profileID)
        XCTAssertEqual(saved.record.id, training.session.id)
        XCTAssertEqual(saved.actualReps, training.session.actualReps)
        XCTAssertTrue(training.history.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: b.file("pending-phone-workout.json").path))
    }

    func testExplicitLegacyImportPreservesOriginalAndNeverAssignsAdultHistoryToChild() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let original = try JSONEncoder().encode([LoggedWorkout.make(exerciseID: "wallPushup", count: 4, sets: 1)])
        try original.write(to: root.appendingPathComponent("history.json"))
        let a = AccountDataScope(accountID: UUID(), profileID: UUID(), root: root)
        let b = AccountDataScope(accountID: UUID(), profileID: UUID(), root: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: a.file("history.json").path))
        XCTAssertThrowsError(try a.importLegacy(from: root, age: TrainingAgeContext(ageYears: 12, guardianManaged: true)))
        try a.importLegacy(from: root, age: TrainingAgeContext(ageYears: 30, guardianManaged: false))
        XCTAssertEqual(try Data(contentsOf: a.file("history.json")), original)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("history.json")), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: b.file("history.json").path))
        XCTAssertTrue(try a.folder.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        #if !targetEnvironment(simulator)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: a.folder.path)[.protectionKey] as? FileProtectionType, .completeUntilFirstUserAuthentication)
        #endif
        XCTAssertThrowsError(try a.importLegacy(from: root, age: TrainingAgeContext(ageYears: 30, guardianManaged: false)))
    }
}

@MainActor private final class ClaimMembershipClient: MembershipClient {
    var restores = 0
    var entitlements: [MembershipVerification] = [.verified(.init(id: 71, originalID: 70, productID: MembershipPlan.lifetime.productID, kind: .nonConsumable))]
    func products() async throws -> [MembershipOffer] { [] }
    func currentEntitlements() async -> [MembershipVerification] { entitlements }
    func updates() -> AsyncStream<MembershipVerification> { AsyncStream { $0.finish() } }
    func purchase(_ plan: MembershipPlan, appAccountToken: UUID) async throws -> MembershipPurchaseResult { .cancelled }
    func restore() async throws { restores += 1 }
    func finish(transactionID: UInt64) async {}
}

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
        let preferences = try ProgrammePreferences(goals: [.balance], weekdays: [2, 5], ageContext: TrainingAgeContext(ageYears: 12, guardianManaged: true), comfortAnswers: [.legs: .unsure])
        try store.save(LocalProfile(programmePreferences: preferences))
        try store.saveMeasurements(LocalBodyMeasurements(heightCM: 150, weightKG: 45))
        XCTAssertEqual(store.profile?.programmePreferences, preferences)
        XCTAssertTrue(ProfileDraftPersistence(store: store).save(name: "Local", weeklyTarget: 3, goals: [.mobility]))
        let edited = try XCTUnwrap(store.profile?.programmePreferences)
        XCTAssertEqual(edited.goals, [.mobility]); XCTAssertEqual(edited.weekdays.count, 3)
        XCTAssertEqual(edited.ageContext, preferences.ageContext)
        XCTAssertEqual(edited.comfortAnswers, preferences.comfortAnswers)
        XCTAssertEqual(edited.availableSupport, preferences.availableSupport)
        XCTAssertEqual(edited.allowsFloorWork, preferences.allowsFloorWork)
        XCTAssertEqual(edited.excludedExerciseIDs, preferences.excludedExerciseIDs)
        XCTAssertEqual(edited.minutesPerSession, preferences.minutesPerSession)
        XCTAssertEqual(edited.preferredLocalHour, preferences.preferredLocalHour)
        XCTAssertEqual(edited.startingPoint, preferences.startingPoint)
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

/// Exercises the production coordinator and its actual constructed stores.
@MainActor final class FinalFixWaveTests: XCTestCase {
    private func coordinator(root: URL, apple: FinalWaveApple? = nil, cloud: ProgrammeCloudFake? = nil,
                             send: ConsentedAnalyticsStore.Sender? = nil, id: UUID = UUID()) async throws -> AccountWorkspaceCoordinator {
        let vault = MemoryAccountCredentials(), wire = AccountTestTransport(), auth = AccountTestAuthorization()
        auth.succeed = true; wire.failure = URLError(.notConnectedToInternet)
        try vault.save(.init(session: .init(authenticated: true, accountID: id, appAccountToken: id, deviceID: UUID(), accessToken: "fixture-access", refreshToken: "fixture-refresh", accessExpiresAt: Date().addingTimeInterval(900), refreshExpiresAt: Date().addingTimeInterval(86400)), privateKey: P256.Signing.PrivateKey().rawRepresentation, lastTrustedVerification: Date()))
        let account = NativeAccountStore(client: AccountClient(transport: wire), credentials: vault, authorization: auth)
        await account.restore()
        let result = AccountWorkspaceCoordinator(account: account, root: root, membershipClient: apple ?? FinalWaveApple(), analyticsSender: send, programmeClient: cloud)
        result.accountChanged()
        if result.directory?.profiles.isEmpty == true {
            let created = await result.createProfile(name: "Adult", age: try .init(ageYears: 30, guardianManaged: false))
            XCTAssertTrue(created)
        }
        return result
    }
    private func legacy(_ root: URL) throws -> [SessionRecord] {
        let goal = try XCTUnwrap(ExerciseCatalog.find("wallPushup")).goal
        let records = (0..<2).map { day in
            SessionRecord(id: UUID(), date: Date(timeIntervalSince1970: 1_790_000_000 + Double(day * 86400)), sets: [],
                loggedSets: (0..<(day == 0 ? 2 : 1)).map { _ in LoggedSet(id: UUID(), exerciseID: "wallPushup", reps: goal, seconds: 0, source: .manual, reason: .voluntary) })
        }
        try ProtectedLocalStorage.write(JSONEncoder().encode(records), to: root.appendingPathComponent("history.json"))
        return records
    }
    func testFailedProgrammeWithdrawalIsOffAcrossActualCoordinatorReopenAndRetry() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var folder: URL?
        defer { if let folder { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }; try? FileManager.default.removeItem(at: root) }
        let cloud = ProgrammeCloudFake(), c = try await coordinator(root: root, cloud: cloud)
        let w = try XCTUnwrap(c.visibleWorkspace), sync = try XCTUnwrap(w.programmeSync)
        folder = w.scope.folder
        try sync.consent(); await sync.upload(); await sync.read()
        let durableOn = try Data(contentsOf: w.scope.file("programme-cloud-consent.json"))
        XCTAssertNotNil(sync.pendingRemote)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: w.scope.folder.path)
        await sync.withdraw()
        XCTAssertFalse(sync.consented); XCTAssertTrue(sync.withdrawalPending); XCTAssertNil(sync.pendingRemote)
        XCTAssertThrowsError(try sync.consent()); XCTAssertThrowsError(try sync.restoreReviewed())
        await sync.upload(); await sync.read(); await sync.keepLocalReviewed()
        XCTAssertEqual(cloud.writes.count, 1); XCTAssertEqual(cloud.reads, 1)
        XCTAssertEqual(try Data(contentsOf: w.scope.file("programme-cloud-consent.json")), durableOn, "The failed protected write leaves the old ON file, which must not regain authority")
        let reopened = AccountWorkspaceCoordinator(account: c.account, root: root, membershipClient: FinalWaveApple(), programmeClient: cloud)
        reopened.accountChanged()
        XCTAssertEqual(reopened.directory?.selectedID, w.scope.profileID)
        XCTAssertEqual(reopened.directory?.profiles.count, 1, "Reopening cannot manufacture a replacement profile")
        if let lockedWorkspace = reopened.visibleWorkspace {
            XCTAssertEqual(lockedWorkspace.scope, w.scope)
            XCTAssertFalse(try XCTUnwrap(lockedWorkspace.programmeSync).consented)
            XCTAssertTrue(try XCTUnwrap(lockedWorkspace.programmeSync).withdrawalPending)
        } else {
            XCTAssertNotNil(reopened.message, "An unavailable protected graph must remain closed")
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: w.scope.folder.path)
        reopened.accountChanged()
        let sameScope = try XCTUnwrap(reopened.visibleWorkspace)
        XCTAssertEqual(sameScope.scope, w.scope)
        let next = try XCTUnwrap(sameScope.programmeSync)
        XCTAssertFalse(next.consented); XCTAssertTrue(next.withdrawalPending)
        XCTAssertThrowsError(try next.consent())
        await next.upload(); await next.read()
        XCTAssertEqual(cloud.writes.count, 1); XCTAssertEqual(cloud.reads, 1)
        await next.withdraw()
        XCTAssertFalse(next.consented); XCTAssertFalse(next.withdrawalPending)
        XCTAssertNil(cloud.remote)
        let durable = try await coordinator(root: root, cloud: cloud, id: w.scope.accountID)
        XCTAssertFalse(try XCTUnwrap(durable.visibleWorkspace?.programmeSync).consented)
        XCTAssertFalse(sync.consented, "An older instance must not revive a resolved withdrawal")
    }
    func testActualLegacyReplacementRetiresHeldAnalyticsBeforeNewWithdrawal() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var release: CheckedContinuation<Int, Never>?
        let c = try await coordinator(root: root, send: { _ in await withCheckedContinuation { release = $0 } })
        _ = try legacy(root)
        let old = try XCTUnwrap(c.visibleWorkspace), analytics = try XCTUnwrap(old.training.analytics)
        try analytics.setConsent(.usage, enabled: true); analytics.feature("today")
        let flush = Task { await analytics.flush() }
        for _ in 0..<1000 where release == nil { await Task.yield() }
        XCTAssertNotNil(release)
        await c.importLegacy()
        let replacement = try XCTUnwrap(c.visibleWorkspace)
        XCTAssertFalse(replacement === old)
        XCTAssertFalse(old.profile.permitsPolicyCallbacks)
        try XCTUnwrap(replacement.training.analytics).setConsent(.usage, enabled: false)
        let off = try Data(contentsOf: old.scope.file("analytics-consent.json"))
        release?.resume(returning: 202); await flush.value
        XCTAssertEqual(try Data(contentsOf: old.scope.file("analytics-consent.json")), off)
        XCTAssertThrowsError(try analytics.setConsent(.usage, enabled: true))
        let reopened = try await coordinator(root: root, id: old.scope.accountID)
        XCTAssertNil(reopened.visibleWorkspace?.training.analytics?.ledger.capture(.usage))
    }
    func testActualFirstLegacyImportRetainsEarnedNodesWithoutRetroactiveRewardsOrAnalytics() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let records = try legacy(root)
        let c = try await coordinator(root: root)
        let fresh = try XCTUnwrap(c.visibleWorkspace)
        XCTAssertTrue(fresh.training.history.isEmpty)
        XCTAssertNotNil(fresh.training.quests?.archive.benchmarkPolicy)
        await c.importLegacy()
        let imported = try XCTUnwrap(c.visibleWorkspace)
        XCTAssertEqual(Set(imported.training.history.map(\.id)), Set(records.map(\.id)))
        func assertEarned(_ w: AccountWorkspace) throws {
            let qualified = try XCTUnwrap(w.training.quests).benchmarkHistory(w.training.history)
            let result = SkillCurriculum.evaluate(profile: try XCTUnwrap(w.profile.profile), history: qualified, calendar: w.programme.localCalendar)
            XCTAssertEqual(result.node("wallPushup")?.state, .earned)
            XCTAssertEqual(w.training.quests?.archive.totalXP, 0)
            XCTAssertTrue(w.training.analytics?.pending.isEmpty == true)
        }
        try assertEarned(imported)
        let reopened = try await coordinator(root: root, id: imported.scope.accountID)
        try assertEarned(try XCTUnwrap(reopened.visibleWorkspace))
        let receipt = try Data(contentsOf: imported.scope.file("legacy-import.json"))
        await c.importLegacy()
        XCTAssertEqual(try Data(contentsOf: imported.scope.file("legacy-import.json")), receipt)
        XCTAssertTrue(c.visibleWorkspace === imported, "Failed repeated import retains its usable graph")
        XCTAssertTrue(imported.profile.permitsPolicyCallbacks)
    }
    func testFailedLegacyImportPreservesCurrentGraphAndAllowsRetry() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let c = try await coordinator(root: root), old = try XCTUnwrap(c.visibleWorkspace)
        try ProtectedLocalStorage.write(Data("corrupt".utf8), to: root.appendingPathComponent("history.json"))
        await c.importLegacy()
        XCTAssertTrue(c.visibleWorkspace === old); XCTAssertTrue(old.profile.permitsPolicyCallbacks)
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.scope.file("history.json").path))
        _ = try legacy(root); await c.importLegacy()
        XCTAssertFalse(c.visibleWorkspace === old)
    }
    func testLegacyReplacementConstructionFailureRollsBackWholeOwnedDirectory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let c = try await coordinator(root: root), old = try XCTUnwrap(c.visibleWorkspace)
        _ = try legacy(root)
        let quests = try Data(contentsOf: old.scope.file("quests.json"))
        try ProtectedLocalStorage.write(Data("blocked".utf8), to: old.scope.file("health-preferences.plist"))
        await c.importLegacy()
        XCTAssertTrue(c.visibleWorkspace === old); XCTAssertTrue(old.profile.permitsPolicyCallbacks)
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.scope.file("history.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.scope.file("legacy-import.json").path))
        XCTAssertEqual(try Data(contentsOf: old.scope.file("quests.json")), quests)
        try FileManager.default.removeItem(at: old.scope.file("health-preferences.plist"))
        await c.importLegacy()
        XCTAssertFalse(c.visibleWorkspace === old)
    }
    func testReturningMemberGetsWatchGrantWithoutMembershipScreenOrUpdates() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let apple = FinalWaveApple(), c = try await coordinator(root: root, apple: apple)
        let w = try XCTUnwrap(c.visibleWorkspace), age = try TrainingAgeContext(ageYears: 30, guardianManaged: false)
        apple.values = [.verified(.init(appAccountToken: w.scope.accountID, productID: MembershipPlan.lifetime.productID, kind: .nonConsumable))]
        try w.profile.save(.init(bodyMeasurements: .init(heightCM: 170, weightKG: 70), onboardingRevision: TrainingSetup.revision, programmePreferences: .init(goals: [.balance], weekdays: Set(1...7), startingPoint: .startingOut, ageContext: age, comfortAnswers: Dictionary(uniqueKeysWithValues: ExerciseFamily.allCases.map { ($0, TrainingSetup.Comfort.unsure) }))))
        _ = try w.programme.prepare(profile: XCTUnwrap(w.profile.profile), history: [])
        await c.membership.refreshEntitlements(); try w.watchSharing.setEnabled(true); w.training.publish()
        let cached = try XCTUnwrap(w.watchBridge?.lastTransport)
        XCTAssertNotNil(cached.grant)
        let archive = try WatchWorkoutArchive(url: root.appendingPathComponent("watch-cache.json"))
        try archive.receive(cached)
        apple.hold = true; apple.calls = 0
        let returned = try await coordinator(root: root, apple: apple, id: w.scope.accountID)
        let rw = try XCTUnwrap(returned.visibleWorkspace), verifiedAt = returned.account.lastTrustedVerification
        rw.watchBridge?.refreshForWatchRequest(); rw.watchBridge?.refreshForWatchRequest()
        for _ in 0..<1000 where apple.release == nil { await Task.yield() }
        XCTAssertEqual(apple.calls, 1, "Startup and Watch request coalesce current entitlements even with fresh private verification")
        if let unresolved = rw.watchBridge?.lastTransport { try archive.receive(unresolved) }
        XCTAssertNotNil(archive.transport?.grant, "Unresolved Apple state must not revoke a same-owner cached grant")
        apple.release?.resume(returning: apple.values); apple.release = nil; apple.hold = false
        for _ in 0..<1000 where rw.watchBridge?.lastTransport?.grant == nil { await Task.yield() }
        XCTAssertTrue(returned.membership.hasAccess); XCTAssertNotNil(rw.watchBridge?.lastTransport?.grant)
        XCTAssertEqual(returned.account.lastTrustedVerification, verifiedAt)
        XCTAssertEqual(rw.watchBridge?.lastTransport?.grant?.verifiedAt, verifiedAt)
        apple.values = []; await returned.membership.refreshEntitlements(); rw.training.publish()
        try archive.receive(XCTUnwrap(rw.watchBridge?.lastTransport))
        XCTAssertNil(archive.transport?.grant, "Authoritative revocation remains fail closed")
    }
}

@MainActor private final class FinalWaveApple: MembershipClient {
    var values: [MembershipVerification] = []
    var calls = 0, hold = false
    var release: CheckedContinuation<[MembershipVerification], Never>?
    func products() async throws -> [MembershipOffer] { [] }
    func currentEntitlements() async -> [MembershipVerification] {
        calls += 1
        if hold { return await withCheckedContinuation { release = $0 } }
        return values
    }
    func updates() -> AsyncStream<MembershipVerification> { AsyncStream { $0.finish() } }
    func purchase(_ plan: MembershipPlan, appAccountToken: UUID) async throws -> MembershipPurchaseResult { .cancelled }
    func restore() async throws {}
    func finish(transactionID: UInt64) async {}
}

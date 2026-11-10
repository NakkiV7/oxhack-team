import XCTest
import CryptoKit
@testable import Spottr

@MainActor final class TrainingSetupTests: XCTestCase {
    func testLegacyVoiceMigrationPreservesProgrammeHistoryAndExplicitFeedbackOff() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = try AccountProfileDirectory(accountID: UUID(), root: root)
        let person = try directory.add(age: .init(ageYears: 30, guardianManaged: false), name: "Adult")
        let scope = directory.scope(person.id)
        let workspace = try AccountWorkspace(scope: scope)
        let profile = try XCTUnwrap(workspace.profile.profile)
        _ = try workspace.programme.prepare(profile: profile, history: [])
        workspace.training.beginAuthorizedSession()
        workspace.training.switchToManualReps(); workspace.training.setManualReps(3)
        workspace.training.endSet(); workspace.training.finish()
        let history = workspace.training.history
        XCTAssertEqual(history.first?.sets.first?.reps, 3)
        let programmeBytes = try Data(contentsOf: scope.file("programme.json"))
        let historyBytes = try Data(contentsOf: scope.file("history.json"))
        let profileBytes = try Data(contentsOf: scope.file("profile.json"))
        let defaults = workspace.profile.preferencesDefaults
        defaults.set(false, forKey: "trainer.audioEnabled")
        for retired in ["arnold", "david", "goggins"] {
            defaults.set(retired, forKey: "trainer.voice")
            defaults.set(retired, forKey: RepVoicePlayer.defaultsKey)
            let reopened = try AccountWorkspace(scope: scope)
            XCTAssertEqual(reopened.training.remoteVoice?.preference.rawValue, "maya")
            XCTAssertEqual(defaults.string(forKey: "trainer.voice"), "maya")
            XCTAssertNil(reopened.training.repVoice.coach)
            XCTAssertFalse(reopened.training.voiceFeedbackEnabled)
            XCTAssertEqual(reopened.training.history, history)
            XCTAssertEqual(try Data(contentsOf: scope.file("programme.json")), programmeBytes)
            XCTAssertEqual(try Data(contentsOf: scope.file("history.json")), historyBytes)
            XCTAssertEqual(try Data(contentsOf: scope.file("profile.json")), profileBytes)
            reopened.training.cancelCoaching()
        }
        workspace.training.cancelCoaching()
    }

    func testScopedProfileResetPreservesCanonicalAgeAndRequiresFreshSetup() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = try AccountProfileDirectory(accountID: UUID(), root: root)
        let age = try TrainingAgeContext(ageYears: 10, guardianManaged: true)
        let person = try directory.add(age: age, name: "Junior")
        let workspace = try AccountWorkspace(scope: directory.scope(person.id))
        try workspace.profile.resetProfile()
        XCTAssertEqual(workspace.profile.profile?.programmePreferences?.ageContext, age)
        XCTAssertFalse(AccountPolicy.setupComplete(profile: workspace.profile.profile))
        XCTAssertNoThrow(try AccountWorkspace(scope: directory.scope(person.id)))
    }
    func testSetupCoachPreferencesReachOnlyTheirWorkspaceAndJuniorPolicyForcesGentle() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = try AccountProfileDirectory(accountID: UUID(), root: root)
        let adult = try directory.add(age: .init(ageYears: 30, guardianManaged: false), name: "Adult")
        let junior = try directory.add(age: .init(ageYears: 10, guardianManaged: true), name: "Junior")
        let first = try AccountWorkspace(scope: directory.scope(adult.id))
        first.profile.preferencesDefaults.set("leo", forKey: "trainer.voice")
        first.profile.preferencesDefaults.set("direct", forKey: "trainer.tone")
        first.training.remoteVoice?.reloadPreferences()
        XCTAssertEqual(first.training.remoteVoice?.preference, .leo)
        let child = try AccountWorkspace(scope: directory.scope(junior.id))
        child.profile.preferencesDefaults.set("david", forKey: "trainer.voice")
        child.profile.preferencesDefaults.set("direct", forKey: "trainer.tone")
        child.training.remoteVoice?.reloadPreferences()
        XCTAssertEqual(child.training.remoteVoice?.tone, .gentle)
        XCTAssertEqual(child.training.remoteVoice?.preference, .maya)
        XCTAssertFalse(child.training.remoteVoice?.configuredVoices.map(\.rawValue).contains("david") == true)
        XCTAssertEqual(first.training.remoteVoice?.tone, .direct)
        child.profile.preferencesDefaults.set("goggins", forKey: RepVoicePlayer.defaultsKey)
        let reopenedJunior = try AccountWorkspace(scope: directory.scope(junior.id))
        XCTAssertNil(reopenedJunior.training.repVoice.coach, "An adult rep pack cannot survive a junior policy rebuild")
        first.profile.preferencesDefaults.set(true, forKey: "trainer.audioEnabled")
        let reopened = try AccountWorkspace(scope: directory.scope(adult.id))
        XCTAssertTrue(reopened.training.voiceFeedbackEnabled)
    }
    func testCanonicalAgeUpdateRebuildsPolicyAndRejectsDirectAgeMutation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = try AccountProfileDirectory(accountID: UUID(), root: root)
        let person = try directory.add(age: try .init(ageYears: 30, guardianManaged: false), name: "Person")
        let old = try AccountWorkspace(scope: directory.scope(person.id))
        let oldProfile = try XCTUnwrap(old.profile.profile)
        let junior = try TrainingAgeContext(ageYears: 10, guardianManaged: true)
        XCTAssertThrowsError(try old.profile.save(LocalProfile(programmePreferences: oldProfile.effectiveProgrammePreferences.changingAge(to: junior))))
        try directory.updateIdentity(id: person.id, name: "Junior", age: junior)
        let next = try AccountWorkspace(scope: directory.scope(person.id))
        XCTAssertEqual(next.profile.profile?.programmePreferences?.ageContext, junior)
        XCTAssertEqual(directory.profiles.first?.age, junior)
        XCTAssertFalse(next.training.rewards.allowsTimePressureRewards)
        XCTAssertNotEqual(next.policyEpoch, old.policyEpoch)
        XCTAssertFalse(AccountPolicy.setupComplete(profile: next.profile.profile))
    }

    func testSameProfileAgeChangeCancelsOldAdultPendingContinueAndBlocksUnfinishedWork() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID(), vault = MemoryAccountCredentials(), wire = AccountTestTransport()
        try vault.save(.init(session: NativeAccountSession(authenticated: true, accountID: id, appAccountToken: id, deviceID: UUID(), accessToken: "access", refreshToken: "refresh", accessExpiresAt: .now.addingTimeInterval(900), refreshExpiresAt: .now.addingTimeInterval(86400)), privateKey: P256.Signing.PrivateKey().rawRepresentation))
        wire.failure = URLError(.notConnectedToInternet)
        let authorization = AccountTestAuthorization(); authorization.succeed = true
        let account = NativeAccountStore(client: AccountClient(transport: wire), credentials: vault, authorization: authorization)
        let membershipClient = SetupMembershipFake()
        let coordinator = AccountWorkspaceCoordinator(account: account, root: root, membershipClient: membershipClient)
        await account.restore(); coordinator.accountChanged()
        let created = await coordinator.createProfile(name: "Adult", age: try .init(ageYears: 30, guardianManaged: false))
        XCTAssertTrue(created)
        let old = try XCTUnwrap(coordinator.visibleWorkspace)
        try old.profile.save(LocalProfile(bodyMeasurements: .init(heightCM: 170, weightKG: 70), onboardingRevision: TrainingSetup.revision,
            programmePreferences: .init(goals: [.strength], weekdays: [1], startingPoint: .experienced,
                ageContext: .init(ageYears: 30, guardianManaged: false),
                comfortAnswers: Dictionary(uniqueKeysWithValues: ExerciseFamily.allCases.map { ($0, TrainingSetup.Comfort.unsure) }))))
        let launch = try XCTUnwrap(old.launch)
        let plan = try CoachSavedPlan.catalogue(exerciseID: "pushup", sets: 3, target: 20, restSeconds: 60)
        launch.request(plan: plan, origin: .library)
        let pending = try XCTUnwrap(launch.pendingID)
        XCTAssertEqual(launch.decision, .requiresMembership)
        membershipClient.entitlements = [.verified(.init(appAccountToken: id, productID: MembershipPlan.lifetime.productID, kind: .nonConsumable))]
        await coordinator.membership.refreshEntitlements()
        XCTAssertTrue(coordinator.membership.hasAccess)
        let profileID = old.scope.profileID
        await coordinator.updateSelectedIdentity(name: "Junior", age: try .init(ageYears: 10, guardianManaged: true))
        let next = try XCTUnwrap(coordinator.visibleWorkspace)
        XCTAssertEqual(next.scope.profileID, profileID)
        XCTAssertFalse(next === old)
        XCTAssertFalse(old.profile.permitsPolicyCallbacks)
        launch.continuePending(id: pending)
        XCTAssertNil(launch.pendingID)
        XCTAssertEqual(old.training.sessionPhase, .idle)
        XCTAssertEqual(next.training.sessionPhase, .idle)
        next.training.beginAuthorizedPlan(try .catalogue(exerciseID: "frontArmRaise", sets: 1, target: 6, restSeconds: 30), availableSupport: [])
        next.training.beginConfiguredSet(); next.training.setConfiguredReps(3)
        await coordinator.updateSelectedIdentity(name: "Adult again", age: try .init(ageYears: 30, guardianManaged: false))
        XCTAssertTrue(coordinator.visibleWorkspace === next)
        XCTAssertEqual(next.training.configured?.actualReps, 3)
        XCTAssertEqual(next.profile.profile?.programmePreferences?.ageContext?.ageYears, 10)
    }

    func testMismatchedDirectoryAndProfileFailClosed() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = try AccountProfileDirectory(accountID: UUID(), root: root)
        let person = try directory.add(age: try .init(ageYears: 30, guardianManaged: false), name: "Person")
        let scope = directory.scope(person.id)
        try NativeProfileStore(url: scope.file("profile.json")).save(LocalProfile(programmePreferences: .init(goals: [.balance], weekdays: [1], ageContext: .init(ageYears: 10, guardianManaged: true))))
        XCTAssertThrowsError(try AccountWorkspace(scope: scope))
    }

    func testImperialMeasurementDraftPersistsConvertedValuesAndWeightOnlyGoalStaysDistinct() throws {
        var saved: LocalBodyMeasurements?
        let measurements = MeasurementsDraftPersistence { saved = $0 }
        measurements.edit(heightCM: "70", weightKG: "154", bmiEligible: true, thresholds: .standard, units: .imperial)
        XCTAssertTrue(measurements.prepareToLeave())
        XCTAssertEqual(try XCTUnwrap(saved).heightCM, 177.8, accuracy: 0.0001)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NativeProfileStore(url: root.appendingPathComponent("profile.json"))
        try store.save(.init(programmePreferences: .init(goals: [.strength], weekdays: [1], ageContext: .init(ageYears: 30, guardianManaged: false))))
        let draft = ProfileDraftPersistence(store: store)
        XCTAssertTrue(draft.save(name: "Adult", weeklyTarget: 1, goals: [.weightManagement]))
        XCTAssertEqual(store.profile?.trainingGoals, [.weightManagement])
        XCTAssertEqual(store.profile?.programmePreferences?.ageContext?.ageYears, 30)
    }

    func testOldAdultHealthRequestCannotReturnAfterPolicyInvalidation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NativeProfileStore(url: root.appendingPathComponent("profile.json"))
        try store.save(.init(programmePreferences: .init(goals: [.balance], weekdays: [1], ageContext: .init(ageYears: 30, guardianManaged: false))))
        let underlying = SetupHealthFake()
        let client = ScopedHealthReadingClient(profile: store, client: underlying)
        let read = Task { try await client.read(asOf: .now, dayStart: .now, dayEnd: .now) }
        for _ in 0..<100 where underlying.pending == nil { await Task.yield() }
        XCTAssertNotNil(underlying.pending)
        store.invalidatePolicy()
        underlying.pending?.resume(returning: [])
        do { _ = try await read.value; XCTFail("Old adult Health results must be rejected") } catch {}
        XCTAssertFalse(client.isAvailable)
    }

    func testDeniedPermissionsKeepManualCompletion() async throws {
        let client = SetupPermissionFake()
        let store = PhonePermissionStore(client: client)
        await store.refresh()
        XCTAssertEqual(store.camera, .denied)
        XCTAssertEqual(store.microphone, .denied)
        XCTAssertEqual(store.notifications, .denied)
        XCTAssertTrue(store.manualAvailable)
        await store.request(.speech)
        XCTAssertEqual(store.speech, .unavailable)
    }
    func testPermissionResultCannotPublishAfterPolicyInvalidation() async throws {
        let client = SetupDelayedPermissionFake()
        let store = PhonePermissionStore(client: client)
        let request = Task { await store.request(.microphone) }
        for _ in 0..<100 where client.pending == nil { await Task.yield() }
        XCTAssertNotNil(client.pending)
        store.invalidate()
        client.pending?.resume()
        await request.value
        XCTAssertEqual(store.microphone, .notRequested)
        XCTAssertFalse(store.busy)
    }
}

@MainActor private final class SetupMembershipFake: MembershipClient {
    var entitlements: [MembershipVerification] = []
    func products() async throws -> [MembershipOffer] { [] }
    func currentEntitlements() async -> [MembershipVerification] { entitlements }
    func updates() -> AsyncStream<MembershipVerification> { AsyncStream { $0.finish() } }
    func purchase(_ plan: MembershipPlan, appAccountToken: UUID) async throws -> MembershipPurchaseResult { .cancelled }
    func restore() async throws {}
    func finish(transactionID: UInt64) async {}
}

@MainActor private final class SetupDelayedPermissionFake: PhonePermissionClient {
    var pending: CheckedContinuation<Void, Never>?
    func status(_ feature: PhonePermissionFeature) async -> PhonePermissionState { .allowed }
    func request(_ feature: PhonePermissionFeature) async { await withCheckedContinuation { pending = $0 } }
}

@MainActor private final class SetupPermissionFake: PhonePermissionClient {
    func status(_ feature: PhonePermissionFeature) async -> PhonePermissionState { feature == .speech ? .unavailable : .denied }
    func request(_ feature: PhonePermissionFeature) async {}
}

@MainActor private final class SetupHealthFake: HealthReadingClient {
    var isAvailable = true
    var pending: CheckedContinuation<[HealthObservation], Error>?
    func requestReadAuthorization() async throws {}
    func read(asOf: Date, dayStart: Date, dayEnd: Date) async throws -> [HealthObservation] {
        try await withCheckedThrowingContinuation { pending = $0 }
    }
}

@MainActor final class TrainingPresentationTests: XCTestCase {
    private let adult = try! TrainingAgeContext(ageYears: 30, guardianManaged: false)

    func testTrainingStartsAtPrivacyOnlyWhenAnalyticsIsAvailable() {
        XCTAssertEqual(TrainingSetupPresentation(preferences: nil, hasAnalytics: true).stage, .account)
        XCTAssertEqual(TrainingSetupPresentation(preferences: nil, hasAnalytics: false).stage, .body)
    }

    func testGoalsScheduleAndSupportAreSeparateAndRequireTheirOwnAnswers() {
        var draft = TrainingSetupPresentation(preferences: nil, hasAnalytics: false)
        XCTAssertEqual(draft.advance(age: adult, hasMeasurements: true), .moved)
        XCTAssertEqual(draft.stage, .goals)
        XCTAssertEqual(draft.rhythmStep, .goals)
        assertBlocked(draft.advance(age: adult, hasMeasurements: true))
        draft.goals = [.strength]
        XCTAssertEqual(draft.advance(age: adult, hasMeasurements: true), .moved)
        XCTAssertEqual(draft.stage, .goals)
        XCTAssertEqual(draft.rhythmStep, .schedule)
        assertBlocked(draft.advance(age: adult, hasMeasurements: true))
        draft.weekdays = [2, 5]
        XCTAssertEqual(draft.advance(age: adult, hasMeasurements: true), .moved)
        XCTAssertEqual(draft.stage, .goals)
        XCTAssertEqual(draft.rhythmStep, .support)
        XCTAssertEqual(draft.advance(age: adult, hasMeasurements: true), .moved)
        XCTAssertEqual(draft.stage, .comfort)
        XCTAssertEqual(draft.comfortStep, .startingPoint)
    }

    func testBackRetracesLocalStepsWithoutLosingAnySelections() throws {
        var draft = TrainingSetupPresentation(preferences: try preferences(), hasAnalytics: false)
        _ = draft.advance(age: adult, hasMeasurements: true)
        _ = draft.advance(age: adult, hasMeasurements: true)
        _ = draft.advance(age: adult, hasMeasurements: true)
        draft.support = [PathSurvey.equipmentChoices[0]]
        draft.floor = false
        draft.minutes = 30; draft.hour = 9
        _ = draft.advance(age: adult, hasMeasurements: true)
        draft.goBack()
        XCTAssertEqual(draft.stage, .goals)
        XCTAssertEqual(draft.rhythmStep, .support)
        draft.goBack()
        XCTAssertEqual(draft.rhythmStep, .schedule)
        draft.goBack()
        XCTAssertEqual(draft.rhythmStep, .goals)
        XCTAssertEqual(draft.goals, [.balance])
        XCTAssertEqual(draft.weekdays, [1, 3])
        XCTAssertEqual(draft.minutes, 30)
        XCTAssertEqual(draft.hour, 9)
        XCTAssertEqual(draft.support, [PathSurvey.equipmentChoices[0]])
        XCTAssertFalse(draft.floor)
    }

    func testExplicitUnsureAdvancesOneFamilyThenReviewCanChangeAnAnswer() throws {
        var draft = try comfortDraft()
        draft.startingPoint = .somePractice
        XCTAssertEqual(draft.advance(age: adult, hasMeasurements: true), .moved)
        let first = try XCTUnwrap(ExerciseFamily.allCases.first)
        XCTAssertEqual(draft.comfortStep, .family(first))
        for family in ExerciseFamily.allCases {
            XCTAssertEqual(draft.comfortStep, .family(family))
            draft.answer(.unsure, family: family)
        }
        XCTAssertEqual(draft.comfortStep, .review)
        XCTAssertEqual(draft.answers.count, ExerciseFamily.allCases.count)
        draft.review(first)
        XCTAssertEqual(draft.comfortStep, .family(first))
        let entry = try XCTUnwrap(ExerciseCatalog.all.first { $0.family == first && (try? draft.preferences(age: adult).canUse($0)) == true })
        draft.answer(.movement(entry.id), family: first)
        XCTAssertEqual(draft.comfortStep, .review)
        XCTAssertEqual(draft.answers[first], .movement(entry.id))
        XCTAssertTrue(ExerciseFamily.allCases.dropFirst().allSatisfy { draft.answers[$0] == .unsure })
        XCTAssertEqual(draft.advance(age: adult, hasMeasurements: true), .moved)
        XCTAssertEqual(draft.stage, .permissions)
    }

    func testComfortCannotBeContinuedUntilEveryRequiredAnswerIsValid() throws {
        var draft = try comfortDraft()
        assertBlocked(draft.advance(age: adult, hasMeasurements: true))
        draft.startingPoint = .startingOut
        _ = draft.advance(age: adult, hasMeasurements: true)
        assertBlocked(draft.advance(age: adult, hasMeasurements: true))
        let first = try XCTUnwrap(ExerciseFamily.allCases.first)
        draft.answer(.unsure, family: first)
        XCTAssertEqual(draft.stage, .comfort)
        assertBlocked(draft.advance(age: adult, hasMeasurements: true))
        for family in ExerciseFamily.allCases { draft.answer(.unsure, family: family) }
        draft.review(first)
        draft.answer(.movement("missing-movement"), family: first)
        assertBlocked(draft.advance(age: adult, hasMeasurements: true))
        XCTAssertEqual(draft.stage, .comfort)
    }

    func testMissingAgeAndAdultMeasurementsBlockBeforeAnySaveOutcome() {
        var draft = TrainingSetupPresentation(preferences: nil, hasAnalytics: false)
        assertBlocked(draft.advance(age: nil, hasMeasurements: true))
        assertBlocked(draft.advance(age: adult, hasMeasurements: false))
        XCTAssertEqual(draft.stage, .body)
    }

    func testUnderFiveKeepsSupervisedPlayAndJuniorChoicesRemainRestricted() throws {
        let child = try TrainingAgeContext(ageYears: 4, guardianManaged: true)
        var draft = TrainingSetupPresentation(preferences: try preferences(age: child), hasAnalytics: false)
        for _ in 0..<4 { XCTAssertEqual(draft.advance(age: child, hasMeasurements: false), .moved) }
        XCTAssertEqual(draft.stage, .comfort)
        XCTAssertEqual(draft.advance(age: child, hasMeasurements: false), .moved)
        XCTAssertEqual(draft.stage, .permissions)
        XCTAssertTrue(draft.answers.isEmpty)
        XCTAssertFalse(try draft.preferences(age: child).canUse(ExerciseCatalog.find("squat")!))
    }

    func testSaveOutcomeRequiresCompletedReviewAndCurrentExclusionsAreHonoured() throws {
        var draft = try comfortDraft()
        draft.startingPoint = .startingOut
        _ = draft.advance(age: adult, hasMeasurements: true)
        for family in ExerciseFamily.allCases { draft.answer(.unsure, family: family) }
        draft.review(.legs)
        draft.answer(.movement("squat"), family: .legs)
        assertBlocked(draft.advance(age: adult, hasMeasurements: true, excludedExerciseIDs: ["squat"]))
        XCTAssertEqual(draft.comfortStep, .family(.legs))
        draft.answer(.unsure, family: .legs)
        XCTAssertEqual(draft.advance(age: adult, hasMeasurements: true), .moved)
        XCTAssertEqual(draft.stage, .permissions)
        XCTAssertEqual(draft.advance(age: adult, hasMeasurements: true), .moved)
        XCTAssertEqual(draft.stage, .coach)
        XCTAssertEqual(draft.advance(age: adult, hasMeasurements: true), .save)
        draft.goBack()
        XCTAssertEqual(draft.stage, .permissions)
        draft.goBack()
        XCTAssertEqual(draft.stage, .comfort)
        XCTAssertEqual(draft.comfortStep, .review)
        XCTAssertEqual(draft.answers.count, 6)
    }

    private func comfortDraft() throws -> TrainingSetupPresentation {
        var draft = TrainingSetupPresentation(preferences: try preferences(), hasAnalytics: false)
        for _ in 0..<4 { _ = draft.advance(age: adult, hasMeasurements: true) }
        XCTAssertEqual(draft.stage, .comfort)
        return draft
    }
    private func preferences(age: TrainingAgeContext? = nil) throws -> ProgrammePreferences {
        try .init(goals: [.balance], weekdays: [1, 3], ageContext: age ?? adult)
    }
    private func assertBlocked(_ outcome: TrainingSetupPresentation.Advance, file: StaticString = #filePath, line: UInt = #line) {
        guard case .blocked = outcome else { XCTFail("Required choices must block Continue", file: file, line: line); return }
    }
}

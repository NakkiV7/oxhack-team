import XCTest
@testable import Spottr

@MainActor final class QuestNativeTests: XCTestCase {
    func testPolicyCorrectionPreservesPreviouslyEarnedBonusButNewJuniorCannotEarnBonus() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 1_792_800_000)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let adult = NativeRewardsStore(url: root.appendingPathComponent("rewards.json"), createdAt: now, calendar: calendar)
        try adult.schedule(startHour: 10, at: now)
        let completion = calendar.startOfDay(for: now).addingTimeInterval(86400 + 36001)
        let owner = WorkoutOwner(accountID: UUID(), profileID: UUID())
        let record = SessionRecord(id: UUID(), date: completion, sets: [], loggedSets: [LoggedSet(id: UUID(), exerciseID: "wallPushup", reps: 20, seconds: 0, source: .manual, reason: .voluntary)], trainingContext: .init(owner: owner, age: try .init(ageYears: 30, guardianManaged: false)))
        try adult.award(record: record, before: [], history: [record], completedAt: completion)
        let junior = NativeRewardsStore(url: root.appendingPathComponent("rewards.json"), createdAt: now, calendar: calendar, allowsTimePressureRewards: false)
        XCTAssertEqual(junior.totalXP(history: [record]), adult.totalXP(history: [record]))
        let childRecord = SessionRecord(id: UUID(), date: completion, sets: [], loggedSets: record.loggedSets, trainingContext: .init(owner: owner, age: try .init(ageYears: 8, guardianManaged: true)))
        try adult.award(record: childRecord, before: [record], history: [record, childRecord], completedAt: completion)
        XCTAssertFalse(adult.ledger.events.contains { $0.sessionID == childRecord.id })
    }
}

@MainActor private final class QuestNotificationFake: RewardNotificationClient {
    var permission = true
    var pending: [String] = ["unrelated.medication"]
    var added: [XPReminder] = []
    var requested = 0
    func authorized() async -> Bool { permission }
    func requestAuthorization() async throws -> Bool { requested += 1; return permission }
    func pendingIDs() async -> [String] { pending }
    func remove(ids: [String]) { pending.removeAll { ids.contains($0) }; added.removeAll { ids.contains($0.id) } }
    func add(_ reminder: XPReminder) async throws { pending.append(reminder.id); added.append(reminder) }
}
extension QuestNativeTests {
    func testScopedQuestClaimPersistsAndRetiredSameUUIDPolicyCannotWrite() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let scope = AccountDataScope(accountID: UUID(), profileID: UUID(), root: root)
        let profile = NativeProfileStore(url: scope.file("profile.json"))
        try profile.save(LocalProfile(programmePreferences: .init(goals: [.balance], weekdays: [1], ageContext: .init(ageYears: 4, guardianManaged: true))))
        let programme = ProgrammeStore(scope: scope, profile: profile)
        let store = QuestStore(scope: scope, profile: profile, programme: programme)
        let quest = try XCTUnwrap(store.choices(history: []).first { $0.kind == .familyActivity })
        XCTAssertFalse(try store.claim(quest, history: []))
        try store.checkIn(quest, history: [])
        XCTAssertTrue(try store.claim(quest, history: []))
        XCTAssertFalse(try store.claim(quest, history: []))
        let exportURL = try scope.exportLocalData()
        defer { try? FileManager.default.removeItem(at: exportURL.deletingLastPathComponent()) }
        let exported = try JSONDecoder().decode(AccountLocalExport.self, from: Data(contentsOf: exportURL))
        XCTAssertEqual(exported.formatVersion, 4)
        XCTAssertEqual(exported.quests?.totalXP, 10)
        let reopened = QuestStore(scope: scope, profile: profile, programme: programme)
        XCTAssertEqual(reopened.archive.totalXP, 10)
        XCTAssertEqual(reopened.archive.checkIns.count, 1)
        profile.invalidatePolicy()
        XCTAssertThrowsError(try store.checkIn(quest, history: []))
        XCTAssertThrowsError(try store.claim(quest, history: []))
    }
    func testReminderDenialReplacementAndJuniorSwitchOnlyRemoveOwnedRequests() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let scope = AccountDataScope(accountID: UUID(), profileID: UUID(), root: root)
        let profile = NativeProfileStore(url: scope.file("profile.json"))
        try profile.save(LocalProfile(programmePreferences: .init(goals: [.balance], weekdays: [1], ageContext: .init(ageYears: 30, guardianManaged: false))))
        let programme = ProgrammeStore(scope: scope, profile: profile)
        let rewards = NativeRewardsStore(url: scope.file("rewards.json"), createdAt: Date().addingTimeInterval(-86400))
        try rewards.schedule(startHour: 10, at: Date())
        let client = QuestNotificationFake()
        let store = RewardReminderStore(scope: scope, profile: profile, rewards: rewards, programme: programme, client: client)
        await store.refresh()
        XCTAssertEqual(client.pending, ["unrelated.medication"])
        client.permission = false
        try await store.setConsent(true)
        XCTAssertTrue(client.added.isEmpty)
        client.permission = true
        try await store.setConsent(true)
        XCTAssertFalse(client.added.isEmpty)
        XCTAssertLessThan(client.pending.count, 64)
        let old = Set(client.added.map(\.id))
        try rewards.schedule(startHour: 20, at: Date())
        await store.refresh()
        XCTAssertTrue(old.isDisjoint(with: Set(client.added.map(\.id))))
        XCTAssertTrue(client.pending.contains("unrelated.medication"))
        profile.invalidatePolicy(); store.suspend()
        await store.refresh()
        XCTAssertEqual(client.pending, ["unrelated.medication"])
        XCTAssertEqual(client.requested, 2)
    }
}
extension QuestNativeTests {
    func testHistoryDeletionReconcilesQuestEvidenceAndSameWorkspaceResumeRestoresOptedInReminders() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let scope = AccountDataScope(accountID: UUID(), profileID: UUID(), root: root)
        let profile = NativeProfileStore(url: scope.file("profile.json"))
        try profile.save(LocalProfile(programmePreferences: .init(goals: [.balance], weekdays: Set(1...7), ageContext: .init(ageYears: 30, guardianManaged: false))))
        let workspace = try AccountWorkspace(scope: scope)
        _ = try workspace.programme.prepare(profile: XCTUnwrap(workspace.profile.profile), history: [])
        let quests = try XCTUnwrap(workspace.training.quests)
        let quest = try XCTUnwrap(quests.choices(history: []).first { $0.kind == .practice })
        let entry = try XCTUnwrap(ExerciseCatalog.find(try XCTUnwrap(quest.exerciseID)))
        let record = SessionRecord(id: UUID(), date: Date().addingTimeInterval(-1), sets: [], loggedSets: [LoggedSet(id: UUID(), exerciseID: entry.id, reps: entry.unit == .reps ? quest.target : 0, seconds: entry.unit == .seconds ? Double(quest.target) : 0, source: .manual, reason: .voluntary)], trainingContext: .init(owner: .init(accountID: scope.accountID, profileID: scope.profileID), age: workspace.profile.profile?.programmePreferences?.ageContext))
        workspace.training.persist(record)
        XCTAssertTrue(try quests.claim(quest, history: workspace.training.history))
        try workspace.training.clearHistory()
        XCTAssertEqual(quests.archive.totalXP, 0)
        XCTAssertTrue(quests.archive.retiredPeriods.contains(quest.periodID))
        let client = QuestNotificationFake()
        let reminders = RewardReminderStore(scope: scope, profile: workspace.profile, rewards: workspace.training.rewards, programme: workspace.programme, client: client)
        workspace.training.rewardReminders = reminders
        try workspace.training.rewards.schedule(startHour: 10, at: Date())
        try await reminders.setConsent(true)
        XCTAssertFalse(client.added.isEmpty)
        workspace.training.setAccountActive(false)
        await reminders.refresh()
        XCTAssertTrue(client.added.isEmpty)
        workspace.training.setAccountActive(true)
        await reminders.refresh()
        XCTAssertFalse(client.added.isEmpty)
    }
}

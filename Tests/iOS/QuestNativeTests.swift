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
        let store = QuestStore(scope: scope, profile: profile, programme: programme, history: [])
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
        let reopened = QuestStore(scope: scope, profile: profile, programme: programme, history: [])
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

@MainActor private final class SuspendedQuestNotificationClient: RewardNotificationClient {
    var pending: [String: XPReminder] = [:]
    var held: CheckedContinuation<Void, Never>?
    var shouldHold = false
    var peakPending = 0
    let unrelated = ["unrelated.medication"]
    func authorized() async -> Bool { true }
    func requestAuthorization() async throws -> Bool { true }
    func pendingIDs() async -> [String] { unrelated + Array(pending.keys) }
    func remove(ids: [String]) { for id in ids { pending.removeValue(forKey: id) } }
    func add(_ reminder: XPReminder) async throws {
        if shouldHold {
            shouldHold = false
            await withCheckedContinuation { held = $0 }
        }
        pending[reminder.id] = reminder
        peakPending = max(peakPending, pending.count + unrelated.count)
    }
}
extension QuestNativeTests {
    func testLateOverlappingRefreshCannotDeleteCurrentReminderPair() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let scope = AccountDataScope(accountID: UUID(), profileID: UUID(), root: root)
        let profile = NativeProfileStore(url: scope.file("profile.json"))
        try profile.save(LocalProfile(programmePreferences: .init(goals: [.balance], weekdays: [1], ageContext: .init(ageYears: 30, guardianManaged: false))))
        let programme = ProgrammeStore(scope: scope, profile: profile)
        let rewards = NativeRewardsStore(url: scope.file("rewards.json"), createdAt: Date().addingTimeInterval(-86400))
        try rewards.schedule(startHour: 10, at: Date())
        let client = SuspendedQuestNotificationClient()
        let store = RewardReminderStore(scope: scope, profile: profile, rewards: rewards, programme: programme, client: client)
        try await store.setConsent(true)
        let expectedDates = Set(client.pending.values.map(\.date))
        client.shouldHold = true
        let first = Task { await store.refresh() }
        for _ in 0..<100 { if client.held != nil { break }; await Task.yield() }
        XCTAssertNotNil(client.held)
        var replacementStarted = false
        let replacement = Task { replacementStarted = true; await store.refresh() }
        for _ in 0..<100 { if replacementStarted { break }; await Task.yield() }
        client.held?.resume(); client.held = nil
        await first.value; await replacement.value
        XCTAssertEqual(Set(client.pending.values.map(\.date)), expectedDates)
        XCTAssertEqual(client.pending.count, expectedDates.count)
        let ids = await client.pendingIDs()
        XCTAssertTrue(ids.contains("unrelated.medication")); XCTAssertLessThan(ids.count, 64)
        XCTAssertEqual(store.scheduledCount, client.pending.count)
        XCTAssertLessThanOrEqual(client.peakPending, 29)
        client.shouldHold = true
        let pendingRefresh = Task { await store.refresh() }
        for _ in 0..<100 { if client.held != nil { break }; await Task.yield() }
        XCTAssertNotNil(client.held)
        let disable = Task { try await store.setConsent(false) }
        for _ in 0..<100 { if !store.consent { break }; await Task.yield() }
        XCTAssertFalse(store.consent) // OFF is immediate even while an OS add has not settled.
        client.held?.resume(); client.held = nil
        await pendingRefresh.value; try await disable.value
        XCTAssertTrue(client.pending.isEmpty)
        XCTAssertEqual(store.scheduledCount, 0)
        let remaining = await client.pendingIDs()
        XCTAssertEqual(remaining, ["unrelated.medication"])
    }
    func testTravelAwardsAdvertisedLocalWindowAndSchedulesLocalTomorrowPreservingPastEvent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
        var london = Calendar(identifier: .gregorian); london.timeZone = TimeZone(identifier: "Europe/London")!
        var newYork = london; newYork.timeZone = TimeZone(identifier: "America/New_York")!
        let store = NativeRewardsStore(url: root.appendingPathComponent("rewards.json"), createdAt: date("2026-10-28T12:00:00Z"), calendar: london)
        try store.schedule(startHour: 10, at: date("2026-10-28T12:00:00Z"), calendar: london)
        func record(_ when: Date) -> SessionRecord { .init(id: UUID(), date: when, sets: [], loggedSets: [.init(id: UUID(), exerciseID: "catCow", reps: 6, seconds: 0, source: .manual, reason: .voluntary)]) }
        let old = record(date("2026-10-29T10:30:00Z"))
        try store.award(record: old, before: [], history: [old], completedAt: old.date, calendar: london)
        let original = store.ledger.events
        let advertised = XPReminderSchedule.make(ledger: store.ledger, owner: .init(accountID: UUID(), profileID: UUID()), age: try .init(ageYears: 30, guardianManaged: false), consent: true, authorized: true, now: date("2026-11-02T05:00:00Z"), calendar: newYork)
        let start = try XCTUnwrap(advertised.first { !$0.isBefore }?.date)
        XCTAssertEqual(newYork.component(.hour, from: start), 10)
        let travelled = record(start.addingTimeInterval(1800))
        try store.award(record: travelled, before: [old], history: [old, travelled], completedAt: travelled.date, calendar: newYork)
        XCTAssertGreaterThan(try XCTUnwrap(store.ledger.events.last).bonusXP, 0)
        XCTAssertEqual(Array(store.ledger.events.prefix(original.count)), original)
        let localLateEvening = date("2026-11-03T04:30:00Z")
        try store.schedule(startHour: 14, at: localLateEvening, calendar: london)
        try store.schedule(startHour: 12, at: localLateEvening, calendar: newYork)
        XCTAssertEqual(store.ledger.windowChanges.last?.effectiveAt, date("2026-11-03T05:00:00Z"))
        XCTAssertEqual(store.ledger.window(at: date("2026-11-05T15:00:00Z"))?.startHour, 12)
        XCTAssertEqual(store.ledger.events, original + [try XCTUnwrap(store.ledger.events.last)])
    }
}

extension QuestNativeTests {
    func testOwnedLegacyBenchmarkMigrationIsFrozenOnDiskAndLateUnknownImportsCannotEarn() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        func scope() throws -> AccountDataScope {
            let result = AccountDataScope(accountID: UUID(), profileID: UUID(), root: root)
            try NativeProfileStore(url: result.file("profile.json")).save(LocalProfile(programmePreferences: .init(goals: [.balance], weekdays: [1], ageContext: .init(ageYears: 15, guardianManaged: true))))
            return result
        }
        func legacy() -> [SessionRecord] {
            (0..<3).map { index in .init(id: UUID(), date: Date().addingTimeInterval(Double(index - 4) * 86400), sets: [], loggedSets: [.init(id: UUID(), exerciseID: "catCow", reps: 6, seconds: 0, source: .manual, reason: .voluntary)]) }
        }
        func earned(_ workspace: AccountWorkspace) throws -> Bool {
            let history = try XCTUnwrap(workspace.training.quests).benchmarkHistory(workspace.training.history)
            return SkillCurriculum.evaluate(profile: try XCTUnwrap(workspace.profile.profile), history: history).node("catCow")?.state == .earned
        }
        let existing = try scope(), history = HistoryStore(url: existing.file("history.json"))
        for record in legacy() { try history.save(record) }
        let original = try AccountWorkspace(scope: existing)
        XCTAssertTrue(try earned(original)); original.suspend()
        let reopened = try AccountWorkspace(scope: existing)
        XCTAssertTrue(try earned(reopened)); reopened.suspend()
        try history.clear()
        for record in legacy() { try history.save(record) }
        let imported = try AccountWorkspace(scope: existing)
        XCTAssertFalse(try earned(imported)); imported.suspend()
        let empty = try scope()
        let first = try AccountWorkspace(scope: empty)
        XCTAssertNotNil(first.training.quests?.archive.benchmarkPolicy)
        first.suspend()
        for record in legacy() { try HistoryStore(url: empty.file("history.json")).save(record) }
        let afterEmpty = try AccountWorkspace(scope: empty)
        XCTAssertFalse(try earned(afterEmpty)); afterEmpty.suspend()
        let corrupt = try scope()
        for record in legacy() { try HistoryStore(url: corrupt.file("history.json")).save(record) }
        try Data("unreadable-original".utf8).write(to: corrupt.file("quests.json"))
        let unreadable = try AccountWorkspace(scope: corrupt)
        XCTAssertFalse(try earned(unreadable))
        XCTAssertEqual(try String(contentsOf: corrupt.file("quests.json"), encoding: .utf8), "unreadable-original")
        unreadable.suspend()
        let unwritable = try scope()
        let originalArchive = try JSONEncoder().encode(QuestArchive(owner: .init(accountID: unwritable.accountID, profileID: unwritable.profileID)))
        try originalArchive.write(to: unwritable.file("quests.json"))
        let profile = NativeProfileStore(url: unwritable.file("profile.json"))
        let programme = ProgrammeStore(scope: unwritable, profile: profile)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: unwritable.folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: unwritable.folder.path) }
        let failedMigration = QuestStore(scope: unwritable, profile: profile, programme: programme, history: legacy())
        XCTAssertNotNil(failedMigration.error)
        XCTAssertTrue(failedMigration.benchmarkHistory(legacy()).isEmpty)
        XCTAssertEqual(try Data(contentsOf: unwritable.file("quests.json")), originalArchive)
    }
}

extension QuestNativeTests {
    func testUnavailableHistoryDefersMigrationUntilOriginalBytesRestoreThroughReopenOrSave() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for recoverBySaving in [false, true] {
            let scope = AccountDataScope(accountID: UUID(), profileID: UUID(), root: root)
            let owner = WorkoutOwner(accountID: scope.accountID, profileID: scope.profileID)
            try NativeProfileStore(url: scope.file("profile.json")).save(LocalProfile(programmePreferences: .init(goals: [.balance], weekdays: [1], ageContext: .init(ageYears: 15, guardianManaged: true))))
            let original: [SessionRecord] = (0..<3).map { index in
                .init(id: UUID(), date: Date().addingTimeInterval(Double(index - 4) * 86400), sets: [], loggedSets: [.init(id: UUID(), exerciseID: "catCow", reps: 6, seconds: 0, source: .manual, reason: .voluntary)])
            }
            try JSONEncoder().encode(original).write(to: scope.file("history.json"))
            let originalBytes = try Data(contentsOf: scope.file("history.json"))
            XCTAssertEqual(try HistoryStore(url: scope.file("history.json")).load(), original)
            let questBytes = try JSONEncoder().encode(QuestArchive(owner: owner))
            try questBytes.write(to: scope.file("quests.json"))
            let corrupt = Data("temporarily unreadable history".utf8)
            try corrupt.write(to: scope.file("history.json"))
            let unavailable = try AccountWorkspace(scope: scope)
            XCTAssertFalse(unavailable.training.historyAvailable)
            XCTAssertNil(unavailable.training.quests?.archive.benchmarkPolicy)
            XCTAssertTrue(unavailable.training.quests?.benchmarkHistory(original).isEmpty == true)
            XCTAssertEqual(try Data(contentsOf: scope.file("history.json")), corrupt)
            XCTAssertEqual(try Data(contentsOf: scope.file("quests.json")), questBytes)
            try originalBytes.write(to: scope.file("history.json"))
            let late = SessionRecord(id: UUID(), date: Date(), sets: [], loggedSets: [.init(id: UUID(), exerciseID: "catCow", reps: 6, seconds: 0, source: .manual, reason: .voluntary)])
            let restored: AccountWorkspace
            if recoverBySaving {
                unavailable.training.persist(late)
                restored = unavailable
            } else {
                unavailable.suspend()
                restored = try AccountWorkspace(scope: scope)
                restored.training.persist(late)
            }
            XCTAssertTrue(restored.training.historyAvailable)
            let quests = try XCTUnwrap(restored.training.quests)
            let qualified = quests.benchmarkHistory(restored.training.history)
            XCTAssertEqual(Set(qualified.map(\.id)), Set(original.map(\.id)))
            XCTAssertEqual(SkillCurriculum.evaluate(profile: try XCTUnwrap(restored.profile.profile), history: qualified).node("catCow")?.state, .earned)
            XCTAssertFalse(qualified.contains { $0.id == late.id })
            restored.suspend()
            let reopened = try AccountWorkspace(scope: scope)
            XCTAssertEqual(Set(try XCTUnwrap(reopened.training.quests).benchmarkHistory(reopened.training.history).map(\.id)), Set(original.map(\.id)))
            reopened.suspend()
        }
    }
}

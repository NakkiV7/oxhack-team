import XCTest
@testable import Spottr

@MainActor final class ConsentedAnalyticsStoreTests: XCTestCase {
    func testAlternatingProfilesShareRegularBudgetAndTwoPreviousWeekFinalSlots() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let start = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-02T00:00:00Z"))
        var sent: [CoarseAnalyticsSnapshot] = []
        let sender: ConsentedAnalyticsStore.Sender = { request in
            sent.append(try JSONDecoder().decode(CoarseAnalyticsSnapshot.self, from: XCTUnwrap(request.httpBody)))
            return 202
        }
        let first = try budgetStore(root: root, send: sender), second = try budgetStore(root: root, send: sender)
        try first.setConsent(.usage, enabled: true); try second.setConsent(.usage, enabled: true)
        for hour in 0..<168 {
            let current = hour.isMultiple(of: 2) ? first : second
            first.setActive(hour.isMultiple(of: 2)); second.setActive(!hour.isMultiple(of: 2))
            let date = start.addingTimeInterval(Double(hour) * 3600)
            current.feature(hour.isMultiple(of: 2) ? "today" : "coach", at: date)
            await current.flush(at: date)
        }
        print("TASK10_ANALYTICS_ALTERNATING_WEEK_SENDS_\(sent.count)")
        XCTAssertLessThanOrEqual(sent.count, 14, "One installation's regular weekly transmissions must leave room for final totals")
        XCTAssertEqual(Set(sent.map(\.tag)).count, 1)
        XCTAssertTrue(sent.allSatisfy { $0.counts["today"] == nil || $0.counts["coach"] == nil }, "Profiles must not merge counters")
        first.setActive(true); second.setActive(false)
        await first.flush(at: start.addingTimeInterval(168 * 3600))
        first.setActive(false); second.setActive(true)
        await second.flush(at: start.addingTimeInterval(180 * 3600))
        XCTAssertLessThanOrEqual(sent.count, 16)
        XCTAssertTrue(first.pending.isEmpty); XCTAssertTrue(second.pending.isEmpty)
        XCTAssertEqual(sent.suffix(2).map { $0.counts.values.reduce(0, +) }, [84, 84], "Final snapshots keep each profile's actual cumulative counts")
        second.feature("coach", at: start.addingTimeInterval(167 * 3600))
        let finalCount = sent.count
        await second.flush(at: start.addingTimeInterval(192 * 3600))
        XCTAssertEqual(sent.count, finalCount, "The two reserved final slots are bounded too")
    }
    func testAmbiguousAttemptReservesSharedCooldownAcrossProfileAndStoreRecreation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-02T00:00:00Z"))
        var attempts = 0
        let sender: ConsentedAnalyticsStore.Sender = { _ in attempts += 1; throw URLError(.networkConnectionLost) }
        let first = try budgetStore(root: root, send: sender), second = try budgetStore(root: root, send: sender)
        try first.setConsent(.usage, enabled: true); first.feature("today", at: date); await first.flush(at: date)
        first.setActive(false)
        try second.setConsent(.usage, enabled: true); second.feature("coach", at: date.addingTimeInterval(3600)); await second.flush(at: date.addingTimeInterval(3600))
        XCTAssertEqual(attempts, 1, "A different profile must not spend the same installation's ambiguous transmission budget")
        second.setActive(false)
        let reopened = ConsentedAnalyticsStore(scope: first.scope, profile: first.profile, send: sender)
        await reopened.flush(at: date.addingTimeInterval(2 * 3600))
        XCTAssertEqual(attempts, 1, "A process-style reconstruction must retain the shared cooldown")
        await reopened.flush(at: date.addingTimeInterval(12 * 3600))
        XCTAssertEqual(attempts, 2)
    }
    func testUnpersistableSharedReservationNeverSendsOrDropsQueuedCounts() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var attempts = 0
        let store = try budgetStore(root: root, send: { _ in attempts += 1; return 202 })
        try store.setConsent(.usage, enabled: true); store.feature("today")
        let installation = root.appendingPathComponent("analytics-installation.json")
        try FileManager.default.removeItem(at: installation)
        try FileManager.default.createDirectory(at: installation, withIntermediateDirectories: false)
        await store.flush()
        XCTAssertEqual(attempts, 0, "Never post when the shared reservation cannot be persisted")
        XCTAssertEqual(store.pending.count, 1)
    }
    private func budgetStore(root: URL, send: @escaping ConsentedAnalyticsStore.Sender) throws -> ConsentedAnalyticsStore {
        let scope = AccountDataScope(accountID: UUID(), profileID: UUID(), root: root)
        let profile = NativeProfileStore(url: scope.file("profile.json"))
        try profile.save(LocalProfile(programmePreferences: .init(goals: [.balance], weekdays: [1], ageContext: .init(ageYears: 30, guardianManaged: false))))
        return ConsentedAnalyticsStore(scope: scope, profile: profile, send: send)
    }
    func testProtectedConsentPersistsAndSeparateNoCredentialQueueRetriesThenRevokes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let scope = AccountDataScope(accountID: UUID(), profileID: UUID(), root: root)
        let profile = NativeProfileStore(url: scope.file("profile.json"))
        try profile.save(LocalProfile(programmePreferences: .init(goals: [.strength], weekdays: [1], ageContext: .init(ageYears: 30, guardianManaged: false))))
        var requests: [URLRequest] = []
        let store = ConsentedAnalyticsStore(scope: scope, profile: profile, send: { request in requests.append(request); throw URLError(.notConnectedToInternet) })
        try store.setConsent(.usage, enabled: true)
        store.feature("today")
        XCTAssertEqual(store.pending.count, 1)
        await store.flush()
        let request = try XCTUnwrap(requests.first)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization")); XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertFalse(request.httpShouldHandleCookies)
        XCTAssertEqual(request.url?.path, "/api/analytics/v1/weekly")
        XCTAssertEqual(store.pending.count, 1)
        await store.flush(); XCTAssertEqual(requests.count, 1, "Backoff must survive immediate retries")
        let reopened = ConsentedAnalyticsStore(scope: scope, profile: profile, send: {_ in 202})
        XCTAssertTrue(reopened.ledger.usage)
        XCTAssertEqual(reopened.pending.count, 1)
        try reopened.setConsent(.usage, enabled: false)
        XCTAssertTrue(reopened.pending.isEmpty)
        XCTAssertFalse(ConsentedAnalyticsStore(scope: scope, profile: profile).ledger.usage)
    }
    func testActualWorkspaceCompletionCapturesConsentAndExcludesMidWorkoutReconsent() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let scope = AccountDataScope(accountID: UUID(), profileID: UUID(), root: root)
        let age = try TrainingAgeContext(ageYears: 30, guardianManaged: false)
        try NativeProfileStore(url: scope.file("profile.json")).save(LocalProfile(programmePreferences: .init(goals: [.strength], weekdays: [1], ageContext: age)))
        let workspace = try AccountWorkspace(scope: scope)
        let analytics = try XCTUnwrap(workspace.training.analytics)
        try analytics.setConsent(.workout, enabled: true)
        let plan = try CoachSavedPlan.catalogue(exerciseID: "squat", sets: 1, target: 3, restSeconds: 30)
        let context = SessionTrainingContext(owner: .init(accountID: scope.accountID, profileID: scope.profileID), age: age)
        workspace.training.beginAuthorizedPlan(plan, availableSupport: [], trainingContext: context)
        workspace.training.beginConfiguredSet(); workspace.training.setConfiguredReps(2); workspace.training.endSet()
        try analytics.setConsent(.workout, enabled: false); try analytics.setConsent(.workout, enabled: true)
        workspace.training.finish()
        XCTAssertTrue(analytics.pending.isEmpty)
        workspace.training.beginAuthorizedPlan(plan, availableSupport: [], trainingContext: context)
        workspace.training.beginConfiguredSet(); workspace.training.setConfiguredReps(2); workspace.training.endSet(); workspace.training.finish()
        XCTAssertEqual(analytics.pending.first?.counts["sessions"], 1)
        workspace.suspend()
    }

    func testAgeTransitionCannotResurrectEarlierAdultConsent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let scope = AccountDataScope(accountID: UUID(), profileID: UUID(), root: root)
        let profile = NativeProfileStore(url: scope.file("profile.json"))
        func save(_ years: Int) throws { try profile.save(LocalProfile(programmePreferences: .init(goals: [.balance], weekdays: [1], ageContext: .init(ageYears: years, guardianManaged: years < 18)))) }
        try save(30)
        try ConsentedAnalyticsStore(scope: scope, profile: profile).setConsent(.workout, enabled: true)
        try save(12)
        XCTAssertNil(ConsentedAnalyticsStore(scope: scope, profile: profile).ledger.capture(.workout))
        try save(30)
        XCTAssertNil(ConsentedAnalyticsStore(scope: scope, profile: profile).ledger.capture(.workout))
    }
    func testProfilesShareWeeklyInstallationTagAndOrderButNeverCountersOrConsent() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var requests: [URLRequest] = []
        func make() throws -> ConsentedAnalyticsStore {
            let scope = AccountDataScope(accountID: UUID(), profileID: UUID(), root: root)
            let profile = NativeProfileStore(url: scope.file("profile.json"))
            try profile.save(LocalProfile(programmePreferences: .init(goals: [.balance], weekdays: [1], ageContext: .init(ageYears: 30, guardianManaged: false))))
            return ConsentedAnalyticsStore(scope: scope, profile: profile, send: { requests.append($0); return 202 })
        }
        let first = try make(), second = try make()
        try first.setConsent(.usage, enabled: true); first.feature("today")
        XCTAssertFalse(second.ledger.usage); XCTAssertTrue(second.pending.isEmpty)
        try second.setConsent(.usage, enabled: true); second.feature("coach")
        let a = try XCTUnwrap(first.pending.first), b = try XCTUnwrap(second.pending.first)
        XCTAssertEqual(a.tag, b.tag); XCTAssertLessThan(a.sequence, b.sequence)
        XCTAssertNil(b.counts["today"]); XCTAssertNil(a.counts["coach"])
        first.setActive(false); await first.flush(); XCTAssertTrue(requests.isEmpty)
        await second.flush(); XCTAssertEqual(requests.count, 1)
        XCTAssertTrue(second.pending.isEmpty)
    }

}

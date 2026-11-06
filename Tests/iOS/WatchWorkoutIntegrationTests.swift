import XCTest
import SwiftUI
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
}

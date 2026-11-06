import Foundation
import Observation
import UserNotifications

@MainActor protocol RewardNotificationClient {
    func authorized() async -> Bool
    func requestAuthorization() async throws -> Bool
    func pendingIDs() async -> [String]
    func remove(ids: [String])
    func add(_ reminder: XPReminder) async throws
}
@MainActor final class LocalRewardNotificationClient: RewardNotificationClient {
    private let center = UNUserNotificationCenter.current()
    func authorized() async -> Bool {
        let status = await center.notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional || status == .ephemeral
    }
    func requestAuthorization() async throws -> Bool { try await center.requestAuthorization(options: [.alert, .sound]) }
    func pendingIDs() async -> [String] { await center.pendingNotificationRequests().map(\.identifier) }
    func remove(ids: [String]) { center.removePendingNotificationRequests(withIdentifiers: ids) }
    func add(_ reminder: XPReminder) async throws {
        let content = UNMutableNotificationContent()
        content.title = reminder.isBefore ? "Your optional XP window starts in an hour" : "Your optional XP window has started"
        content.body = "Train only when it suits you. Rest is always a good choice."
        content.sound = .default
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.date)
        components.timeZone = calendar.timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try await center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
    }
}
@MainActor @Observable final class RewardReminderStore {
    enum Failure: Error { case unavailable }
    private(set) var consent = false
    private(set) var status = "Reminders off"
    private(set) var scheduledCount = 0
    private let scope: AccountDataScope
    private let profile: NativeProfileStore
    private let rewards: NativeRewardsStore
    private let programme: ProgrammeStore
    private let client: any RewardNotificationClient
    private let age: TrainingAgeContext?
    private var active = true
    private let instanceID = UUID()
    private var generation = UUID()
    private var refreshTask: Task<Void, Never>?
    private static var owners: [String: UUID] = [:]
    private var prefix: String { XPReminderSchedule.prefix(owner: .init(accountID: scope.accountID, profileID: scope.profileID)) }
    private var valid: Bool { active && profile.permitsPolicyCallbacks && age == profile.profile?.programmePreferences?.ageContext && age?.allowsTimePressureRewards == true }
    init(scope: AccountDataScope, profile: NativeProfileStore, rewards: NativeRewardsStore, programme: ProgrammeStore, client: any RewardNotificationClient) {
        self.scope = scope; self.profile = profile; self.rewards = rewards; self.programme = programme; self.client = client
        age = profile.profile?.programmePreferences?.ageContext
        consent = (try? JSONDecoder().decode(Bool.self, from: Data(contentsOf: scope.file("xp-reminders.json")))) ?? false
        Self.owners[prefix] = instanceID
    }
    func setConsent(_ value: Bool) async throws {
        guard valid else { throw Failure.unavailable }
        generation = UUID()
        let request = generation
        try ProtectedLocalStorage.write(JSONEncoder().encode(value), to: scope.file("xp-reminders.json"))
        consent = value
        if value {
            _ = try await client.requestAuthorization()
            guard valid, current(request) else { return }
        }
        await refresh()
    }
    func refresh() async {
        guard Self.owners[prefix] == instanceID else { return }
        generation = UUID()
        // An OS add already handed off cannot be cancelled or rolled back by cancelling a Task.
        // Settle it (including stale cleanup) before installing the newest coalesced schedule.
        if let refreshTask { await refreshTask.value; return }
        let worker = Task { @MainActor in
            repeat {
                let request = generation
                await replaceSchedule(request)
                if generation == request { break }
            } while Self.owners[prefix] == instanceID
            refreshTask = nil
        }
        refreshTask = worker
        await worker.value
    }
    private func replaceSchedule(_ request: UUID) async {
        let ids = await client.pendingIDs()
        guard current(request) else { return }
        client.remove(ids: ids.filter { $0.hasPrefix(prefix) })
        scheduledCount = 0
        guard valid, consent else { status = "Reminders off"; return }
        let allowed = await client.authorized()
        guard valid, current(request) else { return }
        guard allowed else { status = "Notifications are not allowed. Change this in iPhone Settings."; return }
        let schedule = XPReminderSchedule.make(ledger: rewards.ledger, owner: .init(accountID: scope.accountID, profileID: scope.profileID), age: age, consent: consent, authorized: allowed, now: programme.referenceDate, calendar: programme.localCalendar, unrelatedPendingCount: ids.filter { !$0.hasPrefix(prefix) }.count)
        do {
            for entry in schedule {
                let reminder = XPReminder(id: entry.id + "." + instanceID.uuidString, date: entry.date, startsAt: entry.startsAt, isBefore: entry.isBefore)
                guard valid, current(request) else { return }
                try await client.add(reminder)
                guard valid, current(request) else { client.remove(ids: [reminder.id]); return }
                scheduledCount += 1
            }
            status = schedule.isEmpty ? "Choose a bonus window to schedule reminders." : "\(scheduledCount) upcoming reminders scheduled. Delivery depends on permission and Focus."
        } catch { status = "Some reminders couldn’t be scheduled. Try again." }
    }
    func setActive(_ value: Bool) {
        active = value
        generation = UUID()
        Task { await refresh() }
    }
    func suspend() { setActive(false) }
    private func current(_ request: UUID) -> Bool { generation == request && Self.owners[prefix] == instanceID }
}

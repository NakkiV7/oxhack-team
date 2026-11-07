import SwiftUI
import CryptoKit

@MainActor @Observable final class WatchSharingStore {
    private struct Saved: Codable {
        let owner: WorkoutOwner
        let age: TrainingAgeContext?
        let policyID: UUID
        let enabled: Bool
    }
    let owner: WorkoutOwner
    let age: TrainingAgeContext?
    private let url: URL
    private(set) var enabled = false
    private(set) var persistencePending = false
    // Retain known OFF across same-owner workspace reconstruction when disk is
    // temporarily unavailable. This is not a claim of durable persistence.
    private static var pendingOff: [WorkoutOwner] = []
    static let pendingPersistenceMessage = "Sharing is off now. Saving is pending and will retry while this profile is open."
    private(set) var policyID = UUID()
    private var active = true
    var onChange: (() -> Void)?
    init(scope: AccountDataScope, age: TrainingAgeContext?) throws {
        owner = .init(accountID: scope.accountID, profileID: scope.profileID)
        self.age = age; url = scope.file("watch-sharing.json")
        if FileManager.default.fileExists(atPath: url.path) {
            let saved = try JSONDecoder().decode(Saved.self, from: Data(contentsOf: url))
            guard saved.owner == owner else { throw AccountFailure.invalidResponse }
            if saved.age == age {
                persistencePending = Self.pendingOff.contains(owner)
                enabled = saved.enabled && !persistencePending; policyID = saved.policyID; return
            }
        }
        try save(enabled: false)
    }
    func setActive(_ value: Bool) { active = value }
    func setEnabled(_ enabled: Bool) throws {
        guard active else { throw AccountFailure.reauthenticate }
        if !enabled {
            self.enabled = false; persistencePending = true
            if !Self.pendingOff.contains(owner) { Self.pendingOff.append(owner) }
            onChange?() // Withdraw effective authority before any fallible storage.
            try retryPendingPersistence()
        } else {
            try retryPendingPersistence()
            try save(enabled: true)
        }
        onChange?()
    }
    func retryPendingPersistence() throws {
        guard active else { throw AccountFailure.reauthenticate }
        if persistencePending { try save(enabled: false) }
    }
    private func save(enabled: Bool) throws {
        try ProtectedLocalStorage.write(JSONEncoder().encode(Saved(owner: owner, age: age, policyID: policyID, enabled: enabled)), to: url)
        self.enabled = enabled; persistencePending = false
        Self.pendingOff.removeAll { $0 == owner }
    }
}

struct WatchImportReceipt: Codable {
    enum Stage: String, Codable { case prepared, historySaved, acknowledged, deleted }
    let digest: Data
    var before: [SessionRecord]
    var stage: Stage
}
struct WatchHistoryDeletion: Codable {
    let owner: WorkoutOwner
    let sessionIDs: Set<UUID>
    let receiptIDs: Set<UUID>
    let historyDigest: Data?
    let requestedAt: Date
}
struct WatchImportReceipts {
    let url: URL
    func load() throws -> [UUID: WatchImportReceipt] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        return try JSONDecoder().decode([UUID: WatchImportReceipt].self, from: Data(contentsOf: url))
    }
    func save(_ receipts: [UUID: WatchImportReceipt]) throws {
        try ProtectedLocalStorage.write(JSONEncoder().encode(receipts), to: url)
    }
    private var deletionURL: URL { url.deletingLastPathComponent().appendingPathComponent("watch-history-deletion.json") }
    func deletion(owner: WorkoutOwner) throws -> WatchHistoryDeletion? {
        guard FileManager.default.fileExists(atPath: deletionURL.path) else { return nil }
        let value = try JSONDecoder().decode(WatchHistoryDeletion.self, from: Data(contentsOf: deletionURL))
        guard value.owner == owner, value.requestedAt.timeIntervalSince1970.isFinite else { throw AccountFailure.invalidResponse }
        return value
    }
    func beginDeletion(owner: WorkoutOwner, history: HistoryStore) throws {
        let previous = try deletion(owner: owner), receipts = try load()
        let data = FileManager.default.fileExists(atPath: history.url.path) ? try Data(contentsOf: history.url) : nil
        // Explicit clear remains able to remove an unchanged corrupt history file.
        // Its byte identity prevents a later different file being deleted wholesale.
        let records = data.flatMap { try? JSONDecoder().decode([SessionRecord].self, from: $0) } ?? []
        let receiptIDs = Set(receipts.keys).union(previous?.receiptIDs ?? [])
        let intent = WatchHistoryDeletion(owner: owner, sessionIDs: Set(records.map(\.id)).union(receiptIDs).union(previous?.sessionIDs ?? []),
            receiptIDs: receiptIDs, historyDigest: data.map { Data(SHA256.hash(data: $0)) }, requestedAt: Date())
        try ProtectedLocalStorage.write(JSONEncoder().encode(intent), to: deletionURL)
    }
    func removeHistory(_ intent: WatchHistoryDeletion, from history: HistoryStore) throws -> [SessionRecord] {
        let data = FileManager.default.fileExists(atPath: history.url.path) ? try Data(contentsOf: history.url) : nil
        if data.map({ Data(SHA256.hash(data: $0)) }) == intent.historyDigest {
            try history.clear(); return []
        }
        return try history.remove(ids: intent.sessionIDs)
    }
    func finishDeletion(_ intent: WatchHistoryDeletion) throws {
        var values = try load()
        for id in intent.receiptIDs { values[id]?.stage = .deleted; values[id]?.before = [] }
        try save(values)
        try FileManager.default.removeItem(at: deletionURL)
    }
    static func digest(_ journal: WatchWorkoutJournal) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return Data(SHA256.hash(data: try encoder.encode(journal)))
    }
}

private struct WatchSharingEnvironmentKey: EnvironmentKey {
    static let defaultValue: WatchSharingStore? = nil
}
extension EnvironmentValues {
    var watchSharing: WatchSharingStore? {
        get { self[WatchSharingEnvironmentKey.self] }
        set { self[WatchSharingEnvironmentKey.self] = newValue }
    }
}

@MainActor final class WatchWorkoutBridge {
    private weak var workspace: AccountWorkspace?
    private weak var account: NativeAccountStore?
    private let membership: MembershipCoordinator
    private let isCurrent: () -> Bool
    private let sequenceURL: URL
    private(set) var lastTransport: WatchProgrammeTransport?
    private var refreshingAuthority = false
    private var lastAuthorityAttempt = Date.distantPast
    init(workspace: AccountWorkspace, account: NativeAccountStore, membership: MembershipCoordinator, isCurrent: @escaping () -> Bool) {
        self.workspace = workspace; self.account = account; self.membership = membership; self.isCurrent = isCurrent
        sequenceURL = workspace.scope.root.appendingPathComponent("watch-transport-sequence.json")
        workspace.watchSharing.onChange = { [weak self] in self?.workspace?.training.publish() }
        workspace.training.companion.onRequest = { [weak self] in
            Task { @MainActor in self?.refreshForWatchRequest() }
        }
        workspace.training.companion.onWorkout = { [weak self] journal in
            Task { @MainActor in
                guard let self, let workspace = self.workspace, self.isCurrent(), workspace.profile.permitsPolicyCallbacks else { return }
                do {
                    if try workspace.training.importWatchWorkout(journal) {
                        workspace.training.companion.acknowledgeWorkout(.init(id: journal.id, owner: journal.grant.owner))
                    }
                } catch { workspace.training.error = "Watch workout is still saved on your Watch. Open its training profile and retry when local storage is available." }
            }
        }
    }
    /// A paired reconnect/request may refresh authority, but only an actual account
    /// response can advance the persisted verification date. Receipt rereads cannot.
    func refreshForWatchRequest() {
        guard let workspace, let account, isCurrent(), workspace.profile.permitsPolicyCallbacks else { return }
        workspace.training.publish()
        let date = Date()
        guard workspace.watchSharing.enabled, !refreshingAuthority,
              date.timeIntervalSince(lastAuthorityAttempt) >= 60,
              account.lastTrustedVerification.map({ date.timeIntervalSince($0) >= 86400 }) ?? true else { return }
        refreshingAuthority = true; lastAuthorityAttempt = date
        let generation = account.authenticationGeneration
        Task { [weak self] in
            guard let self else { return }
            defer { self.refreshingAuthority = false }
            await account.restore()
            guard self.isCurrent(), self.workspace === workspace, workspace.profile.permitsPolicyCallbacks,
                  workspace.watchSharing.enabled, account.authenticationGeneration == generation,
                  account.accountID == workspace.scope.accountID else { return }
            await self.membership.refreshEntitlements()
            guard self.isCurrent(), self.workspace === workspace, workspace.profile.permitsPolicyCallbacks,
                  workspace.watchSharing.enabled, account.authenticationGeneration == generation,
                  account.accountID == workspace.scope.accountID else { return }
            workspace.training.publish()
        }
    }
    func publish(snapshot: CompanionSnapshot?, context: SessionTrainingContext?, active: Bool = true) {
        guard let workspace else { return }
        let link = workspace.training.companion
        let owner = workspace.watchSharing.owner
        let current = active && isCurrent() && workspace.profile.permitsPolicyCallbacks
        if current {
            do {
                try workspace.watchSharing.retryPendingPersistence()
                if workspace.training.error == WatchSharingStore.pendingPersistenceMessage { workspace.training.error = nil }
            } catch { workspace.training.error = WatchSharingStore.pendingPersistenceMessage }
        }
        let sharing = current && workspace.watchSharing.enabled
        let trusted = current && account?.trusted == true && account?.accountID == owner.accountID ? owner : nil
        let access = membership.accountID == owner.accountID ? membership.access : MembershipAccess.resolve([], now: Date())
        let value = WatchProgrammeTransport.authorized(sequence: 0, owner: owner, policyID: workspace.watchSharing.policyID,
            trustedOwner: trusted, verifiedAt: account?.lastTrustedVerification, profile: workspace.profile.profile,
            sharing: sharing, membership: access, programme: workspace.programme.current, at: Date(), analyticsCapture: current ? workspace.training.analytics?.ledger.capture(.workout) : nil)
        do {
            let equivalent = lastTransport.map { previous in
                WatchProgrammeTransport(sequence: 0, owner: previous.owner, policyID: previous.policyID, age: previous.age,
                    sharing: previous.sharing, grant: previous.grant, choices: previous.choices, support: previous.support, timeZoneID: previous.timeZoneID, programmeID: previous.programmeID, programmeRevision: previous.programmeRevision) == value
            } ?? false
            if !equivalent {
                let previous = FileManager.default.fileExists(atPath: sequenceURL.path)
                    ? try JSONDecoder().decode(UInt64.self, from: Data(contentsOf: sequenceURL)) : 0
                guard previous < UInt64.max else { throw AccountFailure.invalidResponse }
                let sequence = previous + 1
                try ProtectedLocalStorage.write(JSONEncoder().encode(sequence), to: sequenceURL)
                lastTransport = .init(sequence: sequence, owner: owner, policyID: value.policyID, age: value.age,
                    sharing: value.sharing, grant: value.grant, choices: value.choices, support: value.support, timeZoneID: value.timeZoneID, programmeID: value.programmeID, programmeRevision: value.programmeRevision)
            }
            if let lastTransport { link.publishProgramme(lastTransport) }
        } catch { workspace.training.error = "Watch access could not be saved. Your existing workouts are unchanged." }
        guard sharing, let snapshot, context?.owner == owner else { link.publishScoped(nil); return }
        link.publishScoped(.init(snapshot: snapshot, owner: owner, policyID: workspace.watchSharing.policyID,
            allowsHealth: workspace.profile.profile?.programmePreferences?.ageContext?.allowsHealthIntegration == true && context?.allowsAdultCompletion == true))
    }
}

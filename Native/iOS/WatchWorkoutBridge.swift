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
    private(set) var policyID = UUID()
    private var active = true
    var onChange: (() -> Void)?
    init(scope: AccountDataScope, age: TrainingAgeContext?) throws {
        owner = .init(accountID: scope.accountID, profileID: scope.profileID)
        self.age = age; url = scope.file("watch-sharing.json")
        if FileManager.default.fileExists(atPath: url.path) {
            let saved = try JSONDecoder().decode(Saved.self, from: Data(contentsOf: url))
            guard saved.owner == owner else { throw AccountFailure.invalidResponse }
            if saved.age == age { enabled = saved.enabled; policyID = saved.policyID; return }
        }
        try save(enabled: false)
    }
    func setActive(_ value: Bool) { active = value }
    func setEnabled(_ enabled: Bool) throws {
        guard active else { throw AccountFailure.reauthenticate }
        try save(enabled: enabled); onChange?()
    }
    private func save(enabled: Bool) throws {
        try ProtectedLocalStorage.write(JSONEncoder().encode(Saved(owner: owner, age: age, policyID: policyID, enabled: enabled)), to: url)
        self.enabled = enabled
    }
}

struct WatchImportReceipt: Codable {
    enum Stage: String, Codable { case prepared, historySaved, acknowledged, deleted }
    let digest: Data
    var before: [SessionRecord]
    var stage: Stage
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
    func markDeleted() throws {
        var values = try load()
        for id in values.keys { values[id]?.stage = .deleted; values[id]?.before = [] }
        try save(values)
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
    private var lastTransport: WatchProgrammeTransport?
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
        let sharing = current && workspace.watchSharing.enabled
        let trusted = current && account?.trusted == true && account?.accountID == owner.accountID ? owner : nil
        let access = membership.accountID == owner.accountID ? membership.access : MembershipAccess.resolve([], now: Date())
        let value = WatchProgrammeTransport.authorized(sequence: 0, owner: owner, policyID: workspace.watchSharing.policyID,
            trustedOwner: trusted, verifiedAt: account?.lastTrustedVerification, profile: workspace.profile.profile,
            sharing: sharing, membership: access, programme: workspace.programme.current, at: Date())
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

import Foundation
import Observation

struct ProgrammeWriteRequest: Encodable {
    let profileSlot: UUID
    let adultEligible = true
    let cloudPlanSync = true
    let expectedRevision: Int
    let preferences: CloudProgrammePreferences
    let programme: CloudProgramme?
    enum CodingKeys: String, CodingKey { case profileSlot, adultEligible, cloudPlanSync, expectedRevision, preferences, programme }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(profileSlot, forKey: .profileSlot); try c.encode(adultEligible, forKey: .adultEligible)
        try c.encode(cloudPlanSync, forKey: .cloudPlanSync); try c.encode(expectedRevision, forKey: .expectedRevision)
        try c.encode(preferences, forKey: .preferences); try c.encode(programme, forKey: .programme)
    }
}
struct ProgrammeReadRequest: Encodable { let profileSlot: UUID; let adultEligible = true; let cloudPlanSync = true }
struct ProgrammeWithdrawRequest: Encodable { let profileSlot: UUID; let expectedRevision: Int }
struct ProgrammeWriteReply: Decodable { let profileSlot: UUID; let revision: Int; let updatedAt: Date }
struct ProgrammeReadReply: Decodable {
    let profileSlot: UUID; let revision: Int; let preferences: CloudProgrammePreferences; let programme: CloudProgramme?; let updatedAt: Date
}
struct ProgrammeWithdrawReply: Decodable { let withdrawn: Bool; let revision: Int }
@MainActor protocol ProgrammeCloudClient {
    func writePlan(_ request: ProgrammeWriteRequest) async throws -> ProgrammeWriteReply
    func readPlan(_ request: ProgrammeReadRequest) async throws -> ProgrammeReadReply
    func withdrawPlan(_ request: ProgrammeWithdrawRequest) async throws -> ProgrammeWithdrawReply
}

@MainActor @Observable final class ProgrammeSyncStore {
    private struct Saved: Codable {
        var profileSlot: UUID
        var consented: Bool
        var serverRevision: Int
        var withdrawalPending: Bool
        let policyAge: TrainingAgeContext?
    }
    private var saved: Saved
    private let programme: ProgrammeStore
    private let profile: NativeProfileStore
    private let client: any ProgrammeCloudClient
    private let isCurrent: () -> Bool
    private let hasOngoingWorkout: () -> Bool
    private let capturedAge: TrainingAgeContext?
    private var readable = true
    private var consentEpoch = UUID()
    private(set) var busy = false
    private(set) var message: String?
    private(set) var pendingRemote: ProgrammeReadReply?
    var profileSlot: UUID { saved.profileSlot }
    var consented: Bool { saved.consented && saved.policyAge == capturedAge }
    var serverRevision: Int { saved.serverRevision }
    var withdrawalPending: Bool { saved.withdrawalPending }
    private var url: URL { programme.scope.file("programme-cloud-consent.json") }
    init(programme: ProgrammeStore, profile: NativeProfileStore, client: any ProgrammeCloudClient, isCurrent: @escaping () -> Bool, hasOngoingWorkout: @escaping () -> Bool) {
        self.programme = programme; self.profile = profile; self.client = client
        self.isCurrent = isCurrent; self.hasOngoingWorkout = hasOngoingWorkout
        capturedAge = profile.profile?.programmePreferences?.ageContext
        saved = Saved(profileSlot: UUID(), consented: false, serverRevision: 0, withdrawalPending: false, policyAge: capturedAge)
        if FileManager.default.fileExists(atPath: url.path) {
            do { saved = try JSONDecoder().decode(Saved.self, from: Data(contentsOf: url)) }
            catch { readable = false; message = "Saved sync settings could not be read. They have not been replaced." }
        }
    }
    private var valid: Bool { readable && isCurrent() && profile.permitsPolicyCallbacks && capturedAge == profile.profile?.programmePreferences?.ageContext && capturedAge?.allowsCloudPlanSync == true }
    func consent() throws {
        guard valid, !busy, !withdrawalPending else { throw AccountFailure.checkpointRequired }
        consentEpoch = UUID()
        try persist(Saved(profileSlot: profileSlot, consented: true, serverRevision: serverRevision, withdrawalPending: false, policyAge: capturedAge))
        message = "Plan sync enabled for this adult profile. Choose Save to upload its configuration."
    }
    func upload() async {
        guard valid, consented, !withdrawalPending, !busy, let local = profile.profile else { return }
        let epoch = consentEpoch
        busy = true; defer { busy = false }
        do {
            let expected = serverRevision
            let reply = try await client.writePlan(.init(profileSlot: profileSlot, expectedRevision: expected,
                preferences: CloudProgrammePreferences(local.effectiveProgrammePreferences), programme: programme.current.map(CloudProgramme.init)))
            guard valid, consentEpoch == epoch, consented, reply.profileSlot == profileSlot, reply.revision == expected + 1, reply.updatedAt.timeIntervalSince1970.isFinite else { throw AccountFailure.invalidResponse }
            var next = saved; next.serverRevision = reply.revision; try persist(next)
            pendingRemote = nil; message = "Saved configuration synced. Workouts and measurements stay on this device."
        } catch { if valid { message = failure(error) } }
    }
    func read() async {
        guard valid, consented, !withdrawalPending, !busy else { return }
        let epoch = consentEpoch
        busy = true; defer { busy = false }
        do {
            let reply = try await client.readPlan(.init(profileSlot: profileSlot))
            guard valid, consentEpoch == epoch, consented, reply.profileSlot == profileSlot, reply.revision > 0, reply.updatedAt.timeIntervalSince1970.isFinite else { throw AccountFailure.invalidResponse }
            _ = try restoredProfile(reply)
            pendingRemote = reply
            message = "Saved configuration loaded for review. Choose which plan to keep."
        } catch { if valid { message = failure(error) } }
    }
    func restoreReviewed() throws {
        guard valid, consented, !busy, !hasOngoingWorkout(), let remote = pendingRemote else { throw AccountFailure.busy }
        let local = try restoredProfile(remote)
        let week = try remote.programme?.restoring(profile: local)
        try programme.restore(week, profile: local)
        try profile.save(local)
        var next = saved; next.serverRevision = remote.revision; try persist(next)
        pendingRemote = nil; message = "Saved configuration restored. Local age, comfort, measurements and history were retained."
    }
    func keepLocalReviewed() async {
        guard valid, consented, !busy, let remote = pendingRemote else { return }
        do {
            var next = saved; next.serverRevision = remote.revision; try persist(next)
            pendingRemote = nil
            await upload()
        } catch { message = failure(error) }
    }
    func linkSlot(_ slot: UUID) throws {
        guard valid, consented, !busy, !hasOngoingWorkout(), !withdrawalPending,
              slot != programme.scope.accountID, slot != programme.scope.profileID else { throw AccountFailure.busy }
        var next = saved; next.profileSlot = slot; next.serverRevision = 0; try persist(next)
        pendingRemote = nil; message = "Linked by your choice. Read and review the saved plan before restoring it."
    }
    func withdraw() async {
        guard valid else { return }
        do {
            consentEpoch = UUID()
            var next = saved; next.consented = false; next.withdrawalPending = true; try persist(next)
            pendingRemote = nil
            guard !busy else { message = "Local syncing is off. Remove the saved programme once the current request finishes."; return }
            busy = true; defer { busy = false }
            let epoch = consentEpoch, expected = serverRevision
            let reply = try await client.withdrawPlan(.init(profileSlot: profileSlot, expectedRevision: expected))
            guard valid, consentEpoch == epoch, !consented, reply.withdrawn, reply.revision == expected + 1 else { throw AccountFailure.invalidResponse }
            next.serverRevision = reply.revision; next.withdrawalPending = false; try persist(next)
            message = "Cloud configuration removed. Local programme and history are retained."
        } catch { if valid { message = "Local syncing is off. Cloud removal is still pending. Choose Remove saved programme to retry." } }
    }
    func removeSavedProgramme() async {
        guard valid, !consented, withdrawalPending, !busy else { return }
        busy = true; defer { busy = false }
        let epoch = consentEpoch
        do {
            let reply = try await client.readPlan(.init(profileSlot: profileSlot))
            guard valid, consentEpoch == epoch, !consented, withdrawalPending,
                  reply.profileSlot == profileSlot, reply.revision > 0 else { throw AccountFailure.invalidResponse }
            var revisionOnly = saved; revisionOnly.serverRevision = reply.revision; try persist(revisionOnly)
            let removed = try await client.withdrawPlan(.init(profileSlot: profileSlot, expectedRevision: reply.revision))
            guard valid, consentEpoch == epoch, !consented, removed.withdrawn, removed.revision == reply.revision + 1 else { throw AccountFailure.invalidResponse }
            revisionOnly.serverRevision = removed.revision; revisionOnly.withdrawalPending = false; try persist(revisionOnly)
            message = "Saved cloud programme removed. Local syncing remains off."
        } catch { if valid { message = "Local syncing remains off. The saved cloud programme could not be removed yet. Retry when connected." } }
    }
    private func restoredProfile(_ reply: ProgrammeReadReply) throws -> LocalProfile {
        guard let local = profile.profile else { throw AccountFailure.checkpointRequired }
        let prefs = try reply.preferences.restoringLocalPolicy(local.effectiveProgrammePreferences)
        let restored = try LocalProfile(name: local.name, weeklyTarget: local.weeklyTarget, goals: local.goals,
            baselineAbility: local.baselineAbility, bodyMeasurements: local.bodyMeasurements, comfortableExercises: local.comfortableExercises,
            weightManagementGoal: local.weightManagementGoal, onboardingRevision: local.onboardingRevision, programmePreferences: prefs)
        _ = try reply.programme?.restoring(profile: restored)
        return restored
    }
    private func persist(_ next: Saved) throws {
        guard valid else { throw AccountFailure.checkpointRequired }
        try ProtectedLocalStorage.write(JSONEncoder().encode(next), to: url); saved = next
    }
    private func failure(_ error: Error) -> String {
        if case AccountFailure.service(409, _) = error { return "Another device changed the saved programme. Read it, then choose which version to keep." }
        return "The cloud request failed. Your local programme and sign-in credentials are unchanged."
    }
}

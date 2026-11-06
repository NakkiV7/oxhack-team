import XCTest
@testable import Spottr

@MainActor final class ProgrammeSyncTests: XCTestCase {
    func testNeverSubmittedConsentCanTurnOffWithoutInvalidWithdrawal() async throws {
        let f = try RemovalFixture(); defer { f.clean() }
        try f.sync.consent(); await f.sync.withdraw()
        XCTAssertFalse(f.sync.consented); XCTAssertFalse(f.sync.withdrawalPending)
        XCTAssertTrue(f.client.withdrawals.isEmpty); XCTAssertEqual(f.client.reads, 0); XCTAssertTrue(f.client.writes.isEmpty)
        try f.sync.consent(); let slot = UUID(); try f.sync.linkSlot(slot)
        XCTAssertEqual(f.sync.profileSlot, slot)
        await f.sync.withdraw()
        XCTAssertTrue(f.sync.withdrawalPending); XCTAssertTrue(f.client.withdrawals.isEmpty)
        await f.sync.removeSavedProgramme()
        XCTAssertFalse(f.sync.withdrawalPending); XCTAssertFalse(f.sync.consented)
        XCTAssertEqual(f.client.reads, 1)
        try f.sync.consent()
        XCTAssertNotEqual(f.sync.profileSlot, slot)
        XCTAssertEqual(f.sync.serverRevision, 0)
        await f.sync.upload()
        XCTAssertEqual(f.client.writes.last?.profileSlot, f.sync.profileSlot)
        XCTAssertEqual(f.client.writes.last?.expectedRevision, 0)
    }
    func testLostWithdrawalResponseResolvesOnlyExplicitCurrent404ThenUsesFreshSlot() async throws {
        let f = try RemovalFixture(); defer { f.clean() }
        try f.sync.consent(); await f.sync.upload(); let oldSlot = f.sync.profileSlot
        f.client.commitWithdrawalBeforeFailure = true
        f.client.withdrawalFailure = URLError(.networkConnectionLost)
        await f.sync.withdraw()
        f.client.commitWithdrawalBeforeFailure = false
        f.client.withdrawalFailure = AccountFailure.service(409, "revision_conflict")
        await f.sync.withdraw()
        XCTAssertTrue(f.sync.withdrawalPending); XCTAssertEqual(f.client.reads, 0)
        XCTAssertEqual(f.client.withdrawals.map(\.expectedRevision), [1, 1])
        await f.sync.removeSavedProgramme()
        XCTAssertFalse(f.sync.withdrawalPending); XCTAssertFalse(f.sync.consented)
        XCTAssertEqual(f.client.reads, 1); XCTAssertEqual(f.client.withdrawals.count, 2)
        XCTAssertEqual(f.client.writes.count, 1)
        XCTAssertEqual(f.sync.serverRevision, 1, "A 404 cannot invent the tombstone revision")
        try f.sync.consent(); XCTAssertNotEqual(f.sync.profileSlot, oldSlot)
        XCTAssertEqual(f.sync.serverRevision, 0)
    }
    func testRemoval404MustBeCurrentAndAuthenticatedAndHeldWriteCannotPublishAfterOff() async throws {
        let f = try RemovalFixture(); defer { f.clean() }
        try f.sync.consent()
        var release: CheckedContinuation<Void, Never>?
        f.client.holdWrite = { await withCheckedContinuation { release = $0 } }
        let write = Task { await f.sync.upload() }
        for _ in 0..<100 where release == nil { await Task.yield() }
        XCTAssertNotNil(release)
        await f.sync.withdraw()
        XCTAssertFalse(f.sync.consented); XCTAssertTrue(f.sync.withdrawalPending)
        await f.sync.removeSavedProgramme(); XCTAssertEqual(f.client.reads, 0)
        release?.resume(); await write.value
        XCTAssertEqual(f.sync.serverRevision, 0); XCTAssertTrue(f.sync.withdrawalPending)
        XCTAssertEqual(f.client.writes.count, 1); XCTAssertTrue(f.client.withdrawals.isEmpty)
        await f.sync.removeSavedProgramme()
        XCTAssertEqual(f.client.reads, 1); XCTAssertEqual(f.client.withdrawals.last?.expectedRevision, 1)
        XCTAssertFalse(f.sync.withdrawalPending); XCTAssertFalse(f.sync.consented)
        XCTAssertEqual(f.client.writes.count, 1)
    }
    func testRemovalErrorsAndStaleOwnerOrPolicy404StayPending() async throws {
        for retirePolicy in [false, true] {
            let f = try RemovalFixture(); defer { f.clean() }
            try f.sync.consent(); try f.sync.linkSlot(UUID()); await f.sync.withdraw()
            f.client.failure = AccountFailure.service(401, "unauthorized")
            await f.sync.removeSavedProgramme(); XCTAssertTrue(f.sync.withdrawalPending)
            f.client.failure = URLError(.notConnectedToInternet)
            await f.sync.removeSavedProgramme(); XCTAssertTrue(f.sync.withdrawalPending)
            f.client.failure = nil
            f.client.onRead = { if retirePolicy { f.workspace.invalidatePolicy() } else { f.isCurrent = false } }
            await f.sync.removeSavedProgramme()
            XCTAssertTrue(f.sync.withdrawalPending); XCTAssertFalse(f.sync.consented)
            XCTAssertEqual(f.client.reads, 3); XCTAssertTrue(f.client.withdrawals.isEmpty)
        }
    }
    func testOldConsentEpoch404CannotClearRenewedRemovalIntent() async throws {
        let f = try RemovalFixture(); defer { f.clean() }
        try f.sync.consent(); try f.sync.linkSlot(UUID()); await f.sync.withdraw()
        var release: CheckedContinuation<Void, Never>?
        f.client.holdRead = { await withCheckedContinuation { release = $0 } }
        let removal = Task { await f.sync.removeSavedProgramme() }
        for _ in 0..<100 where release == nil { await Task.yield() }
        XCTAssertNotNil(release)
        await f.sync.withdraw() // changes the consent epoch while the old read is held
        release?.resume(); await removal.value
        XCTAssertTrue(f.sync.withdrawalPending); XCTAssertFalse(f.sync.consented)
        XCTAssertEqual(f.client.reads, 1); XCTAssertTrue(f.client.withdrawals.isEmpty)
    }
    @MainActor private final class RemovalFixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let workspace: AccountWorkspace
        let client = ProgrammeCloudFake()
        var isCurrent = true
        lazy var sync = ProgrammeSyncStore(programme: workspace.programme, profile: workspace.profile, client: client, isCurrent: { [unowned self] in self.isCurrent }, hasOngoingWorkout: { false })
        init() throws {
            workspace = try AccountWorkspace(scope: .init(accountID: UUID(), profileID: UUID(), root: root))
            try workspace.profile.save(LocalProfile(programmePreferences: .init(goals: [.strength], weekdays: [1], ageContext: .init(ageYears: 30, guardianManaged: false))))
        }
        func clean() { try? FileManager.default.removeItem(at: root) }
    }
    func testConsentIsSeparateAdultOnlyAndCloudFailurePreservesLocalProgramme() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let scope = AccountDataScope(accountID: UUID(), profileID: UUID(), root: root)
        let workspace = try AccountWorkspace(scope: scope)
        try workspace.profile.save(LocalProfile(programmePreferences: .init(goals: [.balance], weekdays: [1], ageContext: .init(ageYears: 30, guardianManaged: false))))
        let week = try workspace.programme.prepare(profile: XCTUnwrap(workspace.profile.profile), history: [])
        let client = ProgrammeCloudFake()
        let sync = ProgrammeSyncStore(programme: workspace.programme, profile: workspace.profile, client: client, isCurrent: { true }, hasOngoingWorkout: { false })
        await sync.upload()
        XCTAssertEqual(client.writes.count, 0)
        try sync.consent()
        XCTAssertNotEqual(sync.profileSlot, scope.accountID)
        XCTAssertNotEqual(sync.profileSlot, scope.profileID)
        client.failure = URLError(.notConnectedToInternet)
        await sync.upload()
        XCTAssertEqual(client.writes.count, 1)
        XCTAssertEqual(workspace.programme.current, week)
        XCTAssertEqual(sync.serverRevision, 0)
        client.failure = nil
        await sync.upload()
        XCTAssertEqual(sync.serverRevision, 1)
        await sync.withdraw()
        XCTAssertFalse(sync.consented)
        XCTAssertEqual(sync.serverRevision, 2)
        try sync.consent(); await sync.upload()
        XCTAssertEqual(client.writes.last?.expectedRevision, 2)
        try workspace.profile.save(LocalProfile(programmePreferences: .init(goals: [.balance], weekdays: [1], ageContext: .init(ageYears: 10, guardianManaged: true))))
        let count = client.writes.count
        await sync.upload(); await sync.read()
        XCTAssertEqual(client.writes.count, count)
        XCTAssertEqual(client.reads, 0)
        XCTAssertThrowsError(try sync.consent())
    }
    func testWithdrawalConflictStaysOffUntilExplicitSingleRemovalRead() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = try AccountWorkspace(scope: .init(accountID: UUID(), profileID: UUID(), root: root))
        try workspace.profile.save(LocalProfile(programmePreferences: .init(goals: [.balance], weekdays: [1], ageContext: .init(ageYears: 30, guardianManaged: false))))
        let client = ProgrammeCloudFake()
        let sync = ProgrammeSyncStore(programme: workspace.programme, profile: workspace.profile, client: client, isCurrent: { true }, hasOngoingWorkout: { false })
        try sync.consent(); await sync.upload()
        client.failure = AccountFailure.service(409, "revision_conflict")
        await sync.withdraw()
        XCTAssertFalse(sync.consented); XCTAssertTrue(sync.withdrawalPending)
        XCTAssertEqual(client.reads, 0)
        client.failure = nil
        client.remote = .init(profileSlot: sync.profileSlot, revision: 4, preferences: CloudProgrammePreferences(try XCTUnwrap(workspace.profile.profile).effectiveProgrammePreferences), programme: nil, updatedAt: Date())
        client.onRead = { XCTAssertFalse(sync.consented); XCTAssertTrue(sync.withdrawalPending) }
        await sync.removeSavedProgramme()
        XCTAssertEqual(client.reads, 1)
        XCTAssertEqual(client.withdrawals.last?.expectedRevision, 4)
        XCTAssertEqual(sync.serverRevision, 5)
        XCTAssertFalse(sync.consented); XCTAssertFalse(sync.withdrawalPending)
        XCTAssertEqual(client.writes.count, 1)
    }
    func testRemovalConflictRemainsPendingAndRetiredReadCannotWithdraw() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = try AccountWorkspace(scope: .init(accountID: UUID(), profileID: UUID(), root: root))
        try workspace.profile.save(LocalProfile(programmePreferences: .init(goals: [.balance], weekdays: [1], ageContext: .init(ageYears: 30, guardianManaged: false))))
        let client = ProgrammeCloudFake()
        let sync = ProgrammeSyncStore(programme: workspace.programme, profile: workspace.profile, client: client, isCurrent: { true }, hasOngoingWorkout: { false })
        try sync.consent(); await sync.upload()
        client.withdrawalFailure = AccountFailure.service(409, "revision_conflict")
        await sync.withdraw()
        client.remote = .init(profileSlot: sync.profileSlot, revision: 7, preferences: CloudProgrammePreferences(try XCTUnwrap(workspace.profile.profile).effectiveProgrammePreferences), programme: nil, updatedAt: Date())
        await sync.removeSavedProgramme()
        XCTAssertEqual(client.reads, 1); XCTAssertEqual(client.withdrawals.count, 2)
        XCTAssertTrue(sync.withdrawalPending); XCTAssertFalse(sync.consented)
        await sync.upload(); await sync.read()
        XCTAssertEqual(client.reads, 1); XCTAssertEqual(client.writes.count, 1)
        client.onRead = { workspace.invalidatePolicy() }
        await sync.removeSavedProgramme()
        XCTAssertEqual(client.reads, 2); XCTAssertEqual(client.withdrawals.count, 2)
        XCTAssertTrue(sync.withdrawalPending); XCTAssertFalse(sync.consented)
    }
    func testRetiredPolicyRejectsLateCloudResponse() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = try AccountWorkspace(scope: .init(accountID: UUID(), profileID: UUID(), root: root))
        try workspace.profile.save(LocalProfile(programmePreferences: .init(goals: [.balance], weekdays: [1], ageContext: .init(ageYears: 30, guardianManaged: false))))
        let client = ProgrammeCloudFake(); client.beforeReply = { workspace.invalidatePolicy() }
        let sync = ProgrammeSyncStore(programme: workspace.programme, profile: workspace.profile, client: client, isCurrent: { true }, hasOngoingWorkout: { false })
        try sync.consent(); await sync.upload()
        XCTAssertEqual(sync.serverRevision, 0)
    }
}

@MainActor final class ProgrammeCloudFake: ProgrammeCloudClient {
    var writes: [ProgrammeWriteRequest] = []
    var reads = 0
    var remote: ProgrammeReadReply?
    var withdrawals: [ProgrammeWithdrawRequest] = []
    var onRead: (() -> Void)?
    var failure: Error?
    var withdrawalFailure: Error?
    var commitWithdrawalBeforeFailure = false
    var beforeReply: (() -> Void)?
    var holdWrite: (() async -> Void)?
    var holdRead: (() async -> Void)?
    func writePlan(_ request: ProgrammeWriteRequest) async throws -> ProgrammeWriteReply {
        writes.append(request); await holdWrite?(); beforeReply?()
        if let failure { throw failure }
        remote = .init(profileSlot: request.profileSlot, revision: request.expectedRevision + 1, preferences: request.preferences, programme: request.programme, updatedAt: Date())
        return .init(profileSlot: request.profileSlot, revision: request.expectedRevision + 1, updatedAt: Date())
    }
    func readPlan(_ request: ProgrammeReadRequest) async throws -> ProgrammeReadReply { reads += 1; await holdRead?(); onRead?(); if let failure { throw failure }; if let remote { return remote }; throw AccountFailure.service(404, "not_found") }
    func withdrawPlan(_ request: ProgrammeWithdrawRequest) async throws -> ProgrammeWithdrawReply {
        withdrawals.append(request)
        guard request.expectedRevision > 0 else { throw AccountFailure.service(400, "invalid_revision") }
        if commitWithdrawalBeforeFailure { remote = nil }
        if let withdrawalFailure { throw withdrawalFailure }
        if let failure { throw failure }
        remote = nil
        return .init(withdrawn: true, revision: request.expectedRevision + 1)
    }
}

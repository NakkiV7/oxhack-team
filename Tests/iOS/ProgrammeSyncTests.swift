import XCTest
@testable import Spottr

@MainActor final class ProgrammeSyncTests: XCTestCase {
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
        try sync.consent()
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
        XCTAssertTrue(client.writes.isEmpty)
    }
    func testRemovalConflictRemainsPendingAndRetiredReadCannotWithdraw() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = try AccountWorkspace(scope: .init(accountID: UUID(), profileID: UUID(), root: root))
        try workspace.profile.save(LocalProfile(programmePreferences: .init(goals: [.balance], weekdays: [1], ageContext: .init(ageYears: 30, guardianManaged: false))))
        let client = ProgrammeCloudFake()
        let sync = ProgrammeSyncStore(programme: workspace.programme, profile: workspace.profile, client: client, isCurrent: { true }, hasOngoingWorkout: { false })
        try sync.consent()
        client.withdrawalFailure = AccountFailure.service(409, "revision_conflict")
        await sync.withdraw()
        client.remote = .init(profileSlot: sync.profileSlot, revision: 7, preferences: CloudProgrammePreferences(try XCTUnwrap(workspace.profile.profile).effectiveProgrammePreferences), programme: nil, updatedAt: Date())
        await sync.removeSavedProgramme()
        XCTAssertEqual(client.reads, 1); XCTAssertEqual(client.withdrawals.count, 2)
        XCTAssertTrue(sync.withdrawalPending); XCTAssertFalse(sync.consented)
        await sync.upload(); await sync.read()
        XCTAssertEqual(client.reads, 1); XCTAssertTrue(client.writes.isEmpty)
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
    var beforeReply: (() -> Void)?
    func writePlan(_ request: ProgrammeWriteRequest) async throws -> ProgrammeWriteReply {
        writes.append(request); beforeReply?()
        if let failure { throw failure }
        return .init(profileSlot: request.profileSlot, revision: request.expectedRevision + 1, updatedAt: Date())
    }
    func readPlan(_ request: ProgrammeReadRequest) async throws -> ProgrammeReadReply { reads += 1; onRead?(); if let failure { throw failure }; if let remote { return remote }; throw URLError(.fileDoesNotExist) }
    func withdrawPlan(_ request: ProgrammeWithdrawRequest) async throws -> ProgrammeWithdrawReply {
        withdrawals.append(request)
        if let withdrawalFailure { throw withdrawalFailure }
        if let failure { throw failure }
        return .init(withdrawn: true, revision: request.expectedRevision + 1)
    }
}

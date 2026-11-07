import XCTest
@testable import SpottrCore

@MainActor
final class HealthAccessTests: XCTestCase {
    func testFreshStoreDoesNotReadOrPromptUntilExplicitConnect() async throws {
        let domain = "Spottr.Health.Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let client = HealthTestClient()
        let store = HealthSnapshotStore(client: client, defaults: defaults)
        await store.refresh()
        XCTAssertFalse(store.hasRequestedAccess)
        XCTAssertNil(store.snapshot)
        XCTAssertEqual(client.requests, 0)
        XCTAssertEqual(client.reads, 0)
        await store.connect()
        XCTAssertTrue(store.hasRequestedAccess)
        XCTAssertEqual(client.requests, 1)
        XCTAssertEqual(client.reads, 1)
        XCTAssertTrue(try XCTUnwrap(store.snapshot).observations.isEmpty)
        XCTAssertTrue(store.statusMessage.contains("No available data"))
        XCTAssertFalse(store.isBusy)
    }

    func testEmptyOrFailedReadRemovesPreviouslyVisibleDataWithoutInventingPermissionOrZeros() async throws {
        let domain = "Spottr.Health.Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let client = HealthTestClient()
        let date = Date.now.addingTimeInterval(-60)
        client.observations = [try XCTUnwrap(.init(metric: .restingHeartRate, value: 62, date: date, source: "Watch"))]
        let store = HealthSnapshotStore(client: client, defaults: defaults)
        await store.connect()
        XCTAssertEqual(store.snapshot?.latestObservations.first?.value, 62)
        client.observations = []
        await store.refresh()
        XCTAssertTrue(try XCTUnwrap(store.snapshot).observations.isEmpty)
        XCTAssertTrue(store.statusMessage.contains("No available data"))
        client.readError = CocoaError(.fileReadNoPermission)
        await store.refresh()
        XCTAssertNil(store.snapshot)
        XCTAssertFalse(store.isBusy)
        XCTAssertEqual(client.requests, 1)
    }

    func testUnsupportedHealthNeverAttemptsPermissionOrRead() async throws {
        let domain = "Spottr.Health.Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let client = HealthTestClient()
        client.isAvailable = false
        let store = HealthSnapshotStore(client: client, defaults: defaults)
        await store.connect()
        XCTAssertFalse(store.hasRequestedAccess)
        XCTAssertEqual(client.requests, 0)
        XCTAssertEqual(client.reads, 0)
        XCTAssertNil(store.snapshot)
    }

    func testMidnightRefreshUsesNewDayBoundsAndNeverKeepsYesterdayAsToday() async throws {
        let domain = "Spottr.Health.Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-05T23:59:59Z")).addingTimeInterval(0.99)
        let client = HealthTestClient()
        client.observations = [try XCTUnwrap(.init(metric: .steps, value: 1200, date: now, source: "Health"))]
        let store = HealthSnapshotStore(client: client, defaults: defaults, now: { now }, calendar: { calendar })
        await store.connect()
        XCTAssertEqual(store.snapshot?.dailyObservations.first?.value, 1200)
        now = now.addingTimeInterval(2)
        XCTAssertNil(store.snapshot)
        client.observations = []
        try await Task.sleep(for: .milliseconds(1250))
        XCTAssertGreaterThanOrEqual(client.reads, 2)
        XCTAssertTrue(try XCTUnwrap(store.snapshot).dailyObservations.isEmpty)
        XCTAssertEqual(client.requestedDayStart, calendar.startOfDay(for: now))
    }

    func testDisconnectDropsInFlightHealthResultsAndDoesNotPersistReadings() async throws {
        let domain = "Spottr.Health.Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let client = HealthTestClient()
        let store = HealthSnapshotStore(client: client, defaults: defaults)
        await store.connect()
        client.deferRead = true
        let refresh = Task { await store.refresh() }
        for _ in 0..<100 where client.pendingRead == nil { await Task.yield() }
        XCTAssertNotNil(client.pendingRead)
        store.disconnect()
        client.pendingRead?.resume(returning: [try XCTUnwrap(.init(metric: .restingHeartRate, value: 60, date: .now, source: "Watch"))])
        await refresh.value
        XCTAssertNil(store.snapshot)
        XCTAssertFalse(store.hasRequestedAccess)
        let reopened = HealthSnapshotStore(client: client, defaults: defaults)
        XCTAssertNil(reopened.snapshot)
        XCTAssertFalse(reopened.hasRequestedAccess)
    }

    func testRetiredReaderDropsHeldResultsAndCannotChangeReplacementPreferences() async throws {
        let domain = "Spottr.Health.Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let client = HealthTestClient()
        client.observations = [try XCTUnwrap(.init(metric: .restingHeartRate, value: 62, date: .now, source: "Watch"))]
        let store = HealthSnapshotStore(client: client, defaults: defaults)
        await store.connect()
        store.setZonePreference(.init(maximumHeartRate: 180, isEstimated: false))
        client.deferRead = true
        let refresh = Task { await store.refresh() }
        for _ in 0..<100 where client.pendingRead == nil { await Task.yield() }
        XCTAssertNotNil(client.pendingRead)
        store.retire()
        let retiredStatus = store.statusMessage
        client.pendingRead?.resume(returning: client.observations)
        await refresh.value
        XCTAssertNil(store.snapshot)
        XCTAssertFalse(store.hasRequestedAccess)
        XCTAssertEqual(store.statusMessage, retiredStatus)
        await store.connect()
        await store.refresh()
        store.disconnect()
        store.setZonePreference(nil)
        store.setZonePreference(.init(maximumHeartRate: 190, isEstimated: true))
        XCTAssertNil(store.snapshot)
        XCTAssertFalse(store.hasRequestedAccess)
        XCTAssertEqual(client.requests, 1)
        XCTAssertEqual(client.reads, 2)
        let reopened = HealthSnapshotStore(client: client, defaults: defaults)
        XCTAssertTrue(reopened.hasRequestedAccess)
        XCTAssertEqual(reopened.zonePreference, .init(maximumHeartRate: 180, isEstimated: false))
        XCTAssertNil(reopened.snapshot)
        reopened.disconnect()
        XCTAssertFalse(HealthSnapshotStore(client: client, defaults: defaults).hasRequestedAccess)
        await reopened.connect()
        XCTAssertTrue(reopened.hasRequestedAccess, "Explicit disconnect must still allow a later explicit connection")
    }

    func testRetirementRejectsLateAuthorizationSuccessAndFailureWithoutClearingSavedIntent() async throws {
        for authorizationFails in [false, true] {
            let domain = "Spottr.Health.Tests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
            defer { defaults.removePersistentDomain(forName: domain) }
            let client = HealthTestClient(); client.deferAuthorization = true
            let store = HealthSnapshotStore(client: client, defaults: defaults)
            let pending = Task { await store.connect() }
            for _ in 0..<100 where client.pendingAuthorization == nil { await Task.yield() }
            XCTAssertNotNil(client.pendingAuthorization)
            store.retire()
            let retiredStatus = store.statusMessage
            if authorizationFails { client.pendingAuthorization?.resume(throwing: CocoaError(.userCancelled)) }
            else { client.pendingAuthorization?.resume() }
            await pending.value
            XCTAssertEqual(store.statusMessage, retiredStatus)
            XCTAssertFalse(store.hasRequestedAccess)
            XCTAssertFalse(store.isBusy)
            XCTAssertNil(store.snapshot)
            XCTAssertEqual(client.reads, 0)
            XCTAssertTrue(HealthSnapshotStore(client: client, defaults: defaults).hasRequestedAccess)
        }
    }

    func testLateAuthorizationFailureCannotReplaceDisconnectedStatus() async throws {
        let defaults = UserDefaults(suiteName: "Spottr.Health.Tests.\(UUID().uuidString)")!
        let client = HealthTestClient(); client.deferAuthorization = true
        let store = HealthSnapshotStore(client: client, defaults: defaults)
        let pending = Task { await store.connect() }
        for _ in 0..<100 where client.pendingAuthorization == nil { await Task.yield() }
        XCTAssertNotNil(client.pendingAuthorization)
        store.disconnect()
        let disconnected = store.statusMessage
        client.pendingAuthorization?.resume(throwing: CocoaError(.userCancelled))
        await pending.value
        XCTAssertEqual(store.statusMessage, disconnected)
        XCTAssertFalse(store.hasRequestedAccess)
        XCTAssertNil(store.snapshot)
        XCTAssertEqual(client.reads, 0)
    }

    func testExplicitZoneBasisPersistsLocallyWithoutPersistingHealthObservations() async throws {
        let domain = "Spottr.Health.Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let client = HealthTestClient()
        let store = HealthSnapshotStore(client: client, defaults: defaults)
        XCTAssertNil(store.zonePreference)
        store.setZonePreference(.init(maximumHeartRate: 180, isEstimated: true))
        let reopened = HealthSnapshotStore(client: client, defaults: defaults)
        XCTAssertEqual(reopened.zonePreference?.maximumHeartRate, 180)
        XCTAssertEqual(reopened.zonePreference?.isEstimated, true)
        XCTAssertNil(reopened.snapshot)
        reopened.setZonePreference(nil)
        XCTAssertNil(HealthSnapshotStore(client: client, defaults: defaults).zonePreference)
    }
}

@MainActor
private final class HealthTestClient: HealthReadingClient {
    var isAvailable = true
    var deferAuthorization = false
    var pendingAuthorization: CheckedContinuation<Void, Error>?
    var requests = 0
    var reads = 0
    var observations: [HealthObservation] = []
    var readError: Error?
    var authorizationError: Error?
    var requestedDayStart: Date?
    var deferRead = false
    var pendingRead: CheckedContinuation<[HealthObservation], Error>?
    func requestReadAuthorization() async throws {
        requests += 1
        if deferAuthorization { try await withCheckedThrowingContinuation { pendingAuthorization = $0 } }
        if let authorizationError { throw authorizationError }
    }
    func read(asOf: Date, dayStart: Date, dayEnd: Date) async throws -> [HealthObservation] {
        reads += 1
        requestedDayStart = dayStart
        if deferRead {
            deferRead = false
            return try await withCheckedThrowingContinuation { pendingRead = $0 }
        }
        if let readError { throw readError }
        return observations
    }
}

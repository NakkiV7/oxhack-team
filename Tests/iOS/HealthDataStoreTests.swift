import XCTest
import HealthKit
@testable import Spottr

@MainActor
final class HealthDataStoreTests: XCTestCase {
    func testZonesStartAbsentAndOnlyExplicitValidatedLocalChoicesPersist() throws {
        let domain = "Spottr.Health.ZoneTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = HealthDataStore(client: EmptyHealthClient(), defaults: defaults)
        XCTAssertNil(store.zones)
        try store.setMaximumHeartRate(180)
        XCTAssertEqual(store.zones?.maximumHeartRate, 180)
        XCTAssertFalse(try XCTUnwrap(store.zones).isEstimated)
        XCTAssertThrowsError(try store.setMaximumHeartRate(.nan))
        XCTAssertThrowsError(try store.setMaximumHeartRate(261))
        XCTAssertEqual(store.zones?.maximumHeartRate, 180)
        try store.estimateZones(age: 40)
        XCTAssertEqual(store.zones?.maximumHeartRate, 180)
        XCTAssertTrue(try XCTUnwrap(store.zones).isEstimated)
        XCTAssertThrowsError(try store.estimateZones(age: 17))
        let reopened = HealthDataStore(client: EmptyHealthClient(), defaults: defaults)
        XCTAssertTrue(try XCTUnwrap(reopened.zones).isEstimated)
        reopened.clearZones()
        XCTAssertNil(reopened.zones)
        XCTAssertNil(HealthDataStore(client: EmptyHealthClient(), defaults: defaults).zones)
    }

    func testRequestedReadTypesContainOnlyTheNineOptionalDisplayedMetrics() {
        XCTAssertEqual(Set(AppleHealthReadingClient.requestedReadTypes.map(\.identifier)), [
            HKQuantityTypeIdentifier.restingHeartRate.rawValue,
            HKQuantityTypeIdentifier.walkingHeartRateAverage.rawValue,
            HKQuantityTypeIdentifier.heartRateVariabilitySDNN.rawValue,
            HKQuantityTypeIdentifier.vo2Max.rawValue,
            HKQuantityTypeIdentifier.heartRateRecoveryOneMinute.rawValue,
            HKQuantityTypeIdentifier.oxygenSaturation.rawValue,
            HKQuantityTypeIdentifier.respiratoryRate.rawValue,
            HKQuantityTypeIdentifier.stepCount.rawValue,
            HKQuantityTypeIdentifier.distanceWalkingRunning.rawValue
        ])
    }
}

@MainActor
private final class EmptyHealthClient: HealthReadingClient {
    var isAvailable: Bool { false }
    func requestReadAuthorization() async throws {}
    func read(asOf: Date, dayStart: Date, dayEnd: Date) async throws -> [HealthObservation] { [] }
}

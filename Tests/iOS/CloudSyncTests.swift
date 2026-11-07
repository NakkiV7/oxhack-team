import XCTest
@testable import Spottr

@MainActor
final class CloudSyncTests: XCTestCase {
    func testRetiredConsumerModelDoesNotReadGatewayConfiguration() async {
        var reads = 0
        let model = CloudSyncModel(configuration: { reads += 1; throw WorkoutSyncError.configuration })
        await model.sync(record: .init(id: UUID(), date: Date(), sets: []), installationID: UUID())
        XCTAssertEqual(reads, 0)
        XCTAssertTrue(model.error?.contains("retired") == true)
        XCTAssertNil(model.receipt)
    }
    func testInstallationIdentityPersistsAndNamespacesStaySeparate() throws {
        let suite = "CloudSyncTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = CloudInstallation.id(defaults: defaults, namespace: "first")
        XCTAssertEqual(first, CloudInstallation.id(defaults: defaults, namespace: "first"))
        XCTAssertNotEqual(first, CloudInstallation.id(defaults: defaults, namespace: "second"))
    }
    func testCloudSyncStartsOnlyWhenRequestedAndKeepsLocalRecordOnFailure() async {
        let record = SessionRecord(id: UUID(), date: Date(), sets: [])
        let model = CloudSyncModel(configuration: { throw WorkoutSyncError.configuration })
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.receipt)
        XCTAssertNil(model.error)
        await model.sync(record: record, installationID: UUID())
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.receipt)
        XCTAssertTrue(model.error?.contains("retired") == true)
        XCTAssertTrue(record.sets.isEmpty)
    }
}

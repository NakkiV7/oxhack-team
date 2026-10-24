import XCTest
@testable import Spottr

@MainActor
final class CloudSyncTests: XCTestCase {
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
        XCTAssertTrue(model.error?.contains("settings") == true)
        XCTAssertTrue(record.sets.isEmpty)
    }
}

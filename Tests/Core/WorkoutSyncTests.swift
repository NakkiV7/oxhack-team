import XCTest
@testable import SpottrCore

final class WorkoutSyncTests: XCTestCase {
    func testExplicitUploadKeepsSessionIdentityAndMillisecondReadingTimes() async throws {
        let date = Date(timeIntervalSince1970: 1_792_836_000.123)
        let record = SessionRecord(id: UUID(), date: date, sets: [])
        let installationID = UUID()
        let client = WorkoutSyncClient(baseURL: URL(string: "https://coach.example")!, token: "access") { request in
            XCTAssertEqual(request.url?.path, "/v1/workouts")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access")
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            XCTAssertEqual(object["installationID"] as? String, installationID.uuidString.lowercased())
            let uploaded = try XCTUnwrap(object["record"] as? [String: Any])
            XCTAssertEqual(uploaded["id"] as? String, record.id.uuidString)
            XCTAssertTrue((uploaded["date"] as? String)?.contains(".123Z") == true)
            let response: [String: Any] = ["workoutID": record.id.uuidString, "replayed": false, "sha256": String(repeating: "a", count: 64)]
            return (try JSONSerialization.data(withJSONObject: response), HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!)
        }
        let receipt = try await client.upload(record: record, installationID: installationID)
        XCTAssertEqual(receipt.workoutID, record.id)
        XCTAssertFalse(receipt.replayed)
    }
    func testReplayConfirmsSameWorkoutWithoutTreatingConflictAsSaved() async throws {
        let record = SessionRecord(id: UUID(), date: Date(), sets: [])
        let client = WorkoutSyncClient(baseURL: URL(string: "https://coach.example")!, token: "access") { request in
            let response: [String: Any] = ["workoutID": record.id.uuidString.lowercased(), "replayed": true, "sha256": String(repeating: "1", count: 64)]
            return (try JSONSerialization.data(withJSONObject: response), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let result = try await client.upload(record: record, installationID: UUID())
        XCTAssertTrue(result.replayed)
        for status in [401, 403, 409, 503] {
            let rejected = WorkoutSyncClient(baseURL: URL(string: "https://coach.example")!, token: "access") { request in
                (Data("private database error".utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
            }
            do { _ = try await rejected.upload(record: record, installationID: UUID()); XCTFail("Failure accepted") }
            catch { XCTAssertEqual(error as? WorkoutSyncError, .rejected(status)) }
        }
    }
    func testCannotConfirmAnotherWorkoutOrMalformedHash() async {
        let record = SessionRecord(id: UUID(), date: Date(), sets: [])
        for body in [#"{"workoutID":"00000000-0000-0000-0000-000000000000","replayed":false,"sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}"#, "{}"] {
            let client = WorkoutSyncClient(baseURL: URL(string: "https://coach.example")!, token: "access") { request in
                (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!)
            }
            do { _ = try await client.upload(record: record, installationID: UUID()); XCTFail("Invalid receipt accepted") }
            catch { XCTAssertEqual(error as? WorkoutSyncError, .invalidReceipt) }
        }
    }
    func testCancellationAndUnsafeConnectionNeverUpload() async {
        let record = SessionRecord(id: UUID(), date: Date(), sets: [])
        let client = WorkoutSyncClient(baseURL: URL(string: "http://example.com")!, token: "access") { _ in
            XCTFail("Plaintext upload started"); throw URLError(.unsupportedURL)
        }
        do { _ = try await client.upload(record: record, installationID: UUID()); XCTFail("Unsafe URL accepted") }
        catch { XCTAssertEqual(error as? WorkoutSyncError, .configuration) }
        let cancelled = WorkoutSyncClient(baseURL: URL(string: "https://example.com")!, token: "access") { _ in
            XCTFail("Cancelled upload started"); throw URLError(.cancelled)
        }
        let task = Task { try await cancelled.upload(record: record, installationID: UUID()) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled upload accepted") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

}

import XCTest
@testable import SpottrCore

final class WorkoutSyncTests: XCTestCase {
    func testAppendedEnergyOnlyPacketsPreserveLegacyUploadBytesAndEmptyEnvelopes() async throws {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let installation = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let date = Date(timeIntervalSince1970: 100)
        let energy = ActiveEnergy(recordingID: UUID(), kilocalories: 7, asOf: date)
        let energyOnly = WatchTelemetry(sessionID: id, sentAt: date.addingTimeInterval(1), heartRate: nil,
                                        accelerationG: nil, rotationRadiansPerSecond: nil, activeEnergy: energy)
        let legacyEmpty = WatchTelemetry(sessionID: id, sentAt: date, heartRate: nil,
                                         accelerationG: nil, rotationRadiansPerSecond: nil)
        let mixed = WatchTelemetry(sessionID: id, sentAt: date, heartRate: .init(value: 120, date: date),
                                   accelerationG: .init(value: 1, date: date), rotationRadiansPerSecond: .init(value: 2, date: date),
                                   activeEnergy: energy)
        let emptyBytes = Data(#"{"installationID":"00000000-0000-0000-0000-000000000002","record":{"date":"1970-01-01T00:01:40.000Z","id":"00000000-0000-0000-0000-000000000001","loggedSets":[],"sets":[],"telemetry":[]}}"#.utf8)
        let legacyBytes = Data(#"{"installationID":"00000000-0000-0000-0000-000000000002","record":{"date":"1970-01-01T00:01:40.000Z","id":"00000000-0000-0000-0000-000000000001","loggedSets":[],"sets":[],"telemetry":[{"sentAt":"1970-01-01T00:01:40.000Z","sessionID":"00000000-0000-0000-0000-000000000001"},{"accelerationG":{"date":"1970-01-01T00:01:40.000Z","value":1},"heartRate":{"date":"1970-01-01T00:01:40.000Z","value":120},"rotationRadiansPerSecond":{"date":"1970-01-01T00:01:40.000Z","value":2},"sentAt":"1970-01-01T00:01:40.000Z","sessionID":"00000000-0000-0000-0000-000000000001"}]}}"#.utf8)
        for (samples, expected) in [([], emptyBytes), ([energyOnly], emptyBytes),
                                    ([legacyEmpty, mixed], legacyBytes), ([legacyEmpty, mixed, energyOnly], legacyBytes)] {
            let client = WorkoutSyncClient(baseURL: URL(string: "https://coach.example")!, token: "access") { request in
                XCTAssertEqual(request.httpBody, expected)
                let reply: [String: Any] = ["workoutID": id.uuidString, "replayed": false, "sha256": String(repeating: "a", count: 64)]
                return (try JSONSerialization.data(withJSONObject: reply), HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!)
            }
            _ = try await client.upload(record: .init(id: id, date: date, sets: [], telemetry: samples), installationID: installation)
        }
    }
    func testLocalEnergyDoesNotChangeOutgoingCoachContext() async throws {
        let id = UUID(), date = Date(timeIntervalSince1970: 100)
        let plain = SessionRecord(id: id, date: date, sets: [])
        let energy = ActiveEnergy(recordingID: UUID(), kilocalories: 7.25, asOf: date)
        let local = SessionRecord(id: id, date: date, sets: [], telemetry: [
            .init(sessionID: id, sentAt: date, heartRate: nil, accelerationG: nil,
                  rotationRadiansPerSecond: nil, activeEnergy: energy)
        ])
        let baseline = CoachRequest(generationID: "energy-is-local", message: "What next?", facts: CoachGrounding.facts(history: [plain]))
        let expected = try JSONEncoder().encode(baseline)
        let client = CoachGatewayClient(baseURL: URL(string: "https://coach.example")!, token: "access") { request in
            let actual = try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as! NSDictionary
            XCTAssertEqual(actual, try JSONSerialization.jsonObject(with: expected) as! NSDictionary)
            return (Data(#"{"generationID":"energy-is-local","text":"Choose a comfortable next step."}"#.utf8),
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        _ = try await client.chat(.init(generationID: "energy-is-local", message: "What next?", facts: CoachGrounding.facts(history: [local])))
    }
    func testEnergyIsLocalWhileV1UploadKeepsExactLegacyBytes() async throws {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let installation = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let date = Date(timeIntervalSince1970: 100)
        let expected = Data(#"{"installationID":"00000000-0000-0000-0000-000000000002","record":{"date":"1970-01-01T00:01:40.000Z","id":"00000000-0000-0000-0000-000000000001","loggedSets":[],"sets":[],"telemetry":[{"heartRate":{"date":"1970-01-01T00:01:40.000Z","value":120},"sentAt":"1970-01-01T00:01:40.000Z","sessionID":"00000000-0000-0000-0000-000000000001"}]}}"#.utf8)
        let client = WorkoutSyncClient(baseURL: URL(string: "https://coach.example")!, token: "access") { request in
            XCTAssertEqual(request.httpBody, expected)
            let reply: [String: Any] = ["workoutID": id.uuidString, "replayed": false, "sha256": String(repeating: "a", count: 64)]
            return (try JSONSerialization.data(withJSONObject: reply), HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!)
        }
        for energy: ActiveEnergy? in [nil, .init(recordingID: UUID(), kilocalories: 7, asOf: date)] {
            let sample = WatchTelemetry(sessionID: id, sentAt: date, heartRate: .init(value: 120, date: date),
                                        accelerationG: nil, rotationRadiansPerSecond: nil, activeEnergy: energy)
            _ = try await client.upload(record: .init(id: id, date: date, sets: [], telemetry: [sample]), installationID: installation)
        }
    }
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

    func testLocalSkipMetadataRoundTripsButMixedUploadKeepsTheOldWireShape() async throws {
        let skip = SkippedSet(id: UUID(), exerciseID: "squat", number: 2, target: 8, unit: .reps, source: .manual, reason: .userChoice)
        let ended = LoggedSet(id: UUID(), exerciseID: "squat", reps: 1, seconds: 0, source: .manual, reason: .voluntary,
                              number: 1, target: 8, quantityOrigin: .selfReport)
        let record = SessionRecord(id: UUID(), date: Date(timeIntervalSince1970: 100), sets: [], loggedSets: [ended], skippedSets: [skip])
        let reopened = try JSONDecoder().decode(SessionRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(reopened.skippedSets, [skip])
        let client = WorkoutSyncClient(baseURL: URL(string: "https://coach.example")!, token: "access") { request in
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            let uploaded = try XCTUnwrap(body["record"] as? [String: Any])
            XCTAssertEqual(Set(uploaded.keys), ["id", "date", "sets", "telemetry", "loggedSets"])
            XCTAssertNil(uploaded["skippedSets"])
            XCTAssertEqual((uploaded["loggedSets"] as? [[String: Any]])?.count, 1)
            XCTAssertEqual((uploaded["loggedSets"] as? [[String: Any]])?.first?["reps"] as? Int, 1)
            let response: [String: Any] = ["workoutID": record.id.uuidString, "replayed": false, "sha256": String(repeating: "a", count: 64)]
            return (try JSONSerialization.data(withJSONObject: response), HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!)
        }
        _ = try await client.upload(record: reopened, installationID: UUID())
    }
    func testSkipOnlyHistoryIsLocalAndNeverUploadsAnEmptyWorkout() async {
        let skip = SkippedSet(id: UUID(), exerciseID: "squat", number: 1, target: 8, unit: .reps, source: .camera, reason: .userChoice)
        let record = SessionRecord(id: UUID(), date: Date(), sets: [], skippedSets: [skip])
        let client = WorkoutSyncClient(baseURL: URL(string: "https://coach.example")!, token: "access") { _ in
            XCTFail("A skip is not a completed workout upload"); throw URLError(.badServerResponse)
        }
        do { _ = try await client.upload(record: record, installationID: UUID()); XCTFail("Skip-only upload accepted") }
        catch { XCTAssertEqual(error as? WorkoutSyncError, .noCompletedSets) }
    }

}

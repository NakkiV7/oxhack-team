import XCTest
@testable import SpottrCore

final class WorkoutSyncTests: XCTestCase {
    func testRetiredConsumerUploadNeverInvokesTransport() async throws {
        let record = SessionRecord(id: UUID(), date: Date(), sets: [])
        let client = WorkoutSyncClient(baseURL: URL(string: "https://coach.example")!, token: "legacy") { request in
            XCTFail("Retired full-workout service must never receive a request")
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!)
        }
        do { _ = try await client.upload(record: record, installationID: UUID()); XCTFail("Retired service accepted upload") }
        catch { XCTAssertTrue(error.localizedDescription.contains("retired")) }
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
}

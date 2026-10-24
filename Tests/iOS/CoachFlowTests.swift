import XCTest
@testable import Spottr

@MainActor
final class CoachFlowTests: XCTestCase {
    func testApprovalRejectsSupportRemovedSinceProposal() async throws {
        let previous = UserDefaults.standard.data(forKey: "coach.approvedPlan")
        defer { UserDefaults.standard.set(previous, forKey: "coach.approvedPlan") }
        let client = CoachGatewayClient(baseURL: URL(string: "https://coach.example")!, token: "test") { request in
            let requestBody = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            let generation = requestBody["generationID"] as! String
            let response: [String: Any] = ["generationID": generation, "items": [["exerciseID": "wallPushup", "sets": 2, "target": 8, "unit": "reps", "restSeconds": 45, "factIDs": ["context"]]], "rationale": ["text": "Build your foundation.", "factIDs": ["context"]]]
            return (try JSONSerialization.data(withJSONObject: response), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let model = CoachModel(configuration: { client }, savedPlanData: nil)
        await model.propose(history: [], support: ["Wall"])
        XCTAssertNotNil(model.proposal)
        model.approve(selected: ["wallPushup"], currentSupport: [])
        XCTAssertNil(model.approvedPlan)
        XCTAssertNotNil(model.error)
    }

    func testCoachDoesNotSendUntilRequestedAndMissingSetupHasActionableError() async {
        let model = CoachModel(configuration: { throw CoachGatewayError.configuration }, savedPlanData: nil)
        XCTAssertTrue(model.turns.isEmpty)
        XCTAssertFalse(model.isLoading)
        await model.send(message: "Help me plan", history: [], support: [])
        XCTAssertFalse(model.isLoading)
        XCTAssertTrue(model.error?.contains("settings") == true)
        XCTAssertFalse(model.turns.contains { $0.role == .model })
    }

    func testCancellationDiscardsLateReply() async throws {
        let received = expectation(description: "Request entered transport")
        var reply: CheckedContinuation<(Data, URLResponse), Never>?
        let client = CoachGatewayClient(baseURL: URL(string: "https://coach.example")!, token: "test") { request in
            await withCheckedContinuation { continuation in
                Task { @MainActor in reply = continuation; received.fulfill() }
            }
        }
        let model = CoachModel(configuration: { client }, savedPlanData: nil)
        let task = Task { await model.send(message: "Help", history: [], support: []) }
        await fulfillment(of: [received], timeout: 2)
        model.cancel()
        reply?.resume(returning: (Data(#"{"generationID":"stale","text":"Late response"}"#.utf8), HTTPURLResponse(url: URL(string: "https://coach.example")!, statusCode: 200, httpVersion: nil, headerFields: nil)!))
        await task.value
        XCTAssertFalse(model.isLoading)
        XCTAssertFalse(model.turns.contains { $0.role == .model })
        XCTAssertNil(model.error)
    }
}

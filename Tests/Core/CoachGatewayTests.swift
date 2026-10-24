import XCTest
@testable import SpottrCore

final class CoachGatewayTests: XCTestCase {
    func testExplicitChatSendsGroundingAndBearerToConfiguredGateway() async throws {
        let client = CoachGatewayClient(baseURL: URL(string: "https://coach.example/api")!, token: "local-token") { request in
            XCTAssertEqual(request.url?.absoluteString, "https://coach.example/api/v1/chat")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer local-token")
            let body = try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any]
            XCTAssertEqual(body?["message"] as? String, "What next?")
            XCTAssertEqual((body?["facts"] as? [[String: String]])?.first?["id"], "context")
            return (Data(#"{"generationID":"one","text":"Start gently."}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let response = try await client.chat(.init(generationID: "one", message: "What next?", facts: [.init(id: "context", text: "No saved sessions.")]))
        XCTAssertEqual(response, "Start gently.")
    }
    func testRejectsStaleReplyAndUnexpectedFields() async throws {
        for body in [#"{"generationID":"old","text":"Late"}"#, #"{"generationID":"one","text":"OK","extra":"field"}"#] {
            let client = CoachGatewayClient(baseURL: URL(string: "https://coach.example")!, token: "test") { request in
                (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            do { _ = try await client.chat(.init(generationID: "one", facts: [])); XCTFail("Invalid response accepted") }
            catch { XCTAssertTrue(error is CoachContractError || error is CoachGatewayError) }
        }
    }
    func testHTTPFailureIsActionableAndDoesNotExposeServerBody() async {
        let client = CoachGatewayClient(baseURL: URL(string: "https://coach.example")!, token: "test") { request in
            (Data("private backend error".utf8), HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!)
        }
        do { _ = try await client.chat(.init(facts: [])); XCTFail("Unauthorized response accepted") }
        catch { XCTAssertEqual(error as? CoachGatewayError, .rejected(401)) }
    }
    func testRemotePlaintextConfigurationNeverContactsTransport() async {
        let client = CoachGatewayClient(baseURL: URL(string: "http://coach.example")!, token: "test") { _ in
            XCTFail("Token would cross plaintext network"); throw URLError(.unsupportedURL)
        }
        do { _ = try await client.chat(.init(facts: [])); XCTFail("Unsafe connection accepted") }
        catch { XCTAssertEqual(error as? CoachGatewayError, .configuration) }
    }
    func testCancellationRejectsAnOtherwiseValidResponse() async {
        let client = CoachGatewayClient(baseURL: URL(string: "https://coach.example")!, token: "test") { request in
            try await Task.sleep(nanoseconds: 5_000_000_000)
            return (Data(#"{"generationID":"one","text":"Late"}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let task = Task { try await client.chat(.init(generationID: "one", facts: [])) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled request accepted") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testStructuredSummaryChecksEvidenceBeforeDisplaying() async throws {
        let body = #"{"generationID":"g","kind":"weekly","headline":{"text":"Keep going.","factIDs":["invented"]},"insights":[],"focus":{"text":"Stay consistent.","factIDs":["context"]}}"#
        let client = CoachGatewayClient(baseURL: URL(string: "https://coach.example")!, token: "test") { request in
            XCTAssertEqual(request.url?.path, "/v1/summary")
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        do {
            _ = try await client.summary(.init(generationID: "g", facts: [.init(id: "context", text: "0 sessions")], kind: .weekly), kind: .weekly)
            XCTFail("Unsupported evidence accepted")
        } catch { XCTAssertEqual(error as? CoachContractError, .invalidEvidence) }
    }

    func testChatDropsOldestHistoryToFitEncodedUTF8BudgetAndKeepsNewestTurnAndFacts() async throws {
        let history = (0..<20).map { CoachTurn(role: $0.isMultiple(of: 2) ? .user : .model, text: "turn-\($0):" + String(repeating: "é", count: 3900)) }
        let facts = [CoachFact(id: "context", text: "Real saved facts")]
        let client = CoachGatewayClient(baseURL: URL(string: "https://coach.example")!, token: "test") { request in
            let data = try XCTUnwrap(request.httpBody)
            XCTAssertLessThanOrEqual(data.count, 65_536)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let retained = try XCTUnwrap(object["history"] as? [[String: String]])
            XCTAssertLessThan(retained.count, history.count)
            XCTAssertEqual(retained.last?["text"], history.last?.text)
            XCTAssertFalse(retained.contains { $0["text"] == history.first?.text })
            XCTAssertEqual(object["message"] as? String, "Current message")
            XCTAssertEqual(object["facts"] as? [[String: String]], [["id": "context", "text": "Real saved facts"]])
            return (Data(#"{"generationID":"g","text":"Ready."}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        _ = try await client.chat(.init(generationID: "g", message: "Current message", history: history, facts: facts))
    }
    func testOversizedGroundingFailsBeforeNetworkWithoutSilentlyDroppingFactsOrMessage() async {
        let client = CoachGatewayClient(baseURL: URL(string: "https://coach.example")!, token: "test") { _ in
            XCTFail("Oversized baseline must not be sent"); throw URLError(.badServerResponse)
        }
        let facts = (0..<40).map { CoachFact(id: "fact-\($0)", text: String(repeating: "é", count: 1900)) }
        do { _ = try await client.chat(.init(message: "Keep this message", facts: facts)); XCTFail("Oversized baseline accepted") }
        catch { XCTAssertTrue(error.localizedDescription.contains("too large")) }
    }

}

import XCTest
@testable import Spottr

@MainActor
final class CoachFlowTests: XCTestCase {
    private static let savedWorkout = Data(#"{"items":[{"exerciseID":"squat","sets":1,"target":2,"unit":"reps","restSeconds":30}],"approvedAt":0,"rationale":"Synthetic saved workout"}"#.utf8)

    func testRemovingSavedWorkoutClearsOnlyItsPersistenceAndReopenedModel() throws {
        let suite = "CoachRemovalTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Self.savedWorkout, forKey: "coach.approvedPlan")
        defaults.set("https://coach.example", forKey: "coach.gatewayURL")
        defaults.set("linear", forKey: "skills.layout")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let history = HistoryStore(url: folder.appendingPathComponent("history.json"))
        try history.save(LoggedWorkout.make(exerciseID: "squat", count: 2, sets: 1))
        let profileURL = folder.appendingPathComponent("profile.json")
        try NativeProfileStore(url: profileURL).save(LocalProfile(weeklyTarget: 3, goals: [.strength]))
        let historyBytes = try Data(contentsOf: history.url), profileBytes = try Data(contentsOf: profileURL)
        let model = CoachModel(configuration: { throw CoachGatewayError.configuration }, savedPlanData: Self.savedWorkout, defaults: defaults)

        model.removeApprovedPlan()

        XCTAssertNil(model.approvedPlan)
        XCTAssertEqual(defaults.persistentDomain(forName: suite) as NSDictionary?,
                       ["coach.gatewayURL": "https://coach.example", "skills.layout": "linear"] as NSDictionary)
        XCTAssertNil(CoachModel(savedPlanData: defaults.data(forKey: "coach.approvedPlan"), defaults: defaults).approvedPlan)
        XCTAssertEqual(try Data(contentsOf: history.url), historyBytes)
        XCTAssertEqual(try Data(contentsOf: profileURL), profileBytes)
        XCTAssertNil(model.error)
    }

    func testRemovingSavedWorkoutPreservesInFlightChatProposalAndReport() async throws {
        for path in ["chat", "proposal", "summary"] {
            let suite = "CoachRemovalTests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(Self.savedWorkout, forKey: "coach.approvedPlan")
            let received = expectation(description: "\(path) entered offline transport")
            var pending: CheckedContinuation<(Data, URLResponse), Never>?
            var captured: URLRequest?
            let client = CoachGatewayClient(baseURL: URL(string: "https://coach.example")!, token: "test") { request in
                await withCheckedContinuation { continuation in
                    Task { @MainActor in pending = continuation; captured = request; received.fulfill() }
                }
            }
            let profile = try LocalProfile(weeklyTarget: 3, goals: [.strength])
            let model = CoachModel(configuration: { client }, savedPlanData: Self.savedWorkout, profile: profile, defaults: defaults)
            let task = Task {
                switch path {
                case "chat": await model.send(message: "Help me plan", history: [], support: [])
                case "proposal": await model.propose(history: [], support: [])
                default: await model.summarize(history: [], kind: .session)
                }
            }
            await fulfillment(of: [received], timeout: 2)

            model.removeApprovedPlan()
            XCTAssertTrue(model.isLoading, path)
            XCTAssertNil(defaults.data(forKey: "coach.approvedPlan"), path)
            pending?.resume(returning: try Self.response(for: XCTUnwrap(captured)))
            await task.value

            XCTAssertFalse(model.isLoading, path)
            XCTAssertNil(model.approvedPlan, path)
            XCTAssertNil(defaults.data(forKey: "coach.approvedPlan"), path)
            XCTAssertNil(model.error, path)
            switch path {
            case "chat": XCTAssertTrue(model.turns.contains { $0.role == .model })
            case "proposal": XCTAssertNotNil(model.proposal)
            default: XCTAssertNotNil(model.summary)
            }
        }
    }

    func testNewWorkoutApprovalStillPersistsAfterRemoval() async throws {
        let suite = "CoachRemovalTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let client = CoachGatewayClient(baseURL: URL(string: "https://coach.example")!, token: "test") { request in try Self.response(for: request) }
        let profile = try LocalProfile(weeklyTarget: 3, goals: [.strength])
        let model = CoachModel(configuration: { client }, savedPlanData: Self.savedWorkout, profile: profile, defaults: defaults)
        model.removeApprovedPlan()
        await model.propose(history: [], support: [])

        model.approve(selected: ["squat"], currentSupport: [])

        let saved = try JSONDecoder().decode(CoachSavedPlan.self, from: XCTUnwrap(defaults.data(forKey: "coach.approvedPlan")))
        XCTAssertEqual(saved.items.map(\.exerciseID), ["squat"])
        XCTAssertEqual(saved.items.first?.sets, 2)
        XCTAssertEqual(saved.items.first?.target, 8)
        XCTAssertEqual(model.approvedPlan?.items.first?.sets, 2)
        XCTAssertEqual(model.approvedPlan?.items.first?.target, 8)
    }

    func testDebugApprovedPlanFixtureRequiresAnIsolatedUUIDAndNeverPersists() throws {
        let suite = "CoachPlanFixtureTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let stored = Data("original plan bytes".utf8)
        defaults.set(stored, forKey: "coach.approvedPlan")
        let fixture = #"{"items":[{"exerciseID":"squat","sets":1,"target":2,"unit":"reps","restSeconds":30}],"approvedAt":0,"rationale":"Synthetic fixture"}"#
        let namespace = UUID().uuidString
        let supplied = CoachSettings.planData(environment: ["SPOTTR_DATA_NAMESPACE": namespace, "SPOTTR_APPROVED_PLAN_FIXTURE": fixture], defaults: defaults)
        #if DEBUG
        let decoded = try JSONDecoder().decode(CoachSavedPlan.self, from: XCTUnwrap(supplied))
        XCTAssertEqual(decoded.items.map(\.exerciseID), ["squat"])
        XCTAssertNotNil(CoachModel(savedPlanData: supplied).approvedPlan)
        #else
        XCTAssertEqual(supplied, stored)
        #endif
        XCTAssertEqual(defaults.data(forKey: "coach.approvedPlan"), stored)

        for environment in [[:], ["SPOTTR_APPROVED_PLAN_FIXTURE": fixture],
                            ["SPOTTR_DATA_NAMESPACE": "not-a-uuid", "SPOTTR_APPROVED_PLAN_FIXTURE": fixture],
                            ["SPOTTR_DATA_NAMESPACE": namespace, "SPOTTR_APPROVED_PLAN_FIXTURE": "{}"],
                            ["SPOTTR_DATA_NAMESPACE": namespace]] {
            XCTAssertEqual(CoachSettings.planData(environment: environment, defaults: defaults), stored)
            XCTAssertEqual(defaults.data(forKey: "coach.approvedPlan"), stored)
        }
    }

    func testDebugApprovedPlanFixtureDoesNotCreateAStoredPlan() throws {
        let suite = "CoachPlanFixtureTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let fixture = #"{"items":[{"exerciseID":"pushup","sets":1,"target":2,"unit":"reps","restSeconds":30}],"approvedAt":0,"rationale":"Synthetic fixture"}"#
        let supplied = CoachSettings.planData(environment: ["SPOTTR_DATA_NAMESPACE": UUID().uuidString, "SPOTTR_APPROVED_PLAN_FIXTURE": fixture], defaults: defaults)
        #if DEBUG
        XCTAssertNotNil(supplied)
        #else
        XCTAssertNil(supplied)
        #endif
        XCTAssertNil(defaults.data(forKey: "coach.approvedPlan"))
    }

    private nonisolated static func response(for request: URLRequest) throws -> (Data, URLResponse) {
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        let generation = try XCTUnwrap(body["generationID"] as? String)
        let grounded: [String: Any] = ["text": "Plan around your selected training preferences.", "factIDs": ["training-goals"]]
        let response: [String: Any]
        switch request.url?.lastPathComponent {
        case "chat": response = ["generationID": generation, "text": "Plan around your selected training preferences."]
        case "proposal": response = ["generationID": generation,
            "items": [["exerciseID": "squat", "sets": 2, "target": 8, "unit": "reps", "restSeconds": 45, "factIDs": ["training-goals"]]],
            "rationale": grounded]
        default: response = ["generationID": generation, "kind": try XCTUnwrap(body["kind"] as? String),
            "headline": grounded, "insights": [grounded], "focus": grounded]
        }
        return (try JSONSerialization.data(withJSONObject: response),
                HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }

    func testSuppliedGoalsReachChatProposalAndReportsWithoutSharingTheOptionalName() async throws {
        let profile = try LocalProfile(name: "Private Optional Name", weeklyTarget: 4, goals: [.mobility, .stamina])
        let requests = expectation(description: "All explicit coach paths receive preferences")
        requests.expectedFulfillmentCount = 4
        let client = CoachGatewayClient(baseURL: URL(string: "https://coach.example")!, token: "test") { request in
            let data = try XCTUnwrap(request.httpBody)
            let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            let facts = try XCTUnwrap(body["facts"] as? [[String: String]])
            let preference = try XCTUnwrap(facts.first { $0["id"] == "training-goals" }?["text"])
            XCTAssertTrue(preference.contains("Mobility, Stamina"))
            XCTAssertTrue(preference.contains("4 training days per week"))
            XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("Private Optional Name"))
            requests.fulfill()
            return try Self.response(for: request)
        }
        let model = CoachModel(configuration: { client }, savedPlanData: nil, profile: profile)

        await model.send(message: "Help me plan", history: [], support: [])
        XCTAssertTrue(model.turns.contains { $0.role == .model })
        await model.propose(history: [], support: [])
        XCTAssertNotNil(model.proposal)
        await model.summarize(history: [], kind: .session)
        XCTAssertEqual(model.summary?.kind, .session)
        await model.summarize(history: [], kind: .weekly)
        XCTAssertEqual(model.summary?.kind, .weekly)
        XCTAssertNil(model.error)
        await fulfillment(of: [requests], timeout: 2)
    }

    func testGoalOrWeeklyTargetChangesRejectLateChatProposalAndSummaryResponses() async throws {
        let initial = try LocalProfile(weeklyTarget: 3, goals: [.strength])
        let changedGoals = try LocalProfile(weeklyTarget: 3, goals: [.mobility])
        let changedTarget = try LocalProfile(weeklyTarget: 5, goals: [.strength])
        for changed in [changedGoals, changedTarget] {
            for path in ["chat", "proposal", "summary"] {
                let received = expectation(description: "\(path) request entered transport")
                var pending: CheckedContinuation<(Data, URLResponse), Never>?
                var captured: URLRequest?
                let client = CoachGatewayClient(baseURL: URL(string: "https://coach.example")!, token: "test") { request in
                    await withCheckedContinuation { continuation in
                        Task { @MainActor in pending = continuation; captured = request; received.fulfill() }
                    }
                }
                let model = CoachModel(configuration: { client }, savedPlanData: nil, profile: initial)
                let task = Task {
                    switch path {
                    case "chat": await model.send(message: "Help me plan", history: [], support: [])
                    case "proposal": await model.propose(history: [], support: [])
                    default: await model.summarize(history: [], kind: .weekly)
                    }
                }
                await fulfillment(of: [received], timeout: 2)

                model.updateProfile(changed)
                XCTAssertFalse(model.isLoading)
                pending?.resume(returning: try Self.response(for: XCTUnwrap(captured)))
                await task.value

                XCTAssertFalse(model.turns.contains { $0.role == .model }, path)
                XCTAssertNil(model.proposal, path)
                XCTAssertNil(model.summary, path)
                XCTAssertNil(model.error, path)
            }
        }
    }

    func testChangingOnlyTheOptionalNameDoesNotDiscardAnUnchangedGoalsResponse() async throws {
        let initial = try LocalProfile(name: "Initial Name", weeklyTarget: 3, goals: [.strength])
        let renamed = try LocalProfile(name: "Updated Name", weeklyTarget: 3, goals: [.strength])
        let received = expectation(description: "Request entered transport")
        var pending: CheckedContinuation<(Data, URLResponse), Never>?
        var captured: URLRequest?
        let client = CoachGatewayClient(baseURL: URL(string: "https://coach.example")!, token: "test") { request in
            await withCheckedContinuation { continuation in
                Task { @MainActor in pending = continuation; captured = request; received.fulfill() }
            }
        }
        let model = CoachModel(configuration: { client }, savedPlanData: nil, profile: initial)
        let task = Task { await model.send(message: "Help me plan", history: [], support: []) }
        await fulfillment(of: [received], timeout: 2)

        model.updateProfile(renamed)
        pending?.resume(returning: try Self.response(for: XCTUnwrap(captured)))
        await task.value

        XCTAssertTrue(model.turns.contains { $0.role == .model })
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.error)
    }

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

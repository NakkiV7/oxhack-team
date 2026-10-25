import Foundation
import Testing
@testable import SpottrCore

private func json(_ value: Any) -> Data { try! JSONSerialization.data(withJSONObject: value) }
private func object(_ data: Data) -> [String: Any] { (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:] }
private let squatBeginner = PathSurvey(goal: .squat, abilityKey: "new", equipment: ["Stable support"])

/// A plan as the gateway returns it for the squat path.
private func plan(_ request: PathProposalRequest, start: String = "gluteBridge", route: [String]? = nil, extra: [[String: Any]] = []) -> Data {
    let target: [String: Any] = ["sets": 3, "target": 8, "perWeek": 3]
    func node(_ id: String, _ prerequisites: [String], optional: Bool = false, supports: String? = nil) -> [String: Any] {
        ["id": id, "why": "Why \(id).", "prerequisites": prerequisites, "optional": optional, "supports": supports as Any? ?? NSNull(), "practiceTarget": target]
    }
    let nodes = [node("gluteBridge", []), node("squat", ["gluteBridge"]), node("reverseLunge", ["squat"]), node("splitSquat", ["reverseLunge"]),
                 node("assistedSquat", ["splitSquat"]), node("singleLegBalance", [], optional: true, supports: "reverseLunge")] + extra
    return json(["generationID": request.generationID, "nodes": nodes, "start": start, "goalNode": "assistedSquat",
                 "route": route ?? ["gluteBridge", "squat", "reverseLunge", "splitSquat", "assistedSquat"],
                 "rationale": "Builds from the pattern to single-leg control.", "startReason": "Starting at the foundation.", "emphasis": "Smooth reps."])
}

@Test func pathRequestsCarryOnlyWhatTheAppAllows() throws {
    let request = PathProposalRequest(survey: squatBeginner, generationID: "path-1")
    let body = object(try JSONEncoder().encode(request))
    let answers = try #require(body["answers"] as? [String: Any])
    #expect(answers["band"] as? String == "beginner" && answers["focus"] is NSNull && answers["coachingStyle"] is NSNull)
    let exercises = try #require(body["exercises"] as? [[String: Any]])
    let ids = exercises.compactMap { $0["id"] as? String }
    #expect(!ids.contains("wallPushup") && !ids.contains("inclinePushup") && ids.contains("assistedSquat"))   // equipment filter
    let squat = try #require(exercises.first { $0["id"] as? String == "squat" })
    #expect(squat["capability"] as? String == "cameraAssessment" && squat["maxTarget"] as? Int == 18)
    #expect(exercises.first { $0["id"] as? String == "pushup" }?["capability"] as? String == "cameraAssessment")
    #expect(exercises.first { $0["id"] as? String == "plank" }?["capability"] as? String == "practiceLog")
    #expect(request.allowedStarts == ["gluteBridge"] && request.ruleStart == "gluteBridge" && request.repair.isEmpty)
    let experienced = PathProposalRequest(survey: PathSurvey(goal: .squat, abilityKey: "comfortable"), repair: ["squat: practice target outside the allowed range"])
    #expect(experienced.allowedStarts == ["gluteBridge", "squat"] && experienced.ruleStart == "squat" && experienced.repair.count == 1)
}

@Test func aValidPlanBecomesAGeminiPathBoundedByPlacement() throws {
    let request = PathProposalRequest(survey: squatBeginner)
    let path = try PathProposalContracts.path(from: plan(request), request: request, survey: squatBeginner)
    #expect(path.provenance == .gemini && path.start == "gluteBridge" && path.nodes.allSatisfy { !$0.notRequired })
    #expect(path.node("singleLegBalance")?.supports == "reverseLunge" && TrainingPathRules.validate(path, survey: squatBeginner).isEmpty)

    let experienced = PathSurvey(goal: .squat, abilityKey: "control", equipment: ["Stable support"])
    let laterRequest = PathProposalRequest(survey: experienced)
    let later = try PathProposalContracts.path(from: plan(laterRequest, start: "squat", route: ["squat", "reverseLunge", "splitSquat", "assistedSquat"]),
                                               request: laterRequest, survey: experienced)
    #expect(later.start == "squat" && later.node("gluteBridge")?.notRequired == true && later.placementSource == .selfReported)
    // A start the answers do not allow is replaced by the rule's start, and a broken route by the default one.
    let bounded = try PathProposalContracts.path(from: plan(request, start: "splitSquat", route: ["squat"]), request: request, survey: squatBeginner)
    #expect(bounded.start == "gluteBridge" && bounded.route == ["gluteBridge", "squat", "reverseLunge", "splitSquat", "assistedSquat"])
}

@Test func aPlanThatBreaksTheRulesIsRejectedWithRepairableReasons() async throws {
    let survey = PathSurvey(goal: .squat, abilityKey: "new", avoid: ["splitSquat"])
    let request = PathProposalRequest(survey: survey)
    #expect(throws: PathProposalError.invalid(["splitSquat: the person asked to leave this movement out"])) {
        try PathProposalContracts.path(from: plan(request), request: request, survey: survey)
    }
    #expect(throws: PathProposalError.staleGeneration) {
        try PathProposalContracts.path(from: plan(PathProposalRequest(survey: survey)), request: request, survey: survey)
    }

    final class Calls: @unchecked Sendable { var requests: [PathProposalRequest] = [] }
    let calls = Calls()
    let invalid = await PathGenerator.generate(survey: survey) { request in calls.requests.append(request); return plan(request) }
    #expect(calls.requests.count == 1)   // never an automatic paid retry
    #expect(invalid.path == TrainingPathRules.fallback(survey: survey) && invalid.path.provenance == .catalogueFallback)
    #expect(invalid.repairable == ["splitSquat: the person asked to leave this movement out"])
    let repaired = await PathGenerator.generate(survey: survey, repair: invalid.repairable) { request in calls.requests.append(request); return plan(request) }
    #expect(calls.requests.last?.repair == invalid.repairable && repaired.path.provenance == .catalogueFallback)
    let offline = await PathGenerator.generate(survey: squatBeginner) { _ in throw CoachGatewayError.rejected(503) }
    #expect(offline.path.provenance == .catalogueFallback && offline.repairable.isEmpty && offline.problems == ["The coach couldn’t respond (503). Try again."])
    let used = await PathGenerator.generate(survey: squatBeginner) { request in plan(request) }
    #expect(used.path.provenance == .gemini && used.problems.isEmpty)
}

private func waitingLoop(_ contract: TempoContract, _ values: [Double]) -> CoachAttemptLoop {
    let start = Date(timeIntervalSince1970: 1_790_000_000)
    var loop = CoachAttemptLoop(contract: contract, startedAt: start)
    loop.begin(at: start)
    for (i, value) in values.enumerated() {
        let rep = contract.metric == .lowering ? LoopRep(lowering: value, total: 3, flexion: 80) : LoopRep(total: value, flexion: 80)
        _ = loop.onRep(rep, at: start.addingTimeInterval(Double(i + 1) * 4))
    }
    return loop
}

@Test func cueRequestsComeFromTheOpenBaselineAndRepliesStayGrounded() throws {
    let loop = waitingLoop(.squat, [1.3, 1.4, 1.32])
    let request = try #require(AttemptCueRequest(loop: loop, coachingStyle: .concise))
    #expect(request.generationID == loop.requestID?.uuidString && request.baseline == .init(validReps: 3, median: 1.32))
    #expect(request.facts.map(\.text) == ["Baseline median lowering time 1.32 s over 3 counted squats.",
                                         "Baseline lowering time per rep: 1.3 s, 1.4 s, 1.32 s.", "Target lowering time 1.5 s, within 0.15 s."])
    let body = object(try JSONEncoder().encode(request))
    #expect((body["contract"] as? [String: Any])?["metric"] as? String == "lowering" && body["coachingStyle"] as? String == "concise")
    func reply(_ action: String, _ text: String, _ facts: [String] = ["target"], id: String? = nil) -> Data {
        json(["generationID": id ?? request.generationID, "action": action, "text": text, "factIDs": facts])
    }
    let cue = try AttemptCueContracts.cue(from: reply("cue_target", "Count to 2 as you lower, aiming for 1.5 s."), request: request)
    #expect(cue.action == .cueTarget && cue.provenance == .gemini)
    #expect(throws: CoachContractError.invalidProposal) { try AttemptCueContracts.cue(from: reply("maintain_target", "Keep that rhythm."), request: request) }
    #expect(throws: CoachContractError.invalidEvidence) { try AttemptCueContracts.cue(from: reply("cue_target", "Aim for 1.7 s."), request: request) }
    #expect(throws: CoachContractError.invalidEvidence) { try AttemptCueContracts.cue(from: reply("cue_target", "Slow down.", ["invented"]), request: request) }
    #expect(throws: CoachContractError.staleGeneration) { try AttemptCueContracts.cue(from: reply("cue_target", "Slow down.", id: "old"), request: request) }
    #expect(AttemptCueRequest(loop: CoachAttemptLoop(contract: .squat, startedAt: Date())) == nil)   // nothing to cue yet

    let pushups = try #require(AttemptCueRequest(loop: waitingLoop(.pushup, [1.9, 2.1, 2.0])))
    #expect(pushups.facts[0].text == "Baseline median rep time 2 s over 3 counted push-ups." && pushups.coachingStyle == nil)
    let keep = try AttemptCueContracts.cue(from: json(["generationID": pushups.generationID, "action": "maintain_target",
                                                       "text": "Keep each push-up at about 2 s.", "factIDs": ["baseline"]]), request: pushups)
    #expect(keep.action == .maintainTarget)
}

@Test func explanationsDescribeTheComputedResultOnly() throws {
    let record = completedAttempt(baseline: [0.9, 1.0, 0.8], retry: [1.45, 1.5, 1.6], at: Date(timeIntervalSince1970: 1_790_000_000))
    let request = try #require(AttemptExplanationRequest(record: record, coachingStyle: .encouraging))
    #expect(request.outcome == .init(classification: "closer", retryMeets: true))
    #expect(request.facts.map(\.id) == ["result", "target", "baseline", "retry", "rule"])
    #expect(request.facts[3].text == "Retry median lowering time 1.5 s over 3 counted squats, within the target tolerance.")
    let good = json(["generationID": request.generationID, "text": "Your retry median of 1.5 s landed within 0.15 s of the target.", "factIDs": ["retry", "target"]])
    #expect(try AttemptCueContracts.explanation(from: good, request: request).hasPrefix("Your retry median"))
    let invented = json(["generationID": request.generationID, "text": "You improved by 67 percent.", "factIDs": ["result"]])
    #expect(throws: CoachContractError.invalidEvidence) { try AttemptCueContracts.explanation(from: invented, request: request) }
    var unfinished = CoachAttemptLoop(contract: .squat, startedAt: Date())
    unfinished.begin(at: Date())
    #expect(AttemptExplanationRequest(record: unfinished.record) == nil)
}

@Test func clientPostsEachTaskToItsRouteWithTheBearerToken() async throws {
    final class Seen: @unchecked Sendable { var paths: [String] = [] }
    let seen = Seen(), loop = waitingLoop(.squat, [1.3, 1.4, 1.32])
    let cueRequest = try #require(AttemptCueRequest(loop: loop))
    let client = CoachGatewayClient(baseURL: URL(string: "https://coach.example")!, token: "local-token") { request in
        seen.paths.append(request.url?.path ?? "")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer local-token")
        let body = object(request.httpBody ?? Data())
        let generation = body["generationID"] as? String ?? ""
        let reply: [String: Any] = request.url?.path == "/v1/attempt-cue"
            ? ["generationID": generation, "action": "cue_target", "text": "Count to 2 as you lower.", "factIDs": ["target"]]
            : ["generationID": generation, "text": "Plan.", "factIDs": ["target"]]
        return (json(reply), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    let cue = try await client.attemptCue(cueRequest)
    #expect(cue.text == "Count to 2 as you lower.")
    _ = try await client.pathProposal(PathProposalRequest(survey: squatBeginner))
    #expect(seen.paths == ["/v1/attempt-cue", "/v1/path-proposal"])
}

/// Recorded from a live gemini-3.5-flash reply through this gateway on 25 October 2026 (only the generation id is replaced).
/// The plan passed the server's structural checks but ended the path at squats with two steps after it.
private let recordedEarlyGoalPlan = #"""
{"generationID":"recorded","start":"gluteBridge","goalNode":"squat","route":["gluteBridge","squat"],
"nodes":[
{"id":"gluteBridge","why":"Glute bridges are a fantastic way to activate your hips before squatting, though camera tracking is not trained for it yet.","prerequisites":[],"optional":false,"supports":null,"practiceTarget":{"sets":2,"target":10,"perWeek":3}},
{"id":"squat","why":"Squats will help build lower-body strength and confidence as you learn proper technique.","prerequisites":["gluteBridge"],"optional":false,"supports":null,"practiceTarget":{"sets":3,"target":12,"perWeek":3}},
{"id":"reverseLunge","why":"Reverse lunges are wonderful for developing leg balance and power, though camera tracking is not trained for it yet.","prerequisites":["squat"],"optional":false,"supports":null,"practiceTarget":{"sets":2,"target":10,"perWeek":3}},
{"id":"splitSquat","why":"Split squats will further enhance your leg strength and stability, though camera tracking is not trained for it yet.","prerequisites":["reverseLunge"],"optional":false,"supports":null,"practiceTarget":{"sets":2,"target":8,"perWeek":3}}],
"rationale":"This path starts with glute bridges to build baseline hip activation before progressing directly into squats. It fits your beginner level and three weekly sessions perfectly while giving you a clear structure to learn.",
"startReason":"Starting with glute bridges allows you to safely build hip stability and warm up before progressing to squats.",
"emphasis":"Focusing on proper form and controlled movement will help you learn each exercise with total confidence."}
"""#

@Test func aRecordedGeminiPlanThatStoppedEarlyFallsBackWithARepairableReason() async {
    let survey = PathSurvey(goal: .squat, abilityKey: "new", equipment: ["Stable support"], focus: .learn, coachingStyle: .encouraging)
    let request = PathProposalRequest(survey: survey, generationID: "recorded")
    #expect(throws: PathProposalError.invalid(["goal node must be the last step of the main chain (splitSquat)"])) {
        try PathProposalContracts.path(from: Data(recordedEarlyGoalPlan.utf8), request: request, survey: survey)
    }
    let outcome = await PathGenerator.generate(survey: survey) { request in
        Data(recordedEarlyGoalPlan.replacingOccurrences(of: "\"recorded\"", with: "\"\(request.generationID)\"").utf8)
    }
    #expect(outcome.path.provenance == .catalogueFallback && outcome.repairable == ["goal node must be the last step of the main chain (splitSquat)"])
}

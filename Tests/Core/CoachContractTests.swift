import Foundation
import Testing
@testable import SpottrCore

private let coachContext = CoachValidationContext(generationID: "generation-1", suppliedFactIDs: ["session-1.reps"], availableSupport: [])
private let validProposal = #"{"generationID":"generation-1","items":[{"exerciseID":"pushup","sets":3,"target":10,"unit":"reps","restSeconds":60,"factIDs":["session-1.reps"]}],"rationale":{"text":"Keep the recorded target.","factIDs":["session-1.reps"]}}"#

@Test func coachProposalRequiresExplicitSelection() throws {
    let proposal = try CoachContracts.parseProposal(Data(validProposal.utf8), context: coachContext)
    #expect(proposal.items.first?.exerciseID == "pushup")
    #expect(throws: CoachContractError.self) {
        try CoachContracts.approvedItems(from: proposal, selectedExerciseIDs: [], context: coachContext)
    }
    let selected = try CoachContracts.approvedItems(from: proposal, selectedExerciseIDs: ["pushup"], context: coachContext)
    #expect(selected.count == 1)
    #expect(selected.first?.target == 10)
}

@Test(arguments: [
    ("pushup", "inventedExercise"),
    ("\"sets\":3", "\"sets\":0"),
    ("\"sets\":3", "\"sets\":11"),
    ("\"target\":10", "\"target\":201"),
    ("\"unit\":\"reps\"", "\"unit\":\"seconds\""),
    ("\"restSeconds\":60", "\"restSeconds\":601"),
    ("session-1.reps", "inventedFact"),
    ("generation-1", "generation-old"),
    ("pushup", "wallPushup"),
    ("\"factIDs\":[\"session-1.reps\"]", "\"factIDs\":[]"),
    ("\"factIDs\":[\"session-1.reps\"]", "\"factIDs\":[\"session-1.reps\",\"session-1.reps\"]"),
    ("\"sets\":3", "\"sets\":3,\"surprise\":true"),
    ("Keep the recorded target.", " ")
])
func coachRejectsUnusableProposal(replacement: (String, String)) {
    let input = validProposal.replacingOccurrences(of: replacement.0, with: replacement.1)
    #expect(throws: (any Error).self) { try CoachContracts.parseProposal(Data(input.utf8), context: coachContext) }
}

@Test func coachRejectsDuplicateExercisesAndOversizedPayloads() throws {
    let item = #"{"exerciseID":"pushup","sets":3,"target":10,"unit":"reps","restSeconds":60,"factIDs":["session-1.reps"]}"#
    let input = validProposal.replacingOccurrences(of: "[\(item)]", with: "[\(item),\(item)]")
    #expect(throws: (any Error).self) { try CoachContracts.parseProposal(Data(input.utf8), context: coachContext) }
    #expect(throws: (any Error).self) { try CoachContracts.parseProposal(Data(repeating: 32, count: 65_537), context: coachContext) }
}

@Test func coachSummariesRemainGroundedAndBounded() throws {
    let input = #"{"generationID":"generation-1","kind":"session","headline":{"text":"Ten repetitions recorded.","factIDs":["session-1.reps"]},"insights":[],"focus":{"text":"Review the same target next session.","factIDs":["session-1.reps"]}}"#
    let summary = try CoachContracts.parseSummary(Data(input.utf8), context: coachContext, kind: .session)
    #expect(summary.insights.isEmpty)
    #expect(throws: CoachContractError.self) { try CoachContracts.parseSummary(Data(input.utf8), context: coachContext, kind: .weekly) }
    #expect(throws: CoachContractError.self) {
        try CoachContracts.parseSummary(Data(input.replacingOccurrences(of: "session-1.reps", with: "unknown").utf8), context: coachContext, kind: .session)
    }
    let text = #"{"text":"An observation.","factIDs":["session-1.reps"]}"#
    let tooMany = input.replacingOccurrences(of: "\"insights\":[]", with: "\"insights\":[\(Array(repeating: text, count: 4).joined(separator: ","))]")
    #expect(throws: CoachContractError.self) { try CoachContracts.parseSummary(Data(tooMany.utf8), context: coachContext, kind: .session) }
}

@Test func coachProposalUsesConservativeConfigurableVolumeLimits() throws {
    for input in [validProposal.replacingOccurrences(of: "\"sets\":3", with: "\"sets\":6"), validProposal.replacingOccurrences(of: "\"target\":10", with: "\"target\":31")] {
        #expect(throws: CoachContractError.self) { try CoachContracts.parseProposal(Data(input.utf8), context: coachContext) }
    }
    let limited = CoachValidationContext(generationID: "generation-1", suppliedFactIDs: ["session-1.reps"], availableSupport: [], planLimits: .init(maxTotalSets: 2))
    #expect(throws: CoachContractError.self) { try CoachContracts.parseProposal(Data(validProposal.utf8), context: limited) }
    let hold = validProposal.replacingOccurrences(of: "pushup", with: "plank").replacingOccurrences(of: "\"unit\":\"reps\"", with: "\"unit\":\"seconds\"").replacingOccurrences(of: "\"target\":10", with: "\"target\":121")
    #expect(throws: CoachContractError.self) { try CoachContracts.parseProposal(Data(hold.utf8), context: coachContext) }
}

@Test func coachCannotApproveUnknownOrStaleSelectionsAndSupportsTimedPlans() throws {
    let proposal = try CoachContracts.parseProposal(Data(validProposal.utf8), context: coachContext)
    #expect(throws: CoachContractError.self) { try CoachContracts.approvedItems(from: proposal, selectedExerciseIDs: ["squat"], context: coachContext) }
    let stale = CoachValidationContext(generationID: "generation-2", suppliedFactIDs: ["session-1.reps"], availableSupport: [])
    #expect(throws: CoachContractError.self) { try CoachContracts.approvedItems(from: proposal, selectedExerciseIDs: ["pushup"], context: stale) }
    let hold = validProposal.replacingOccurrences(of: "pushup", with: "plank").replacingOccurrences(of: "\"unit\":\"reps\"", with: "\"unit\":\"seconds\"")
    #expect(try CoachContracts.parseProposal(Data(hold.utf8), context: coachContext).items.first?.unit == .seconds)
    let support = CoachValidationContext(generationID: "generation-1", suppliedFactIDs: ["session-1.reps"], availableSupport: ["Wall"])
    let wall = validProposal.replacingOccurrences(of: "pushup", with: "wallPushup")
    #expect(try CoachContracts.parseProposal(Data(wall.utf8), context: support).items.first?.exerciseID == "wallPushup")
}

@Test func coachRejectsTotalVolumeAndMalformedShapes() {
    let items = ["pushup", "squat", "deadBug", "catCow", "stepJack"].map {
        #"{"exerciseID":""# + $0 + #"","sets":5,"target":10,"unit":"reps","restSeconds":60,"factIDs":["session-1.reps"]}"#
    }.joined(separator: ",")
    let excessive = #"{"generationID":"generation-1","items":["# + items + #"],"rationale":{"text":"Recorded training.","factIDs":["session-1.reps"]}}"#
    for input in [excessive, "{", validProposal.replacingOccurrences(of: "\"sets\":3", with: "\"sets\":true"), validProposal.replacingOccurrences(of: "\"items\":[", with: "\"unknown\":[")] {
        #expect(throws: CoachContractError.self) { try CoachContracts.parseProposal(Data(input.utf8), context: coachContext) }
    }
    let invalidLimits = CoachValidationContext(generationID: "generation-1", suppliedFactIDs: ["session-1.reps"], availableSupport: [], planLimits: .init(maxReps: -1))
    #expect(throws: CoachContractError.self) { try CoachContracts.parseProposal(Data(validProposal.utf8), context: invalidLimits) }
}

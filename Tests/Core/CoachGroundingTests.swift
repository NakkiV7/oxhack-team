import XCTest
@testable import SpottrCore

final class CoachGroundingTests: XCTestCase {
    func testEmptyHistoryIsExplicitAndSkillPointsAreNotFitnessMeasurements() {
        let facts = CoachGrounding.facts(history: [])
        XCTAssertTrue(facts.contains { $0.id == "context" && $0.text.contains("0 saved sessions") })
        XCTAssertTrue(facts.contains { $0.id == "skill-strength" && $0.text.contains("game points") })
        XCTAssertEqual(Set(facts.map(\.id)).count, facts.count)
        XCTAssertFalse(facts.contains { $0.text.contains("bpm") })
    }
    func testSavedSelectionSurvivesRoundTripAndNeverAddsUnselectedExercise() throws {
        let context = CoachValidationContext(generationID: "g", suppliedFactIDs: ["context"], availableSupport: [])
        let proposal = try CoachContracts.parseProposal(Data(#"{"generationID":"g","items":[{"exerciseID":"squat","sets":2,"target":8,"unit":"reps","restSeconds":60,"factIDs":["context"]},{"exerciseID":"plank","sets":1,"target":15,"unit":"seconds","restSeconds":30,"factIDs":["context"]}],"rationale":{"text":"A short session.","factIDs":["context"]}}"#.utf8), context: context)
        let plan = try CoachSavedPlan(proposal: proposal, selectedExerciseIDs: ["plank"], context: context)
        let restored = try JSONDecoder().decode(CoachSavedPlan.self, from: JSONEncoder().encode(plan))
        XCTAssertEqual(restored.items.map(\.exerciseID), ["plank"])
        XCTAssertEqual(restored.items.first?.target, 15)
        XCTAssertThrowsError(try CoachSavedPlan(proposal: proposal, selectedExerciseIDs: [], context: context))
    }
    func testRepeatedSavedSetIsSharedOnlyOnce() throws {
        let original = try LoggedWorkout.make(exerciseID: "squat", count: 12, sets: 1, reason: .voluntary)
        let duplicate = SessionRecord(id: UUID(), date: original.date, sets: [], loggedSets: original.loggedSets)
        let facts = CoachGrounding.facts(history: [original, duplicate])
        XCTAssertEqual(Set(facts.map(\.id)).count, facts.count)
    }

}

import Foundation
import Testing
@testable import SpottrCore

@Test func skillRoutesCoverTheCatalogAndStayAcyclic() {
    let ids = Set(ExerciseCatalog.all.map(\.id))
    #expect(Set(SkillGraph.exerciseIDs) == ids)
    #expect(Set(SkillGraph.edges).count == SkillGraph.edges.count)
    for edge in SkillGraph.edges {
        #expect(ids.contains(edge.from))
        #expect(ids.contains(edge.to))
        #expect(edge.from != edge.to)
        #expect(SkillGraph.tier(of: edge.from) < SkillGraph.tier(of: edge.to))
    }
    #expect(SkillGraph.prerequisites(for: "missing").isEmpty)
}

@Test func advancedChallengesCombineProgressionAndSupportingBranches() {
    #expect(Set(SkillGraph.prerequisites(for: "pushup")) == ["kneePushup", "plank"])
    #expect(Set(SkillGraph.prerequisites(for: "reverseLunge")) == ["squat", "singleLegBalance"])
    #expect(Set(SkillGraph.prerequisites(for: "mountainClimber")) == ["highKnees", "plank"])
    #expect(SkillGraph.dependents(of: "plank").contains("pushup"))
    #expect(SkillGraph.dependents(of: "plank").contains("mountainClimber"))
}

@Test func achievementNeedsEveryParentAndRetainsPracticeBeforeUnlock() throws {
    let date = Date(timeIntervalSince1970: 1_790_000_000)
    func completed(_ id: String) throws -> [SessionRecord] {
        let entry = try #require(ExerciseCatalog.find(id))
        return [try LoggedWorkout.make(exerciseID: id, count: entry.goal, sets: 2, date: date),
                try LoggedWorkout.make(exerciseID: id, count: entry.goal, sets: 1, date: date.addingTimeInterval(86400))]
    }
    let push = try ["wallPushup", "inclinePushup", "kneePushup", "pushup"].flatMap(completed)
    let before = SkillProgress.evaluate(history: push)
    #expect(before.node(exerciseID: "pushup")?.qualifyingSets == 3)
    #expect(before.node(exerciseID: "pushup")?.isAvailable == false)
    #expect(before.node(exerciseID: "pushup")?.isComplete == false)
    let after = SkillProgress.evaluate(history: push + (try ["deadBug", "plank"].flatMap(completed)))
    #expect(after.node(exerciseID: "pushup")?.isAvailable == true)
    #expect(after.node(exerciseID: "pushup")?.isComplete == true)
    #expect(after.node(exerciseID: "closeGripPushup")?.isAvailable == false)
}

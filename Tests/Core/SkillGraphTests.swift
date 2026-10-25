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

@Test func earnedConnectionsExplainRemainingParentsWithoutPreviewGrantingProgress() throws {
    let date = Date(timeIntervalSince1970: 1_790_000_000)
    let empty = SkillProgress.evaluate(history: [])
    #expect(empty.pendingPrerequisiteIDs(for: "pushup") == ["kneePushup", "plank"])
    #expect(!empty.isConnectionEarned(from: "kneePushup", to: "pushup"))
    #expect(empty.access(exerciseID: "pushup", previewUnlock: true) == .preview)
    #expect(!empty.isConnectionEarned(from: "plank", to: "pushup"))

    let history = try ["wallPushup", "inclinePushup", "kneePushup"].flatMap { id in
        [try LoggedWorkout.make(exerciseID: id, count: 8, sets: 2, date: date),
         try LoggedWorkout.make(exerciseID: id, count: 8, sets: 1, date: date.addingTimeInterval(86400))]
    }
    let partial = SkillProgress.evaluate(history: history)
    #expect(partial.isConnectionEarned(from: "kneePushup", to: "pushup"))
    #expect(!partial.isConnectionEarned(from: "plank", to: "pushup"))
    #expect(!partial.isConnectionEarned(from: "wallPushup", to: "pushup"))
    #expect(!partial.isConnectionEarned(from: "missing", to: "pushup"))
    #expect(partial.pendingPrerequisiteIDs(for: "pushup") == ["plank"])
    #expect(partial.pendingPrerequisiteIDs(for: "wallPushup").isEmpty)
    #expect(partial.pendingPrerequisiteIDs(for: "missing").isEmpty)
    #expect(partial.access(exerciseID: "pushup") == .locked)
}

@Test func manualAndCameraGoalSetsCanEarnTogetherWithSeparateProvenance() throws {
    let date = Date(timeIntervalSince1970: 1_790_000_000)
    let bridge = try [LoggedWorkout.make(exerciseID: "gluteBridge", count: 12, sets: 2, date: date),
                      LoggedWorkout.make(exerciseID: "gluteBridge", count: 12, sets: 1, date: date.addingTimeInterval(86400))]
    let manual = try LoggedWorkout.make(exerciseID: "squat", count: 12, sets: 2, date: date)
    let camera = SetRecord(id: UUID(), exercise: .squat, number: 1, reps: 12, target: 12,
                           activeSeconds: 30, source: .camera, reason: .target)
    let replay = SetRecord(id: UUID(), exercise: .squat, number: 2, reps: 12, target: 12,
                           activeSeconds: 30, source: .video, reason: .target)
    let tracked = SessionRecord(id: UUID(), date: date.addingTimeInterval(86400), sets: [camera, replay])
    let progress = SkillProgress.evaluate(history: bridge + [manual, tracked])
    let node = try #require(progress.node(exerciseID: "squat"))
    #expect(progress.access(exerciseID: "squat") == .earned)
    #expect(node.manualSets == 2)
    #expect(node.cameraSets == 1)
    #expect(node.qualifyingSets == 3)
    #expect(node.trainingDays == 2)
    #expect(progress.pendingPrerequisiteIDs(for: "squat").isEmpty)
    #expect(progress.isConnectionEarned(from: "gluteBridge", to: "squat"))
}

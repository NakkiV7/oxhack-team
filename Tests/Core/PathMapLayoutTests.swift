import Foundation
import Testing
@testable import SpottrCore

@Test func theMainChainRunsInLevelOrderWithSideStepsInTheirOwnLanes() {
    // Beginner squat path: glute bridges to assisted single-leg squats, with the single-leg stand as the optional branch.
    let path = TrainingPathRules.fallback(survey: PathSurvey(goal: .squat, abilityKey: "new"))
    let map = PathMapLayout.make(path: path)
    let chain = ["gluteBridge", "squat", "reverseLunge", "splitSquat", "assistedSquat"]
    #expect(chain.map { map.positions[$0]!.lane } == [0, 0, 0, 0, 0])
    #expect(chain.map { map.positions[$0]!.y } == [64, 214, 364, 514, 664])        // one step apart, foundation at the top
    let branch = map.positions["singleLegBalance"]!
    #expect(branch.lane == 1 && branch.axis == map.positions["reverseLunge"]!.axis)  // beside the step it supports
    #expect(map.order == ["gluteBridge", "squat", "singleLegBalance", "reverseLunge", "splitSquat", "assistedSquat"])
    #expect(map.edges.contains(.init(from: "singleLegBalance", to: "reverseLunge", kind: .support)))
    #expect(map.edges.filter { $0.kind == .prerequisite }.count == 4)
    #expect(map.width == 2 * (64 + 14) + 118 && map.height == 2 * 64 + 4 * 150)
    #expect(PathMapLayout.role(of: path.node("assistedSquat")!, in: path) == .goal)
    #expect(PathMapLayout.role(of: path.node("squat")!, in: path) == .milestone)
    #expect(PathMapLayout.role(of: path.node("gluteBridge")!, in: path) == .standard)
    #expect(PathMapLayout.role(of: path.node("singleLegBalance")!, in: path) == .optional)
}

@Test func aSupportingPrerequisiteSitsHalfAStepBeforeTheStepItUnlocks() {
    // Comfortable push-ups with nothing nearby: knee push-ups, push-ups, close-grip, with the plank as the optional branch.
    var path = TrainingPathRules.fallback(survey: PathSurvey(goal: .pushup, abilityKey: "comfortable", equipment: []))
    path.nodes.append(PathNode(id: "sidePlank", why: "Supports close-grip push-ups."))
    path.nodes[path.nodes.firstIndex { $0.id == "closeGripPushup" }!].prerequisites.append("sidePlank")
    let map = PathMapLayout.make(path: path)
    let support = map.positions["sidePlank"]!, dependant = map.positions["closeGripPushup"]!
    #expect(support.lane == -1 && support.axis == dependant.axis - 0.5)
    #expect(map.positions["plank"]!.lane == 1)
    let horizontal = PathMapLayout.make(path: path, orientation: .horizontal)
    #expect(horizontal.positions["kneePushup"]!.x < horizontal.positions["pushup"]!.x && horizontal.width > horizontal.height)
    #expect(PathMapLayout.make(path: path) == map)   // same path, same picture
}

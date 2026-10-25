import Foundation
import Testing
@testable import SpottrCore

private let profiles: [(name: String, survey: PathSurvey)] = [
    ("new squatter, equipment not asked", PathSurvey(goal: .squat, abilityKey: "new")),
    ("comfortable squatter", PathSurvey(goal: .squat, abilityKey: "comfortable", focus: .improve)),
    ("unsure squatter with no equipment", PathSurvey(goal: .squat, abilityKey: "unsure", equipment: [])),
    ("first push-up, wall only", PathSurvey(goal: .pushup, abilityKey: "first", equipment: ["Wall"])),
    ("comfortable push-ups, nothing nearby", PathSurvey(goal: .pushup, abilityKey: "comfortable", equipment: []))
]

@Test func fallbackPathsAreValidAndDifferForDifferentAnswers() {
    let paths = profiles.map { TrainingPathRules.fallback(survey: $0.survey) }
    for (profile, path) in zip(profiles, paths) {
        #expect(TrainingPathRules.validate(path, survey: profile.survey).isEmpty, "\(profile.name)")
        #expect(path.provenance == .catalogueFallback)
        #expect(path.route.first == path.start && path.route.last == path.goalNode)
        #expect(path.nodes.filter(\.optional).count <= 1)
    }
    let shapes = Set(paths.map { "\($0.start)|\($0.goalNode)|\($0.nodes.map(\.id).sorted().joined(separator: ","))" })
    #expect(shapes.count == profiles.count)
    #expect(!paths[2].nodes.contains { $0.id == "assistedSquat" })   // needs a stable support the person does not have
    #expect(paths[3].nodes.contains { $0.id == "wallPushup" } && !paths[3].nodes.contains { $0.id == "inclinePushup" })
    #expect(!paths[4].nodes.contains { $0.id == "wallPushup" })
}

@Test func placementFollowsTheAnswersAndACameraCheck() {
    let nodes = TrainingPathRules.fallback(survey: PathSurvey(goal: .squat)).nodes
    let beginner = TrainingPathRules.placement(survey: PathSurvey(goal: .squat, abilityKey: "new"), nodes: nodes)
    #expect(beginner.start == "gluteBridge" && beginner.notRequired.isEmpty && beginner.source == .selfReported)
    let unsure = TrainingPathRules.placement(survey: PathSurvey(goal: .squat, abilityKey: "unsure"), nodes: nodes)
    #expect(unsure.start == "gluteBridge" && unsure.reason.contains("camera check"))
    let experienced = TrainingPathRules.placement(survey: PathSurvey(goal: .squat, abilityKey: "control"), nodes: nodes)
    #expect(experienced.start == "squat" && experienced.notRequired == ["gluteBridge"] && experienced.allowedStarts == ["gluteBridge", "squat"])
    let checked = TrainingPathRules.placement(survey: PathSurvey(goal: .squat, abilityKey: "new"), nodes: nodes,
                                              check: PlacementCheck(exerciseID: "squat", validReps: 3))
    #expect(checked.start == "squat" && checked.source == .cameraSupported)
    let tooFew = TrainingPathRules.placement(survey: PathSurvey(goal: .squat, abilityKey: "new"), nodes: nodes,
                                             check: PlacementCheck(exerciseID: "squat", validReps: 2))
    #expect(tooFew.start == "gluteBridge")
    // The onboarding baseline places someone who has not answered the starting-point question yet.
    let profile = try? LocalProfile(weeklyTarget: 7, baselineAbility: .regularPractice)
    let fromProfile = PathSurvey(profile: profile)
    #expect(fromProfile.band == .advanced && fromProfile.sessionsPerWeek == 6)
    #expect(TrainingPathRules.placement(survey: fromProfile, nodes: nodes).start == "squat")
}

@Test func leavingAMovementOutRemovesItAndKeepsTheChainLinked() {
    let survey = PathSurvey(goal: .squat, abilityKey: "new", avoid: ["reverseLunge", "squat"])
    let path = TrainingPathRules.fallback(survey: survey)
    #expect(!path.nodes.contains { $0.id == "reverseLunge" })
    #expect(path.nodes.contains { $0.id == "squat" })   // the goal movement can never be left out
    #expect(path.node("splitSquat")?.prerequisites.contains("squat") == true)
    #expect(TrainingPathRules.validate(path, survey: survey).isEmpty)
    #expect(PathGoal.squat.avoidable == ["gluteBridge", "reverseLunge", "splitSquat", "assistedSquat", "singleLegBalance", "hipFlexorStretch"])
}

@Test(arguments: ["unknown", "link", "cycle", "optionalGate", "equipment", "avoided", "target", "start", "route", "size"])
func validationRejectsEachRuleAGeneratedPathCouldBreak(rule: String) {
    let survey = PathSurvey(goal: .squat, abilityKey: "new", equipment: ["Stable support"], sessionsPerWeek: 3)
    var path = TrainingPathRules.fallback(survey: survey)
    #expect(TrainingPathRules.validate(path, survey: survey).isEmpty)
    var checked = survey
    func edit(_ id: String, _ change: (inout PathNode) -> Void) { if let i = path.nodes.firstIndex(where: { $0.id == id }) { change(&path.nodes[i]) } }
    switch rule {
    case "unknown": path.nodes.append(PathNode(id: "burpee", why: ""))
    case "link": edit("squat") { $0.prerequisites = ["assistedSquat"] }
    case "cycle": edit("gluteBridge") { $0.prerequisites = ["squat"] }
    case "optionalGate": edit("squat") { $0.prerequisites.append("singleLegBalance") }
    case "equipment": checked.equipment = []
    case "avoided": checked.avoid = ["splitSquat"]
    case "target": edit("squat") { $0.practiceTarget = PracticeTarget(sets: 3, target: 40, perWeek: 3) }
    case "start": path.start = "reverseLunge"; path.route = TrainingPathRules.defaultRoute(path)
    case "route": path.route = ["gluteBridge", "reverseLunge", "assistedSquat"]
    default: path.nodes = Array(path.nodes.prefix(3))
    }
    #expect(!TrainingPathRules.validate(path, survey: checked).isEmpty)
}

@Test func practiceTargetsScaleWithTheAnswersAndStayInsideTheirBounds() {
    let beginner = PathSurvey(goal: .squat, abilityKey: "new", minutesPerSession: 10, sessionsPerWeek: 9)
    #expect(PracticeTarget.standard(for: "squat", survey: beginner) == PracticeTarget(sets: 2, target: 7, perWeek: 6))
    let advanced = PathSurvey(goal: .squat, abilityKey: "comfortable", sessionsPerWeek: 3)
    #expect(PracticeTarget.standard(for: "squat", survey: advanced) == PracticeTarget(sets: 3, target: 12, perWeek: 3))
    #expect(PracticeTarget.standard(for: "plank", survey: beginner)?.target == 12)
    #expect(PracticeTarget(sets: 4, target: 18, perWeek: 3).isValid(for: "squat", survey: advanced))
    #expect(!PracticeTarget(sets: 5, target: 12, perWeek: 3).isValid(for: "squat", survey: advanced))
    #expect(!PracticeTarget(sets: 3, target: 19, perWeek: 3).isValid(for: "squat", survey: advanced))
    #expect(!PracticeTarget(sets: 3, target: 12, perWeek: 4).isValid(for: "squat", survey: advanced))
}

@Test func capabilitiesSeparateAssessmentCountingAndPractice() {
    #expect(PathCapability.of("squat") == .cameraAssessment)
    #expect(PathCapability.of("pushup") == .cameraCounting)
    #expect(PathCapability.of("gluteBridge") == .practiceLog)
    #expect(PathSurvey.equipmentChoices == ["Stable sofa or counter", "Stable support", "Wall"])
}

@Test func surveyAnswersDecodeWithDefaultsForMissingKeys() throws {
    let decoded = try JSONDecoder().decode(PathSurvey.self, from: Data(#"{"goal":"pushup","abilityKey":"few"}"#.utf8))
    #expect(decoded.goal == .pushup && decoded.band == .intermediate && decoded.equipment == nil && decoded.sessionsPerWeek == 3)
    let full = PathSurvey(goal: .squat, abilityKey: "control", equipment: ["Wall"], focus: .learn, coachingStyle: .encouraging, avoid: ["gluteBridge"])
    #expect(try JSONDecoder().decode(PathSurvey.self, from: JSONEncoder().encode(full)) == full)
}

import Foundation

public enum SkillCurriculum {
    public struct Chapter: Sendable, Identifiable {
        public let id: String
        public let title: String
        public let exerciseIDs: [String]
    }
    public enum State: String, Codable, Sendable { case earned, placed, available, locked }
    public struct Node: Equatable, Sendable, Identifiable {
        public var id: String { exerciseID }
        public let exerciseID: String
        public let state: State
        public let isUsable: Bool
        public let qualifyingSets: Int
        public let trainingDays: Int
        public let manualSets: Int
        public let cameraSets: Int
    }
    public struct Progress: Equatable, Sendable {
        public let nodes: [Node]
        public let points: Int
        public func node(_ exerciseID: String) -> Node? { nodes.first { $0.exerciseID == exerciseID } }
    }
    public static let chapters: [Chapter] = [
        .init(id: "foundations", title: "Foundations", exerciseIDs: ["seatedMarch", "seatedKneeExtension", "frontArmRaise", "wallPushup", "supportedSquat", "standingKneeRaise", "calfRaise", "wallPlank", "quarterSquat", "sitToStand"]),
        .init(id: "rhythm", title: "Rhythm", exerciseIDs: ["halfSquat", "gluteBridge", "deadBug", "birdDog", "kneePlank", "singleLegBalance", "stepJack", "standingBicepsCurl", "catCow", "wallSit"]),
        .init(id: "control", title: "Control", exerciseIDs: ["inclinePushup", "squat", "tempoHalfSquat", "pausedHalfSquat", "supportedSplitSquat", "standingHipAbduction", "standingHipExtension", "lateralArmRaise", "wallSlide", "tandemBalance", "kneeSidePlank", "hipFlexorStretch", "plank", "highKnees"]),
        .init(id: "strength", title: "Strength", exerciseIDs: ["kneePushup", "wideSquat", "narrowSquat", "reverseLunge", "forwardLunge", "lateralLunge", "highPlank", "sidePlank", "tempoSquat", "pausedSquat", "mountainClimber"]),
        .init(id: "flow", title: "Flow", exerciseIDs: ["pushup", "widePushup", "splitSquat"]),
        .init(id: "challenge", title: "Challenge", exerciseIDs: ["closeGripPushup", "tempoPushup", "pausedPushup", "diamondPushup", "assistedSquat"])
    ]
    public static var exerciseIDs: [String] { chapters.flatMap(\.exerciseIDs) }

    public static func evaluate(profile: LocalProfile, history: [SessionRecord], calendar: Calendar = .current) -> Progress {
        let skill = SkillProgress.evaluate(history: history, calendar: calendar)
        let prefs = profile.effectiveProgrammePreferences
        let earned = Set(skill.nodes.filter { $0.qualifyingSets >= 3 && $0.trainingDays >= 2 }.map(\.exerciseID))
        let placed = profile.comfortableExercises
        let passed = earned.union(placed)
        let nodes = exerciseIDs.compactMap { id -> Node? in
            guard let entry = ExerciseCatalog.find(id), let evidence = skill.node(exerciseID: id) else { return nil }
            let family = ExerciseCatalog.all.filter { $0.family == entry.family }
            let usableLevels = family.filter(prefs.canUse).map(\.level)
            let lower = usableLevels.filter { $0 < entry.level }.max()
            let available = lower == nil || family.contains { passed.contains($0.id) && $0.level >= lower! }
            let state: State = earned.contains(id) ? .earned : placed.contains(id) ? .placed : available ? .available : .locked
            return .init(exerciseID: id, state: state, isUsable: prefs.canUse(entry), qualifyingSets: evidence.qualifyingSets,
                         trainingDays: evidence.trainingDays, manualSets: evidence.manualSets, cameraSets: evidence.cameraSets)
        }
        return .init(nodes: nodes, points: TrainingAttribute.allCases.reduce(0) { $0 + skill.points(for: $1) })
    }
}

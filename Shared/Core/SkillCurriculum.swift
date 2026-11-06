import Foundation

public enum SkillCurriculum {
    /// Frozen, owner-scoped migration boundary. Only already-earned legacy benchmarks
    /// retain their original supporting identities; subsequent context-free imports cannot qualify.
    public struct BenchmarkPolicy: Codable, Equatable, Sendable {
        public let owner: WorkoutOwner
        private struct Support: Codable, Equatable, Hashable, Sendable {
            let recordID: UUID
            let setID: UUID
            let exerciseID: String
        }
        private let legacySupport: Set<Support>
        public init(owner: WorkoutOwner, legacyHistory: [SessionRecord], calendar: Calendar) {
            self.owner = owner
            let eligible = legacyHistory.filter {
                $0.trainingContext == nil || ($0.trainingContext?.owner == owner && $0.trainingContext?.age?.allowsTimePressureRewards == true)
            }
            let earned = Set(SkillProgress.evaluate(history: eligible, calendar: calendar).nodes
                .filter { $0.qualifyingSets >= 3 && $0.trainingDays >= 2 }.map(\.exerciseID))
            func supports(_ id: String, reps: Int, seconds: Double, source: InputSource, reason: StopReason) -> Bool {
                guard earned.contains(id), let entry = ExerciseCatalog.find(id), source != .video, reason != .discomfort else { return false }
                return entry.unit == .reps ? reps >= entry.goal && seconds == 0 : reps == 0 && seconds.isFinite && seconds >= Double(entry.goal)
            }
            legacySupport = Set(eligible.filter { $0.trainingContext == nil }.flatMap { record in
                let tracked = record.sets.filter { supports($0.exercise.rawValue, reps: $0.reps, seconds: 0, source: $0.source, reason: $0.reason) }
                    .map { Support(recordID: record.id, setID: $0.id, exerciseID: $0.exercise.rawValue) }
                let logged = record.loggedSets.filter { supports($0.exerciseID, reps: $0.reps, seconds: $0.seconds, source: $0.source, reason: $0.reason) }
                    .map { Support(recordID: record.id, setID: $0.id, exerciseID: $0.exerciseID) }
                return tracked + logged
            })
        }
        public func qualifiedHistory(_ history: [SessionRecord]) -> [SessionRecord] {
            history.compactMap { record in
                if let context = record.trainingContext {
                    return context.owner == owner && context.age?.allowsTimePressureRewards == true ? record : nil
                }
                let sets = record.sets.filter { legacySupport.contains(.init(recordID: record.id, setID: $0.id, exerciseID: $0.exercise.rawValue)) }
                let logged = record.loggedSets.filter { legacySupport.contains(.init(recordID: record.id, setID: $0.id, exerciseID: $0.exerciseID)) }
                guard !sets.isEmpty || !logged.isEmpty else { return nil }
                // Projection of remaining actual evidence, never synthetic sets or a permanent earned flag.
                return SessionRecord(id: record.id, date: record.date, sets: sets, telemetry: record.telemetry,
                    loggedSets: logged, skippedSets: record.skippedSets, endedAt: record.endedAt,
                    timeline: record.timeline, plannedWorkoutID: record.plannedWorkoutID)
            }
        }
    }

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

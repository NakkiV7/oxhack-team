import Foundation

public struct ManualHoldClock: Sendable {
    private var started: Double?
    private var accumulated = 0.0
    public init() {}
    public var isRunning: Bool { started != nil }
    public func elapsed(at time: Double) -> Double { accumulated + max(0, time - (started ?? time)) }
    public mutating func start(at time: Double) {
        guard started == nil, time.isFinite else { return }
        started = time
    }
    public mutating func pause(at time: Double) {
        guard time.isFinite else { return }
        accumulated = elapsed(at: time)
        started = nil
    }
}

public enum SkillGraph {
    public struct Edge: Hashable, Sendable {
        public let from: String
        public let to: String
    }
    public static let version = 1
    public static var exerciseIDs: [String] { ExerciseCatalog.all.map(\.id) }
    public static var edges: [Edge] {
        exerciseIDs.flatMap { id in prerequisites(for: id).map { Edge(from: $0, to: id) } }
    }
    public static func prerequisites(for id: String) -> [String] {
        guard let entry = ExerciseCatalog.find(id) else { return [] }
        let previous = ExerciseCatalog.all.first { $0.family == entry.family && $0.level == entry.level - 1 }
        let support: [String: [String]] = [
            "pushup": ["plank"], "closeGripPushup": ["sidePlank"],
            "reverseLunge": ["singleLegBalance"], "assistedSquat": ["hipFlexorStretch"],
            "mountainClimber": ["plank"]
        ]
        return (previous.map { [$0.id] } ?? []) + (support[id] ?? [])
    }
    public static func dependents(of id: String) -> [String] { edges.filter { $0.from == id }.map(\.to) }
    public static func tier(of id: String) -> Int {
        prerequisites(for: id).map { tier(of: $0) + 1 }.max() ?? 0
    }
}

public struct SkillNodeProgress: Sendable {
    public let exerciseID: String
    public let qualifyingSets: Int
    public let trainingDays: Int
    public let manualSets: Int
    public let cameraSets: Int
    public let isAvailable: Bool
    public let isComplete: Bool
}

public enum SkillAccess: Sendable {
    case earned, available, preview, locked
}

public struct SkillProgress: Sendable {
    public let nodes: [SkillNodeProgress]
    private let attributePoints: [TrainingAttribute: Int]

    public func points(for attribute: TrainingAttribute) -> Int { attributePoints[attribute, default: 0] }
    public func node(exerciseID: String) -> SkillNodeProgress? { nodes.first { $0.exerciseID == exerciseID } }

    public func pendingPrerequisiteIDs(for exerciseID: String) -> [String] {
        SkillGraph.prerequisites(for: exerciseID).filter { node(exerciseID: $0)?.isComplete != true }
    }

    public func isConnectionEarned(from: String, to: String) -> Bool {
        SkillGraph.prerequisites(for: to).contains(from) && node(exerciseID: from)?.isComplete == true
    }

    public func access(exerciseID: String, previewUnlock: Bool = false) -> SkillAccess? {
        guard let node = node(exerciseID: exerciseID) else { return nil }
        if node.isComplete { return .earned }
        if node.isAvailable { return .available }
        return previewUnlock ? .preview : .locked
    }

    public func suggestedChallengeIDs(profile: LocalProfile) -> [String] {
        guard let baseline = profile.baselineAbility else { return [] }
        return ExerciseFamily.allCases.compactMap { family in
            ExerciseCatalog.all.filter {
                $0.family == family && profile.goals.contains($0.attribute) && $0.level <= baseline.suggestedLevel
            }.max { $0.level < $1.level }?.id
        }
    }

    private struct Evidence {
        let id: UUID
        let date: Date
        let exerciseID: String
        let reps: Int
        let seconds: Double
        let source: InputSource
        let reason: StopReason

        func qualifies(for entry: ExerciseEntry) -> Bool {
            guard exerciseID == entry.id, source != .video, reason != .discomfort else { return false }
            if entry.unit == .seconds { return reps == 0 && seconds.isFinite && seconds >= Double(entry.goal) }
            return reps >= entry.goal && seconds == 0
        }
    }

    public static func evaluate(history: [SessionRecord], calendar: Calendar = .current) -> SkillProgress {
        var sessionIDs = Set<UUID>()
        var setIDs = Set<UUID>()
        let unique = history.filter { $0.date.timeIntervalSince1970.isFinite }
            .sorted { $0.date < $1.date }.filter { sessionIDs.insert($0.id).inserted }
        let evidence = unique.flatMap { session in
            let tracked = session.sets.map {
                Evidence(id: $0.id, date: session.date, exerciseID: $0.exercise.rawValue, reps: $0.reps,
                         seconds: 0, source: $0.source, reason: $0.reason)
            }
            let manual = session.loggedSets.map {
                Evidence(id: $0.id, date: session.date, exerciseID: $0.exerciseID, reps: $0.reps,
                         seconds: $0.seconds, source: $0.source, reason: $0.reason)
            }
            return (tracked + manual).filter { setIDs.insert($0.id).inserted }
        }
        let nodes = ExerciseCatalog.all.sorted { SkillGraph.tier(of: $0.id) < SkillGraph.tier(of: $1.id) }.reduce([SkillNodeProgress]()) { nodes, entry in
            let sets = evidence.filter { $0.qualifies(for: entry) }
            let days = Set(sets.map { calendar.startOfDay(for: $0.date) }).count
            let available = SkillGraph.prerequisites(for: entry.id).allSatisfy { id in
                nodes.contains { $0.exerciseID == id && $0.isComplete }
            }
            let node = SkillNodeProgress(exerciseID: entry.id, qualifyingSets: sets.count, trainingDays: days,
                                     manualSets: sets.filter { $0.source == .manual }.count,
                                     cameraSets: sets.filter { $0.source == .camera }.count, isAvailable: available,
                                     isComplete: available && sets.count >= 3 && days >= 2)
            return nodes + [node]
        }
        let points = ExerciseCatalog.all.reduce(into: [TrainingAttribute: Int]()) { result, entry in
            let sets = evidence.filter { $0.qualifies(for: entry) }
            let byDay = Dictionary(grouping: sets) { calendar.startOfDay(for: $0.date) }
            result[entry.attribute, default: 0] += byDay.values.reduce(0) { $0 + min(3, $1.count) * 10 }
        }
        return SkillProgress(nodes: nodes, attributePoints: points)
    }
}

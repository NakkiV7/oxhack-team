import Foundation

/// What the app can measure for a movement. Capability is shown separately from progress and never mixed into it.
public enum PathCapability: String, Codable, Sendable {
    /// The camera times a phase against a fixed contract and can verify the step (squats).
    case cameraAssessment
    /// The camera counts reps, but there is no contract that can verify the step (push-ups).
    case cameraCounting
    /// Self-reported practice only.
    case practiceLog

    public static func of(_ exerciseID: String) -> PathCapability {
        if TempoContract.contract(for: exerciseID) != nil { return .cameraAssessment }
        return ExerciseCatalog.find(exerciseID)?.tracking != nil ? .cameraCounting : .practiceLog
    }
    public var title: String {
        switch self {
        case .cameraAssessment: return "Camera assessment"
        case .cameraCounting: return "Camera rep counting"
        case .practiceLog: return "Practice log"
        }
    }
}

/// A personalised practice prescription for one step. It guides practice; the earned rule is unchanged (three goal sets
/// of the catalogue goal across two days).
public struct PracticeTarget: Codable, Equatable, Sendable {
    public let sets: Int
    public let target: Int
    public let perWeek: Int
    public init(sets: Int, target: Int, perWeek: Int) { self.sets = sets; self.target = target; self.perWeek = perWeek }

    /// Scaled from the catalogue goal by placement band and from the time and sessions the person has.
    public static func standard(for exerciseID: String, survey: PathSurvey) -> PracticeTarget? {
        guard let entry = ExerciseCatalog.find(exerciseID) else { return nil }
        let scale = survey.band == .advanced ? 1 : survey.band == .intermediate ? 0.8 : 0.6
        let floor = entry.unit == .seconds ? 10 : 3
        return .init(sets: survey.minutesPerSession <= 10 ? 2 : 3,
                     target: max(floor, Int((Double(entry.goal) * scale).rounded())),
                     perWeek: min(6, max(1, survey.sessionsPerWeek)))
    }
    /// The bounds a generated target must respect: 1 to 4 sets, at most one and a half times the catalogue goal, and no
    /// more sessions a week than the person planned.
    public func isValid(for exerciseID: String, survey: PathSurvey) -> Bool {
        guard let entry = ExerciseCatalog.find(exerciseID) else { return false }
        let maxTarget = Int((Double(entry.goal) * 1.5).rounded(.up))
        return (1...4).contains(sets) && (1...maxTarget).contains(target) && (1...min(6, max(1, survey.sessionsPerWeek))).contains(perWeek)
    }
}

/// One step of a path. A path has at most one node per catalogue exercise, so the node id is the exercise id.
public struct PathNode: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var why: String
    public var prerequisites: [String]
    /// A side branch: it never gates another node, and `supports` names the node it helps.
    public var optional: Bool
    public var supports: String?
    /// Before the person's starting point. Counts as passed for unlocking; never shown as earned or verified.
    public var notRequired: Bool
    public var practiceTarget: PracticeTarget?
    public init(id: String, why: String, prerequisites: [String] = [], optional: Bool = false, supports: String? = nil,
                notRequired: Bool = false, practiceTarget: PracticeTarget? = nil) {
        self.id = id; self.why = why; self.prerequisites = prerequisites; self.optional = optional; self.supports = supports
        self.notRequired = notRequired; self.practiceTarget = practiceTarget
    }
    public var entry: ExerciseEntry? { ExerciseCatalog.find(id) }
}

public enum PlacementSource: String, Codable, Sendable { case selfReported, cameraSupported }
public enum PathProvenance: String, Codable, Sendable { case gemini, catalogueFallback }

public struct PathRationale: Codable, Equatable, Sendable {
    public var text: String
    public var startReason: String
    public var emphasis: String
    public init(text: String, startReason: String, emphasis: String) { self.text = text; self.startReason = startReason; self.emphasis = emphasis }
}

/// A personalised path through the catalogue: Gemini's selection when it validates, otherwise the catalogue fallback.
public struct TrainingPath: Codable, Equatable, Sendable {
    public var goal: PathGoal
    public var catalogVersion: Int
    public var nodes: [PathNode]
    public var start: String
    public var goalNode: String
    /// The recommended order from the start to the goal along prerequisite links.
    public var route: [String]
    public var placementSource: PlacementSource
    public var provenance: PathProvenance
    public var rationale: PathRationale
    public init(goal: PathGoal, catalogVersion: Int = ExerciseCatalog.version, nodes: [PathNode], start: String, goalNode: String,
                route: [String], placementSource: PlacementSource, provenance: PathProvenance, rationale: PathRationale) {
        self.goal = goal; self.catalogVersion = catalogVersion; self.nodes = nodes; self.start = start; self.goalNode = goalNode
        self.route = route; self.placementSource = placementSource; self.provenance = provenance; self.rationale = rationale
    }
    public func node(_ id: String) -> PathNode? { nodes.first { $0.id == id } }
}

/// A recent camera check of the goal movement, used for placement only.
public struct PlacementCheck: Codable, Equatable, Sendable {
    public let exerciseID: String
    public let validReps: Int
    public init(exerciseID: String, validReps: Int) { self.exerciseID = exerciseID; self.validReps = validReps }
}

public struct PathPlacement: Equatable, Sendable {
    public let start: String
    /// Main-chain steps before the start.
    public let notRequired: [String]
    /// Starts a generated path may use: the rule's start or any earlier step of the main chain.
    public let allowedStarts: [String]
    public let reason: String
    public let source: PlacementSource
}

/// Path rules shared by the catalogue fallback and the validation of every generated path.
public enum TrainingPathRules {
    public static let minNodes = 4
    public static let maxNodes = 6
    public static let maxOptional = 1

    /// Catalogue support links into a movement from another family (for example, the plank supports push-ups).
    public static func supportLinks(of exerciseID: String) -> [String] {
        guard let entry = ExerciseCatalog.find(exerciseID) else { return [] }
        return SkillGraph.prerequisites(for: exerciseID).filter { ExerciseCatalog.find($0)?.family != entry.family }
    }

    /// Where the path starts. Beginners and "not sure" start at the foundation; people with experience start at the camera
    /// movement; a camera check with three valid reps of the goal movement also allows starting there.
    public static func placement(survey: PathSurvey, nodes: [PathNode], check: PlacementCheck? = nil) -> PathPlacement {
        let goal = survey.goal
        let chain = nodes.filter { !$0.optional && $0.entry?.family == goal.family }
            .sorted { ($0.entry?.level ?? 0) < ($1.entry?.level ?? 0) }.map(\.id)
        func at(_ index: Int, _ reason: String, _ source: PlacementSource) -> PathPlacement {
            let i = min(max(0, index), max(0, chain.count - 1))
            return .init(start: chain.isEmpty ? "" : chain[i], notRequired: Array(chain.prefix(i)), allowedStarts: Array(chain.prefix(i + 1)),
                         reason: reason, source: source)
        }
        let goalIndex = max(0, chain.firstIndex(of: goal.exerciseID) ?? 0)
        let name = ExerciseCatalog.find(goal.exerciseID)?.name.lowercased() ?? goal.exerciseID
        if let check, check.exerciseID == goal.exerciseID, check.validReps >= 3 {
            return at(goalIndex, "Your camera check recorded \(check.validReps) valid \(name), so the path starts there; earlier steps are not required for this starting point.", .cameraSupported)
        }
        switch survey.band {
        case .beginner: return at(0, "Starting at the foundation of the progression.", .selfReported)
        case .unsure: return at(0, "You weren't sure, so the path starts at the foundation; a camera check can move you on.", .selfReported)
        case .intermediate, .advanced:
            let lead = survey.band == .advanced ? "You can do a comfortable set" : "You have some experience"
            return at(goalIndex, "\(lead), so the path starts at \(name); earlier steps are not required for this starting point.", .selfReported)
        }
    }

    /// Every rule a generated path could break. Empty when the path is valid.
    public static func validate(_ path: TrainingPath, survey: PathSurvey) -> [String] {
        var errors: [String] = []
        let nodes = path.nodes, ids = Set(nodes.map(\.id))
        if ids.count != nodes.count { errors.append("duplicate node ids") }
        if !(minNodes...maxNodes).contains(nodes.count) { errors.append("expected \(minNodes) to \(maxNodes) nodes, got \(nodes.count)") }
        if nodes.filter(\.optional).count > maxOptional { errors.append("more than one optional branch") }
        for node in nodes {
            guard let entry = node.entry else { errors.append("unknown exercise \(node.id)"); continue }
            if let need = PathSurvey.requiredEquipment(for: entry), let equipment = survey.equipment, !equipment.contains(need) {
                errors.append("\(node.id): needs \(need), which is not available")
            }
            if survey.avoid.contains(node.id), node.id != survey.goal.exerciseID { errors.append("\(node.id): the person asked to leave this movement out") }
            if let target = node.practiceTarget, !target.isValid(for: node.id, survey: survey) { errors.append("\(node.id): practice target outside the allowed range") }
            if node.optional, nodes.contains(where: { $0.prerequisites.contains(node.id) }) { errors.append("\(node.id): an optional node cannot gate another node") }
            if let supported = node.supports {
                if !ids.contains(supported) { errors.append("\(node.id): supports \(supported), which is not in the path") }
                else if !SkillGraph.prerequisites(for: supported).contains(node.id) { errors.append("\(node.id): is not a catalogue support for \(supported)") }
            }
            for parent in node.prerequisites {
                guard ids.contains(parent), let parentEntry = ExerciseCatalog.find(parent) else { errors.append("\(node.id): prerequisite \(parent) is not in the path"); continue }
                let allowed = SkillGraph.prerequisites(for: node.id).contains(parent) || (parentEntry.family == entry.family && parentEntry.level < entry.level)
                if !allowed { errors.append("\(node.id): \(parent) is not an allowed progression link") }
            }
        }
        if hasCycle(nodes) { errors.append("prerequisite links form a cycle") }
        if let start = path.node(path.start) {
            if start.prerequisites.contains(where: { path.node($0)?.notRequired != true }) { errors.append("start node has unmet prerequisites inside the path") }
            if path.node(path.goalNode) == nil { errors.append("goal node missing") }
            else if !reachable(path).contains(path.goalNode) { errors.append("goal node not reachable from the start") }
        } else {
            errors.append("start node missing")
            if path.node(path.goalNode) == nil { errors.append("goal node missing") }
        }
        if !isValidRoute(path) { errors.append("recommended route is not a path from the start to the goal") }
        return errors
    }

    /// The route starts at the start, ends at the goal, visits each node once, and each step lists the previous one.
    public static func isValidRoute(_ path: TrainingPath) -> Bool {
        let route = path.route
        guard route.first == path.start, route.last == path.goalNode, Set(route).count == route.count else { return false }
        return route.enumerated().allSatisfy { index, id in
            guard let node = path.node(id) else { return false }
            return index == 0 || node.prerequisites.contains(route[index - 1])
        }
    }

    /// From the start, follow the lowest-level non-optional dependent until the goal.
    public static func defaultRoute(_ path: TrainingPath) -> [String] {
        var route = [path.start]
        for _ in 0..<12 where route.last != path.goalNode {
            guard let current = route.last, let next = path.nodes.filter({ !$0.optional && $0.prerequisites.contains(current) })
                .min(by: { ($0.entry?.level ?? 0) < ($1.entry?.level ?? 0) }) else { break }
            route.append(next.id)
        }
        return route.last == path.goalNode ? route : [path.start]
    }

    /// The deterministic path used when Gemini is unavailable or its plan fails validation twice. It honours the same answers.
    public static func fallback(survey: PathSurvey, check: PlacementCheck? = nil) -> TrainingPath {
        let chain = survey.goal.chain.filter(survey.canUse)
        var nodes = chain.enumerated().map { index, id in
            PathNode(id: id, why: index == 0 ? "The first step of this progression with the space and equipment you have."
                     : "Builds on \(ExerciseCatalog.find(chain[index - 1])?.name.lowercased() ?? chain[index - 1]).",
                     prerequisites: index == 0 ? [] : [chain[index - 1]])
        }
        // Catalogue supports: the first usable one becomes the optional branch; more join as prerequisites only while the
        // path is shorter than the minimum.
        var supports = chain.flatMap { id in supportLinks(of: id).map { (support: $0, of: id) } }.filter { survey.canUse($0.support) && !chain.contains($0.support) }
        let branch = supports.isEmpty ? nil : supports.removeFirst()
        for (support, of) in supports where nodes.count + (branch == nil ? 0 : 1) < minNodes {
            nodes.append(PathNode(id: support, why: "Supports \(ExerciseCatalog.find(of)?.name.lowercased() ?? of)."))
            if let index = nodes.firstIndex(where: { $0.id == of }) { nodes[index].prerequisites.append(support) }
        }
        if let branch {
            nodes.append(PathNode(id: branch.support, why: "Optional: \(ExerciseCatalog.find(branch.support)?.name.lowercased() ?? branch.support) supports \(ExerciseCatalog.find(branch.of)?.name.lowercased() ?? branch.of).",
                                  optional: true, supports: branch.of))
        }
        for index in nodes.indices { nodes[index].practiceTarget = PracticeTarget.standard(for: nodes[index].id, survey: survey) }
        let placement = self.placement(survey: survey, nodes: nodes, check: check)
        for index in nodes.indices { nodes[index].notRequired = placement.notRequired.contains(nodes[index].id) }
        var path = TrainingPath(goal: survey.goal, nodes: nodes, start: placement.start, goalNode: chain.last ?? survey.goal.exerciseID, route: [],
                                placementSource: placement.source, provenance: .catalogueFallback,
                                rationale: .init(text: placement.reason, startReason: placement.reason, emphasis: defaultEmphasis(survey.focus)))
        path.route = defaultRoute(path)
        return path
    }

    public static func defaultEmphasis(_ focus: PathFocus?) -> String {
        switch focus {
        case .learn: return "Learn the movement pattern before adding volume."
        case .consistency: return "Turn up on your planned days; steady practice beats big sessions."
        case .improve: return "Refine control on the movement you already have."
        case .unsure, nil: return "Build the movement step by step at a pace you can repeat."
        }
    }

    private static func hasCycle(_ nodes: [PathNode]) -> Bool {
        var done = Set<String>(), active = Set<String>()
        func visit(_ id: String) -> Bool {
            if active.contains(id) { return true }
            if done.contains(id) { return false }
            active.insert(id)
            let cyclic = (nodes.first { $0.id == id }?.prerequisites ?? []).contains(where: visit)
            active.remove(id); done.insert(id)
            return cyclic
        }
        return nodes.contains { visit($0.id) }
    }

    /// Nodes reachable by progressing from the start; nodes without prerequisites are open from the outset.
    private static func reachable(_ path: TrainingPath) -> Set<String> {
        var reach = Set([path.start] + path.nodes.filter { $0.prerequisites.isEmpty }.map(\.id))
        var grew = true
        while grew {
            grew = false
            for node in path.nodes where !reach.contains(node.id) && !node.prerequisites.isEmpty
                && node.prerequisites.allSatisfy({ reach.contains($0) || path.node($0)?.notRequired == true }) {
                reach.insert(node.id); grew = true
            }
        }
        return reach
    }
}

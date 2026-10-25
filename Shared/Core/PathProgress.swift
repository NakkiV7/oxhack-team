import Foundation

/// Where a step stands in the person's path.
public enum PathStepState: String, Codable, Sendable {
    /// Three goal sets across two training days, with the path's prerequisites passed. The existing earned rule.
    case earned
    /// Before the person's starting point: passed for unlocking, never shown as earned.
    case notRequired
    /// The next step on the route.
    case current
    case available
    case locked
}

public struct PathStepStatus: Equatable, Sendable {
    public let state: PathStepState
    /// Camera verification is a separate mark on top of the earned rule. It never unlocks a step by itself.
    public let verification: StepVerification
    public let qualifyingSets: Int
    public let trainingDays: Int
    public let manualSets: Int
    public let cameraSets: Int
    /// Passed for unlocking the steps that build on it.
    public var isPassed: Bool { state == .earned || state == .notRequired }
    public var title: String {
        switch state {
        case .earned: return verification == .none ? "Earned" : "Earned · AI-verified"
        case .notRequired: return "Not required for your start"
        case .current: return "Current step"
        case .available: return "Available"
        case .locked: return "Locked"
        }
    }
}

public struct PathStatus: Equatable, Sendable {
    public let steps: [String: PathStepStatus]
    /// The first open step along the route, or nil when the path is complete.
    public let current: String?
    public func step(_ id: String) -> PathStepStatus? { steps[id] }

    /// Progress comes from the person's history through `SkillProgress`, so a new path version never loses or invents it.
    /// Availability follows the path's own links, which can start later than the full catalogue tree.
    public static func evaluate(path: TrainingPath, skill: SkillProgress, attempts: [CoachAttemptRecord] = [], calendar: Calendar = .current) -> PathStatus {
        var memo: [String: (passed: Bool, earned: Bool, available: Bool)] = [:]
        func resolve(_ id: String, _ depth: Int = 0) -> (passed: Bool, earned: Bool, available: Bool) {
            if let known = memo[id] { return known }
            guard depth < 12, let node = path.node(id) else { return (false, false, false) }
            let evidence = skill.node(exerciseID: id)
            let meetsRule = (evidence?.qualifyingSets ?? 0) >= 3 && (evidence?.trainingDays ?? 0) >= 2
            let available = node.prerequisites.allSatisfy { resolve($0, depth + 1).passed }
            let earned = available && meetsRule
            let result = (earned || node.notRequired, earned, available)
            memo[id] = result
            return result
        }
        let open = { (id: String) -> Bool in let r = resolve(id); return r.available && !r.earned && path.node(id)?.notRequired == false }
        let current = path.route.first(where: open) ?? path.nodes.first { !$0.optional && open($0.id) }?.id
        var steps: [String: PathStepStatus] = [:]
        for node in path.nodes {
            let r = resolve(node.id), evidence = skill.node(exerciseID: node.id)
            let state: PathStepState = r.earned ? .earned : node.notRequired ? .notRequired : node.id == current ? .current : r.available ? .available : .locked
            steps[node.id] = .init(state: state, verification: NodeVerification.evaluate(attempts: attempts, exerciseID: node.id, calendar: calendar).verification,
                                   qualifyingSets: evidence?.qualifyingSets ?? 0, trainingDays: evidence?.trainingDays ?? 0,
                                   manualSets: evidence?.manualSets ?? 0, cameraSets: evidence?.cameraSets ?? 0)
        }
        return .init(steps: steps, current: current)
    }
}

/// What a new path version changes, shown before it is saved. Progress lives in the history, so nothing is lost: steps that
/// leave the path keep their sets and stay in the person's record.
public struct PathDiff: Equatable, Sendable {
    public let added: [String]
    public let removed: [String]
    public let kept: [String]
    public let startFrom: String?
    public let startTo: String
    public let goalFrom: String?
    public let goalTo: String
    /// Kept steps with recorded progress.
    public let carried: [String]
    /// Steps leaving the path that have recorded progress; it stays in the history and the level.
    public let keptInHistory: [String]
    public var changesStart: Bool { startFrom != nil && startFrom != startTo }
    public var changesGoal: Bool { goalFrom != nil && goalFrom != goalTo }

    public static func between(_ old: TrainingPath?, _ new: TrainingPath, skill: SkillProgress, attempts: [CoachAttemptRecord] = [],
                               calendar: Calendar = .current) -> PathDiff {
        let before = old?.nodes.map(\.id) ?? [], after = new.nodes.map(\.id)
        let hasProgress = { (id: String) -> Bool in
            (skill.node(exerciseID: id)?.qualifyingSets ?? 0) > 0
                || NodeVerification.evaluate(attempts: attempts, exerciseID: id, calendar: calendar).verification != .none
        }
        let removed = before.filter { !after.contains($0) }, kept = after.filter(before.contains)
        return .init(added: after.filter { !before.contains($0) }, removed: removed, kept: kept,
                     startFrom: old?.start, startTo: new.start, goalFrom: old?.goalNode, goalTo: new.goalNode,
                     carried: kept.filter(hasProgress), keptInHistory: removed.filter(hasProgress))
    }
}

/// Saved path versions. A new version never replaces the history; the newest is active.
public struct PathHistory: Codable, Equatable, Sendable {
    public struct Version: Codable, Equatable, Identifiable, Sendable {
        public let id: Int
        public let createdAt: Date
        public let path: TrainingPath
        public let survey: PathSurvey
    }
    public enum Invalid: Error, Equatable { case path([String]) }
    public private(set) var versions: [Version] = []
    public init() {}
    public var active: Version? { versions.last }

    /// Validates again before saving: nothing unvalidated becomes a person's path.
    @discardableResult public mutating func save(_ path: TrainingPath, survey: PathSurvey, at date: Date) throws -> Version {
        let errors = TrainingPathRules.validate(path, survey: survey)
        guard errors.isEmpty else { throw Invalid.path(errors) }
        let version = Version(id: (versions.last?.id ?? 0) + 1, createdAt: date, path: path, survey: survey)
        versions.append(version)
        return version
    }
}

/// The path level is a game score from XP, never a fitness rating. Level L starts at 50·L·(L−1) XP.
public struct PathLevel: Equatable, Sendable {
    public static let firstVerificationXP = 50
    public static let consistentVerificationXP = 100
    public let level: Int
    public let xp: Int
    public let floor: Int
    public let next: Int
    public init(xp: Int) {
        let xp = max(0, xp)
        var level = 1
        while xp >= 50 * level * (level + 1) { level += 1 }
        self.level = level; self.xp = xp; self.floor = 50 * level * (level - 1); self.next = 50 * level * (level + 1)
    }
    public var fraction: Double { Double(xp - floor) / Double(next - floor) }

    /// The existing attribute XP from earned-rule sets, plus a bonus for each camera-verified step.
    public static func xp(skill: SkillProgress, verifications: [StepVerification]) -> Int {
        TrainingAttribute.allCases.reduce(0) { $0 + skill.points(for: $1) } + verifications.reduce(0) {
            switch $1 {
            case .none: return $0
            case .firstCompletion: return $0 + firstVerificationXP
            case .consistent: return $0 + firstVerificationXP + consistentVerificationXP
            }
        }
    }
}

/// A transparent attribute measured from saved records only. `value` stays nil ("not assessed yet") until there is enough
/// evidence; there is no flattering default.
public struct MeasuredAttribute: Equatable, Sendable {
    public enum Key: String, Sendable { case tempo, consistency, practice }
    public let key: Key
    public let value: Int?
    public let evidence: Int
    public let detail: String
    public let method: String
    public let scope: String
    public var title: String { key.rawValue.capitalized }
}

public enum MeasuredAttributes {
    public static func evaluate(attempts: [CoachAttemptRecord], history: [SessionRecord], plannedSessions: Int?, now: Date,
                                calendar: Calendar = .current) -> [MeasuredAttribute] {
        // Timed reps from camera assessments in the last 30 days, each judged against its own movement's contract.
        let timed: [(value: Double, contract: TempoContract)] = attempts.flatMap { attempt -> [(value: Double, contract: TempoContract)] in
            guard let contract = TempoContract.contract(for: attempt.exerciseID), contract.version == attempt.contractVersion,
                  attempt.startedAt <= now, attempt.startedAt >= now.addingTimeInterval(-30 * 86_400) else { return [] }
            return (attempt.baselineReps + attempt.retryReps).filter(\.valid).compactMap { rep in contract.value(of: rep).map { ($0, contract) } }
        }
        let movements = timed.reduce(into: [TempoContract]()) { if !$0.contains($1.contract) { $0.append($1.contract) } }
        let single = movements.count == 1 ? movements[0] : nil
        let noun = single.map { "timed \($0.movement)" } ?? "timed reps"
        let inRange = timed.filter { abs($0.value - $0.contract.target) <= $0.contract.tolerance }.count
        let tempo = MeasuredAttribute(
            key: .tempo, value: timed.count >= 3 ? percent(inRange, of: timed.count) : nil, evidence: timed.count,
            detail: timed.count < 3 ? "Needs 3 timed reps from a camera assessment (\(timed.count) so far)"
                : single.map { "\(inRange) of \(timed.count) \(noun) were within \(plain($0.tolerance)) s of the \(plain($0.target)) s \($0.label) target" }
                ?? "\(inRange) of \(timed.count) timed reps were within the tolerance of their movement's target",
            method: "Share of reps timed in camera assessments over the last 30 days that landed within their movement's target tolerance (squats: lowering time; push-ups: rep time). Baseline and retry reps both count; uncounted reps do not.",
            scope: "last 30 days")
        // Repeatability: each rep against the median of its own movement, so squat and push-up timings never mix.
        let medians = Dictionary(uniqueKeysWithValues: movements.map { contract in
            (contract.exerciseID, AttemptComparison.median(timed.filter { $0.contract == contract }.map(\.value)) ?? 0) })
        let steady = timed.filter { let middle = medians[$0.contract.exerciseID] ?? 0; return middle > 0 && abs($0.value - middle) <= 0.1 * middle }.count
        let consistency = MeasuredAttribute(
            key: .consistency, value: timed.count >= 5 ? percent(steady, of: timed.count) : nil, evidence: timed.count,
            detail: timed.count < 5 ? "Needs 5 timed reps (\(timed.count) so far)"
                : single.map { "\(steady) of \(timed.count) \(noun) were within 10% of your own median \($0.label) (\(plain(medians[$0.exerciseID] ?? 0)) s)" }
                ?? "\(steady) of \(timed.count) timed reps were within 10% of your own median for that movement",
            method: "Share of timed reps over the last 30 days within 10% of your own median for the same movement. It measures repeatability, not speed.",
            scope: "last 30 days")
        let week = calendar.dateInterval(of: .weekOfYear, for: now)
        let trainedDates = history.filter { session in session.sets.contains { $0.source != .video } || session.loggedSets.contains { $0.source != .video } }.map(\.date)
            + attempts.filter { $0.status == .result }.map { $0.completedAt ?? $0.startedAt }
        let days = Set(trainedDates.filter { week?.contains($0) == true }.map { calendar.startOfDay(for: $0) }).count
        let planned = plannedSessions.flatMap { $0 > 0 ? $0 : nil }
        let practice = MeasuredAttribute(
            key: .practice, value: planned.map { min(100, percent(days, of: $0)) }, evidence: days,
            detail: planned.map { "\(days) of \($0) planned sessions this week" } ?? "Set sessions per week in your path to track this",
            method: "Days this calendar week with a recorded or logged workout, or a completed camera assessment, against the sessions per week you chose. Logged practice is self-reported.",
            scope: "this week")
        return [tempo, consistency, practice]
    }

    private static func percent(_ part: Int, of whole: Int) -> Int { Int((100 * Double(part) / Double(whole)).rounded()) }
    private static func plain(_ value: Double) -> String { String(format: "%g", (value * 100).rounded() / 100) }
}

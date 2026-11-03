import Foundation

// Requests and validated responses for the gateway's path and camera coaching tasks. Gemini only selects and words; every
// id, link and number in a request comes from the app's own rules, and every response is validated again here.

/// The exercise a contract measures, in the form the gateway accepts.
public struct ContractPayload: Encodable, Equatable, Sendable {
    public let exerciseID: String
    public let version: String
    public let metric: String
    public let label: String
    public let target: Double
    public let tolerance: Double
    public init(_ contract: TempoContract) {
        exerciseID = contract.exerciseID; version = contract.version; metric = contract.metric.rawValue
        label = contract.label; target = contract.target; tolerance = contract.tolerance
    }
}

// MARK: - Client routes

public extension CoachGatewayClient {
    /// One Gemini plan for the person's training path. The caller validates it with `PathProposalContracts`.
    func pathProposal(_ input: PathProposalRequest) async throws -> Data {
        try await post(try Self.bounded(JSONEncoder().encode(input)), path: "path-proposal")
    }
    /// One coaching cue between a baseline and a retry; validated against the request before it is returned.
    func attemptCue(_ input: AttemptCueRequest) async throws -> AttemptCue {
        try AttemptCueContracts.cue(from: await post(try Self.bounded(JSONEncoder().encode(input)), path: "attempt-cue"), request: input)
    }
    /// Gemini's wording for a result the app already computed.
    func attemptExplanation(_ input: AttemptExplanationRequest) async throws -> String {
        try AttemptCueContracts.explanation(from: await post(try Self.bounded(JSONEncoder().encode(input)), path: "attempt-explanation"), request: input)
    }
    private static func bounded(_ body: Data) throws -> Data {
        guard body.count <= 65_536 else { throw CoachGatewayError.requestTooLarge }
        return body
    }
}

// MARK: - Path proposal

public struct PathProposalRequest: Encodable, Sendable {
    public struct Answers: Encodable, Equatable, Sendable {
        public let band: String
        public let focus: String?
        public let coachingStyle: String?
        public let minutesPerSession: Int
        public let sessionsPerWeek: Int
        private enum CodingKeys: String, CodingKey { case band, focus, coachingStyle, minutesPerSession, sessionsPerWeek }
        public func encode(to encoder: Encoder) throws {   // the gateway expects explicit nulls
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(band, forKey: .band); try values.encode(focus, forKey: .focus); try values.encode(coachingStyle, forKey: .coachingStyle)
            try values.encode(minutesPerSession, forKey: .minutesPerSession); try values.encode(sessionsPerWeek, forKey: .sessionsPerWeek)
        }
    }
    public struct Exercise: Encodable, Equatable, Sendable {
        public let id: String
        public let capability: String
        public let allowedPrerequisites: [String]
        public let maxTarget: Int
    }
    public let generationID: String
    public let goal: String
    public let answers: Answers
    public let exercises: [Exercise]
    public let allowedStarts: [String]
    public let ruleStart: String
    public let repair: [String]

    /// Built from the person's answers and the app's rules: only usable exercises, only catalogue links, the targets'
    /// upper bounds, and the starts the answers allow. `repair` carries the errors of a previous plan when the person asks
    /// Gemini to fix it.
    public init(survey: PathSurvey, check: PlacementCheck? = nil, repair: [String] = [], generationID: String = UUID().uuidString) {
        let usable = ExerciseCatalog.all.filter { survey.canUse($0.id) }
        let usableIDs = Set(usable.map(\.id))
        let placement = TrainingPathRules.placement(survey: survey, nodes: TrainingPathRules.fallback(survey: survey, check: check).nodes, check: check)
        self.generationID = generationID
        goal = survey.goal.exerciseID
        answers = .init(band: survey.band.rawValue, focus: survey.focus?.rawValue, coachingStyle: survey.coachingStyle?.rawValue,
                        minutesPerSession: min(120, max(5, survey.minutesPerSession)), sessionsPerWeek: min(7, max(1, survey.sessionsPerWeek)))
        exercises = usable.map { entry in
            .init(id: entry.id, capability: PathCapability.of(entry.id).rawValue,
                  allowedPrerequisites: SkillGraph.prerequisites(for: entry.id).filter(usableIDs.contains),
                  maxTarget: Int((Double(entry.goal) * 1.5).rounded(.up)))
        }
        allowedStarts = placement.allowedStarts
        ruleStart = placement.start
        self.repair = Array(repair.prefix(12)).map { String($0.prefix(200)) }
    }
}

private struct PathProposalResponse: Decodable {
    struct Node: Decodable {
        let id: String
        let why: String
        let prerequisites: [String]
        let optional: Bool
        let supports: String?
        let practiceTarget: PracticeTarget
    }
    let generationID: String
    let nodes: [Node]
    let start: String
    let goalNode: String
    let route: [String]
    let rationale: String
    let startReason: String
    let emphasis: String
}

public enum PathProposalError: Error, Equatable {
    case malformed
    case staleGeneration
    /// The plan broke the app's rules; these are the reasons, ready for a person-initiated repair request.
    case invalid([String])
}

public enum PathProposalContracts {
    /// Turns Gemini's plan into a path the app trusts: the start is bounded by placement, steps before it become "not
    /// required", a broken route is replaced by the default one, and the whole path must pass `TrainingPathRules.validate`.
    public static func path(from data: Data, request: PathProposalRequest, survey: PathSurvey, check: PlacementCheck? = nil) throws -> TrainingPath {
        guard !data.isEmpty, data.count <= 65_536, let response = try? JSONDecoder().decode(PathProposalResponse.self, from: data) else { throw PathProposalError.malformed }
        guard response.generationID == request.generationID else { throw PathProposalError.staleGeneration }
        var nodes = response.nodes.map {
            PathNode(id: $0.id, why: String($0.why.prefix(240)), prerequisites: $0.prerequisites, optional: $0.optional,
                     supports: $0.optional ? $0.supports : nil, practiceTarget: $0.practiceTarget)
        }
        let placement = TrainingPathRules.placement(survey: survey, nodes: nodes, check: check)
        let start = placement.allowedStarts.contains(response.start) ? response.start : placement.start
        let before = placement.allowedStarts.prefix { $0 != start }
        for index in nodes.indices { nodes[index].notRequired = before.contains(nodes[index].id) }
        var path = TrainingPath(goal: survey.goal, nodes: nodes, start: start, goalNode: response.goalNode, route: response.route,
                                placementSource: start == placement.start ? placement.source : .selfReported, provenance: .gemini,
                                rationale: .init(text: response.rationale, startReason: response.startReason, emphasis: response.emphasis))
        if !TrainingPathRules.isValidRoute(path) { path.route = TrainingPathRules.defaultRoute(path) }
        let errors = TrainingPathRules.validate(path, survey: survey)
        guard errors.isEmpty else { throw PathProposalError.invalid(errors) }
        return path
    }
}

public enum PathGenerator {
    public struct Outcome: Sendable {
        public let path: TrainingPath
        /// Why Gemini's plan was not used, when the catalogue path was returned instead. Empty when Gemini's plan was used.
        public let problems: [String]
        /// Validation errors a person can send back once with "Ask Gemini to fix it". Empty for provider failures.
        public let repairable: [String]
    }

    /// One Gemini call, never an automatic paid retry. Any failure returns the catalogue path for the same answers, labelled
    /// as such, with the reasons.
    public static func generate(survey: PathSurvey, check: PlacementCheck? = nil, repair: [String] = [],
                                propose: @Sendable (PathProposalRequest) async throws -> Data) async -> Outcome {
        let request = PathProposalRequest(survey: survey, check: check, repair: repair)
        let fallback = TrainingPathRules.fallback(survey: survey, check: check)
        do {
            return .init(path: try PathProposalContracts.path(from: await propose(request), request: request, survey: survey, check: check),
                         problems: [], repairable: [])
        } catch PathProposalError.invalid(let errors) {
            return .init(path: fallback, problems: errors, repairable: errors)
        } catch {
            return .init(path: fallback, problems: [(error as? LocalizedError)?.errorDescription ?? "Gemini's plan was unavailable."], repairable: [])
        }
    }
}

// MARK: - Coaching cue and explanation

public struct AttemptCueRequest: Encodable, Sendable {
    public struct Baseline: Encodable, Equatable, Sendable { public let validReps: Int; public let median: Double }
    public let generationID: String
    public let contract: ContractPayload
    public let baseline: Baseline
    public let coachingStyle: String?
    public let facts: [CoachFact]
    private enum CodingKeys: String, CodingKey { case generationID, contract, baseline, coachingStyle, facts }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(generationID, forKey: .generationID); try values.encode(contract, forKey: .contract)
        try values.encode(baseline, forKey: .baseline); try values.encode(coachingStyle, forKey: .coachingStyle); try values.encode(facts, forKey: .facts)
    }

    /// The cue request for the loop's open baseline, or nil when the loop is not waiting for one. The generation id is the
    /// loop's request id, so a late answer cannot land on another attempt.
    public init?(loop: CoachAttemptLoop, coachingStyle: CoachingStyle? = nil) {
        let values = loop.baseline.filter(\.valid).compactMap(loop.contract.value(of:))
        guard loop.state == .preparingCue, let requestID = loop.requestID, values.count >= TempoContract.minimumValidReps,
              let middle = AttemptComparison.rounded(AttemptComparison.median(values)) else { return nil }
        let c = loop.contract
        generationID = requestID.uuidString
        contract = ContractPayload(c)
        baseline = .init(validReps: values.count, median: middle)
        self.coachingStyle = coachingStyle?.rawValue
        facts = [
            CoachFact(id: "baseline", text: "Baseline median \(c.label) \(Self.number(middle)) s over \(values.count) counted \(c.movement)."),
            CoachFact(id: "baseline-reps", text: "Baseline \(c.label) per rep: \(values.map { "\(Self.number($0)) s" }.joined(separator: ", "))."),
            CoachFact(id: "target", text: "Target \(c.label) \(Self.number(c.target)) s, within \(Self.number(c.tolerance)) s.")
        ]
    }
    static func number(_ value: Double) -> String { String(format: "%g", (value * 100).rounded() / 100) }
}

public struct AttemptExplanationRequest: Encodable, Sendable {
    public struct Outcome: Encodable, Equatable, Sendable { public let classification: String; public let retryMeets: Bool }
    public let generationID: String
    public let contract: ContractPayload
    public let outcome: Outcome
    public let coachingStyle: String?
    public let facts: [CoachFact]
    private enum CodingKeys: String, CodingKey { case generationID, contract, outcome, coachingStyle, facts }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(generationID, forKey: .generationID); try values.encode(contract, forKey: .contract)
        try values.encode(outcome, forKey: .outcome); try values.encode(coachingStyle, forKey: .coachingStyle); try values.encode(facts, forKey: .facts)
    }

    /// Facts for a finished attempt's computed result, or nil when the attempt has no result.
    public init?(record: CoachAttemptRecord, coachingStyle: CoachingStyle? = nil) {
        guard record.status == .result, let o = record.outcome, let c = TempoContract.contract(for: record.exerciseID), c.version == record.contractVersion else { return nil }
        let n = AttemptCueRequest.number
        generationID = record.id.uuidString
        contract = ContractPayload(c)
        outcome = .init(classification: o.classification.rawValue, retryMeets: o.retryMeets)
        self.coachingStyle = coachingStyle?.rawValue
        var facts = [CoachFact(id: "result", text: "Result: \(o.title.lowercased()).")]
        facts.append(CoachFact(id: "target", text: "Target \(c.label) \(n(c.target)) s, within \(n(c.tolerance)) s."))
        if let b = o.baselineMedian { facts.append(CoachFact(id: "baseline", text: "Baseline median \(c.label) \(n(b)) s over \(o.baselineCount) counted \(c.movement).")) }
        if let r = o.retryMedian { facts.append(CoachFact(id: "retry", text: "Retry median \(c.label) \(n(r)) s over \(o.retryCount) counted \(c.movement)\(o.retryMeets ? ", within the target tolerance" : ", outside the target tolerance").")) }
        if let noise = o.noiseTolerance { facts.append(CoachFact(id: "rule", text: "Changes within \(n(noise)) s count as about the same.")) }
        if let reason = o.reason { facts.append(CoachFact(id: "reason", text: "Not assessable because \(reason).")) }
        self.facts = facts
    }
}

public enum AttemptCueContracts {
    private struct GroundedReply: Decodable { let generationID: String; let text: String; let factIDs: [String]; let action: String? }

    /// Gemini's cue, accepted only if it answers this request, uses an allowed action consistent with the baseline, cites
    /// supplied facts and states no number the facts do not contain. Callers fall back to the deterministic cue otherwise.
    public static func cue(from data: Data, request: AttemptCueRequest) throws -> AttemptCue {
        let reply = try grounded(data, generationID: request.generationID, facts: request.facts, maxLength: 200)
        let meets = abs(request.baseline.median - request.contract.target) <= request.contract.tolerance
        guard let raw = reply.action, let action = AttemptCue.Action(rawValue: raw), action != .noAssessment,
              action != .maintainTarget || meets, action != .cueTarget || !meets else { throw CoachContractError.invalidProposal }
        return AttemptCue(action: action, text: reply.text, provenance: .gemini)
    }

    /// Gemini's explanation of the computed result, under the same grounding rules. It never changes the result.
    public static func explanation(from data: Data, request: AttemptExplanationRequest) throws -> String {
        try grounded(data, generationID: request.generationID, facts: request.facts, maxLength: 500).text
    }

    private static func grounded(_ data: Data, generationID: String, facts: [CoachFact], maxLength: Int) throws -> GroundedReply {
        guard !data.isEmpty, data.count <= 65_536, let reply = try? JSONDecoder().decode(GroundedReply.self, from: data) else { throw CoachContractError.malformed }
        guard reply.generationID == generationID else { throw CoachContractError.staleGeneration }
        let text = reply.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...maxLength).contains(text.count), !text.lowercased().contains("http"), !text.lowercased().contains("www.") else { throw CoachContractError.malformed }
        guard (1...8).contains(reply.factIDs.count), Set(reply.factIDs).count == reply.factIDs.count,
              Set(reply.factIDs).isSubset(of: Set(facts.map(\.id))) else { throw CoachContractError.invalidEvidence }
        let allowed = Set(facts.flatMap { numbers(in: $0.text) })
        guard numbers(in: text).allSatisfy({ allowed.contains($0) || ($0 == $0.rounded() && (1...5).contains($0)) }) else { throw CoachContractError.invalidEvidence }
        return GroundedReply(generationID: reply.generationID, text: text, factIDs: reply.factIDs, action: reply.action)
    }

    /// Every number written in digits, for example "1.34" or "3".
    static func numbers(in text: String) -> [Double] {
        var found: [Double] = [], current = ""
        for character in text + " " {
            if character.isASCII, character.isNumber || (character == "." && !current.isEmpty && !current.contains(".")) { current.append(character); continue }
            if current.hasSuffix(".") { current.removeLast() }
            if let value = Double(current) { found.append(value) }
            current = ""
        }
        return found
    }
}

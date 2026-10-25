import Foundation

public struct CoachPlanLimits: Sendable {
    public let maxExercises: Int
    public let maxSetsPerExercise: Int
    public let maxReps: Int
    public let maxHoldSeconds: Int
    public let maxRestSeconds: Int
    public let maxTotalSets: Int

    public init(maxExercises: Int = 12, maxSetsPerExercise: Int = 5, maxReps: Int = 30,
                maxHoldSeconds: Int = 120, maxRestSeconds: Int = 600, maxTotalSets: Int = 24) {
        self.maxExercises = maxExercises
        self.maxSetsPerExercise = maxSetsPerExercise
        self.maxReps = maxReps
        self.maxHoldSeconds = maxHoldSeconds
        self.maxRestSeconds = maxRestSeconds
        self.maxTotalSets = maxTotalSets
    }
}

public struct CoachValidationContext: Sendable {
    public let generationID: String
    public let suppliedFactIDs: Set<String>
    public let availableSupport: Set<String>
    public let planLimits: CoachPlanLimits

    public init(generationID: String, suppliedFactIDs: Set<String>, availableSupport: Set<String>, planLimits: CoachPlanLimits = .init()) {
        self.generationID = generationID
        self.suppliedFactIDs = suppliedFactIDs
        self.availableSupport = availableSupport
        self.planLimits = planLimits
    }
}

public enum CoachContractError: Error, Equatable {
    case malformed, staleGeneration, invalidEvidence, invalidProposal, selectionRequired
}

public struct GroundedCoachText: Decodable, Sendable {
    public let text: String
    public let factIDs: [String]

    public init(from decoder: Decoder) throws {
        let values = try decoder.strictKeys(["text", "factIDs"])
        text = try values.decode(String.self, forKey: .init("text"))
        factIDs = try values.decode([String].self, forKey: .init("factIDs"))
    }
}

public struct ProposedExercise: Decodable, Sendable {
    public let exerciseID: String
    public let sets: Int
    public let target: Int
    public let unit: ExerciseEntry.Unit
    public let restSeconds: Int
    public let factIDs: [String]

    public init(from decoder: Decoder) throws {
        let values = try decoder.strictKeys(["exerciseID", "sets", "target", "unit", "restSeconds", "factIDs"])
        exerciseID = try values.decode(String.self, forKey: .init("exerciseID"))
        sets = try values.decode(Int.self, forKey: .init("sets"))
        target = try values.decode(Int.self, forKey: .init("target"))
        unit = try values.decode(ExerciseEntry.Unit.self, forKey: .init("unit"))
        restSeconds = try values.decode(Int.self, forKey: .init("restSeconds"))
        factIDs = try values.decode([String].self, forKey: .init("factIDs"))
    }
}

public struct WorkoutProposal: Decodable, Sendable {
    public let generationID: String
    public let items: [ProposedExercise]
    public let rationale: GroundedCoachText

    public init(from decoder: Decoder) throws {
        let values = try decoder.strictKeys(["generationID", "items", "rationale"])
        generationID = try values.decode(String.self, forKey: .init("generationID"))
        items = try values.decode([ProposedExercise].self, forKey: .init("items"))
        rationale = try values.decode(GroundedCoachText.self, forKey: .init("rationale"))
    }
}

public enum CoachSummaryKind: String, Decodable, Sendable { case session, weekly }

public struct CoachSummary: Decodable, Sendable {
    public let generationID: String
    public let kind: CoachSummaryKind
    public let headline: GroundedCoachText
    public let insights: [GroundedCoachText]
    public let focus: GroundedCoachText

    public init(from decoder: Decoder) throws {
        let values = try decoder.strictKeys(["generationID", "kind", "headline", "insights", "focus"])
        generationID = try values.decode(String.self, forKey: .init("generationID"))
        kind = try values.decode(CoachSummaryKind.self, forKey: .init("kind"))
        headline = try values.decode(GroundedCoachText.self, forKey: .init("headline"))
        insights = try values.decode([GroundedCoachText].self, forKey: .init("insights"))
        focus = try values.decode(GroundedCoachText.self, forKey: .init("focus"))
    }
}

public enum CoachContracts {
    public static func parseSummary(_ data: Data, context: CoachValidationContext, kind: CoachSummaryKind) throws -> CoachSummary {
        let summary = try decode(CoachSummary.self, data: data)
        guard !context.generationID.isEmpty, summary.generationID == context.generationID else { throw CoachContractError.staleGeneration }
        guard summary.kind == kind, summary.insights.count <= 3 else { throw CoachContractError.malformed }
        for text in [summary.headline] + summary.insights + [summary.focus] {
            try validate(text, context: context)
        }
        return summary
    }

    public static func parseProposal(_ data: Data, context: CoachValidationContext) throws -> WorkoutProposal {
        let proposal = try decode(WorkoutProposal.self, data: data)
        try validate(proposal, context: context)
        return proposal
    }

    public static func approvedItems(from proposal: WorkoutProposal, selectedExerciseIDs: Set<String>, context: CoachValidationContext) throws -> [ProposedExercise] {
        try validate(proposal, context: context)
        guard !selectedExerciseIDs.isEmpty, selectedExerciseIDs.isSubset(of: Set(proposal.items.map(\.exerciseID))) else {
            throw CoachContractError.selectionRequired
        }
        return proposal.items.filter { selectedExerciseIDs.contains($0.exerciseID) }
    }

    private static func decode<T: Decodable>(_ type: T.Type, data: Data) throws -> T {
        guard !data.isEmpty, data.count <= 65_536 else { throw CoachContractError.malformed }
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw CoachContractError.malformed }
    }

    private static func validate(_ proposal: WorkoutProposal, context: CoachValidationContext) throws {
        guard !context.generationID.isEmpty, proposal.generationID == context.generationID else { throw CoachContractError.staleGeneration }
        let limits = context.planLimits
        guard (1...12).contains(limits.maxExercises), (1...10).contains(limits.maxSetsPerExercise),
              (1...200).contains(limits.maxReps), (1...600).contains(limits.maxHoldSeconds),
              (0...600).contains(limits.maxRestSeconds), (1...120).contains(limits.maxTotalSets),
              (1...limits.maxExercises).contains(proposal.items.count),
              Set(proposal.items.map(\.exerciseID)).count == proposal.items.count else { throw CoachContractError.invalidProposal }
        try validate(proposal.rationale, context: context)
        for item in proposal.items {
            guard let exercise = ExerciseCatalog.find(item.exerciseID), exercise.unit == item.unit,
                  (1...limits.maxSetsPerExercise).contains(item.sets), (1...(item.unit == .reps ? limits.maxReps : limits.maxHoldSeconds)).contains(item.target),
                  (0...limits.maxRestSeconds).contains(item.restSeconds),
                  exercise.support.map({ context.availableSupport.contains($0) }) ?? true else { throw CoachContractError.invalidProposal }
            try validateEvidence(item.factIDs, context: context)
        }
        guard proposal.items.reduce(0, { $0 + $1.sets }) <= limits.maxTotalSets else { throw CoachContractError.invalidProposal }
    }

    static func validate(_ text: GroundedCoachText, context: CoachValidationContext) throws {
        guard (1...500).contains(text.text.count), !text.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CoachContractError.malformed }
        try validateEvidence(text.factIDs, context: context)
    }

    private static func validateEvidence(_ ids: [String], context: CoachValidationContext) throws {
        guard (1...16).contains(ids.count), Set(ids).count == ids.count,
              Set(ids).isSubset(of: context.suppliedFactIDs) else { throw CoachContractError.invalidEvidence }
    }
}

private struct CoachJSONKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ value: String) { stringValue = value }
    init?(stringValue: String) { self.init(stringValue) }
    init?(intValue: Int) { return nil }
}

private extension Decoder {
    func strictKeys(_ expected: Set<String>) throws -> KeyedDecodingContainer<CoachJSONKey> {
        let values = try container(keyedBy: CoachJSONKey.self)
        guard Set(values.allKeys.map(\.stringValue)) == expected else { throw CoachContractError.malformed }
        return values
    }
}

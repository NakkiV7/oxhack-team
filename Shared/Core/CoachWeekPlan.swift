import Foundation

public struct CoachWeekRequest: Codable, Sendable {
    public let startDate: String
    public let timeZone: String
    public let availableDays: [Int]
    public let targetDays: Int
    public init(startDate: String, timeZone: String, availableDays: [Int], targetDays: Int) throws {
        self.startDate = startDate; self.timeZone = timeZone; self.availableDays = availableDays; self.targetDays = targetDays
        try validate()
    }
    public func validate() throws {
        guard TimeZone(identifier: timeZone) != nil, Self.date(startDate) != nil,
              (1...7).contains(availableDays.count), Set(availableDays).count == availableDays.count,
              availableDays.allSatisfy({ (0...6).contains($0) }), (1...availableDays.count).contains(targetDays) else { throw CoachContractError.invalidProposal }
    }
    public func dates() throws -> [String] {
        try validate()
        guard let start = Self.date(startDate) else { throw CoachContractError.invalidProposal }
        return (0..<7).map { Self.formatter.string(from: start.addingTimeInterval(Double($0) * 86_400)) }
    }
    private static var formatter: DateFormatter {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        return formatter
    }
    private static func date(_ string: String) -> Date? {
        guard string.count == 10, let date = formatter.date(from: string), formatter.string(from: date) == string else { return nil }
        return date
    }
}

public struct CoachWeekProposal: Decodable, Sendable {
    public enum Status: String, Decodable, Sendable { case proposed, declined }
    public enum Reason: String, Decodable, Sendable {
        case unrelated, medical, urgent
        public var message: String {
            switch self {
            case .unrelated: return "I can help with Spottr, exercise planning and your recorded training. Ask a training question to continue."
            case .medical: return "I can offer general exercise guidance, but cannot diagnose or prescribe treatment or a rehabilitation plan. Ask a qualified healthcare professional about symptoms or a medical condition before planning exercise."
            case .urgent: return "Stop exercising. If chest pain is sudden or does not go away, or comes with sweating, sickness, light-headedness or breathlessness, call 999. This is general NHS guidance, not a diagnosis."
            }
        }
    }
    public struct Day: Decodable, Identifiable, Sendable {
        public enum Kind: String, Decodable, Sendable { case workout, rest }
        public var id: String { date }
        public let date: String
        public let kind: Kind
        public let workout: WorkoutProposal?
        public init(from decoder: Decoder) throws {
            let values = try decoder.weekKeys(["date", "kind", "workout"])
            date = try values.decode(String.self, forKey: .init("date")); kind = try values.decode(Kind.self, forKey: .init("kind"))
            workout = try values.decodeIfPresent(WorkoutProposal.self, forKey: .init("workout"))
        }
    }
    public let generationID: String
    public let status: Status
    public let weekStart: String?
    public let timeZone: String?
    public let days: [Day]
    public let rationale: GroundedCoachText?
    public let reason: Reason?
    public let guidanceIDs: [String]
    public init(from decoder: Decoder) throws {
        let initial = try decoder.container(keyedBy: WeekKey.self)
        status = try initial.decode(Status.self, forKey: .init("status"))
        let values = try decoder.weekKeys(status == .proposed ? ["generationID", "status", "weekStart", "timeZone", "days", "rationale", "guidanceIDs"] : ["generationID", "status", "reason", "guidanceIDs"])
        generationID = try values.decode(String.self, forKey: .init("generationID")); guidanceIDs = try values.decode([String].self, forKey: .init("guidanceIDs"))
        weekStart = try values.decodeIfPresent(String.self, forKey: .init("weekStart")); timeZone = try values.decodeIfPresent(String.self, forKey: .init("timeZone"))
        days = try values.decodeIfPresent([Day].self, forKey: .init("days")) ?? []
        rationale = try values.decodeIfPresent(GroundedCoachText.self, forKey: .init("rationale")); reason = try values.decodeIfPresent(Reason.self, forKey: .init("reason"))
    }
}

public enum CoachWeekContracts {
    public static func parse(_ data: Data, request: CoachWeekRequest, context: CoachValidationContext, guidance: CoachGuidanceRegistry) throws -> CoachWeekProposal {
        guard !data.isEmpty, data.count <= 65_536, let proposal = try? JSONDecoder().decode(CoachWeekProposal.self, from: data) else { throw CoachContractError.malformed }
        try validate(proposal, request: request, context: context, guidance: guidance)
        return proposal
    }
    static func validate(_ proposal: CoachWeekProposal, request: CoachWeekRequest, context: CoachValidationContext, guidance: CoachGuidanceRegistry) throws {
        try request.validate()
        guard !context.generationID.isEmpty, proposal.generationID == context.generationID else { throw CoachContractError.staleGeneration }
        _ = try guidance.sources(for: proposal.guidanceIDs)
        if proposal.status == .declined {
            guard proposal.reason != nil, proposal.reason != .urgent || proposal.guidanceIDs.contains("nhs-chest-pain") else { throw CoachContractError.invalidEvidence }
            return
        }
        let dates = try request.dates(), workouts = proposal.days.filter { $0.kind == .workout }
        guard proposal.weekStart == request.startDate, proposal.timeZone == request.timeZone,
              proposal.days.map(\.date) == dates, (1...request.targetDays).contains(workouts.count), let rationale = proposal.rationale else { throw CoachContractError.invalidProposal }
        guard !hasLink(rationale.text) else { throw CoachContractError.invalidEvidence }
        try CoachContracts.validate(rationale, context: context)
        for (index, day) in proposal.days.enumerated() {
            if day.kind == .rest {
                guard day.workout == nil else { throw CoachContractError.invalidProposal }; continue
            }
            guard request.availableDays.contains(index), let workout = day.workout, workout.items.count <= 3, !hasLink(workout.rationale.text) else { throw CoachContractError.invalidProposal }
            _ = try CoachContracts.approvedItems(from: workout, selectedExerciseIDs: Set(workout.items.map(\.exerciseID)), context: context)
        }
    }
    private static func hasLink(_ text: String) -> Bool {
        text.range(of: "https?:|www\\.", options: [.regularExpression, .caseInsensitive]) != nil
    }
}

public struct CoachSavedWeek: Codable, Sendable {
    public struct Day: Codable, Identifiable, Sendable {
        public var id: String { date }
        public let date: String
        public let plan: CoachSavedPlan
    }
    public let version: Int
    public let weekStart: String
    public let timeZone: String
    public let days: [Day]
    public let guidanceIDs: [String]
    public let approvedAt: Date
    public init(proposal: CoachWeekProposal, selectedDates: Set<String>, movedDates: [String: String], context: CoachValidationContext, request: CoachWeekRequest, guidance: CoachGuidanceRegistry, approvedAt: Date = Date()) throws {
        try CoachWeekContracts.validate(proposal, request: request, context: context, guidance: guidance)
        let workouts = proposal.days.filter { $0.kind == .workout }
        guard !selectedDates.isEmpty, selectedDates.isSubset(of: Set(workouts.map(\.date))), Set(movedDates.keys).isSubset(of: selectedDates) else { throw CoachContractError.selectionRequired }
        let dates = try request.dates()
        let days = try workouts.filter { selectedDates.contains($0.date) }.map { day -> Day in
            let date = movedDates[day.date] ?? day.date
            guard let index = dates.firstIndex(of: date), request.availableDays.contains(index), let workout = day.workout else { throw CoachContractError.invalidProposal }
            return Day(date: date, plan: try CoachSavedPlan(proposal: workout, selectedExerciseIDs: Set(workout.items.map(\.exerciseID)), context: context, approvedAt: approvedAt))
        }
        guard Set(days.map(\.date)).count == days.count else { throw CoachContractError.invalidProposal }
        version = 1; weekStart = request.startDate; timeZone = request.timeZone; self.days = days.sorted { $0.date < $1.date }; guidanceIDs = proposal.guidanceIDs; self.approvedAt = approvedAt
    }
    public static func decode(_ data: Data) throws -> CoachSavedWeek {
        guard data.count <= 65_536, let saved = try? JSONDecoder().decode(Self.self, from: data), saved.version == 1,
              saved.approvedAt.timeIntervalSince1970.isFinite, (1...7).contains(saved.days.count) else { throw CoachContractError.invalidProposal }
        let request = try CoachWeekRequest(startDate: saved.weekStart, timeZone: saved.timeZone, availableDays: Array(0...6), targetDays: 7)
        let dates = try request.dates()
        guard Set(saved.days.map(\.date)).count == saved.days.count, saved.days.map(\.date) == saved.days.map(\.date).sorted(),
              saved.days.allSatisfy({ dates.contains($0.date) && $0.plan.items.count <= 3 }) else { throw CoachContractError.invalidProposal }
        _ = try CoachGuidanceRegistry.bundled().sources(for: saved.guidanceIDs)
        let supports = Set(ExerciseCatalog.all.compactMap(\.support))
        for day in saved.days { _ = try ConfigurableSession(plan: day.plan, availableSupport: supports) }
        return saved
    }
}

private struct WeekKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ value: String) { stringValue = value }
    init?(stringValue: String) { self.init(stringValue) }
    init?(intValue: Int) { nil }
}
private extension Decoder {
    func weekKeys(_ expected: Set<String>) throws -> KeyedDecodingContainer<WeekKey> {
        let values = try container(keyedBy: WeekKey.self)
        guard Set(values.allKeys.map(\.stringValue)) == expected else { throw CoachContractError.malformed }
        return values
    }
}

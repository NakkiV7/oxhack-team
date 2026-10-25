import Foundation

public struct LocalProfile: Codable, Equatable, Sendable {
    public enum BaselineAbility: String, CaseIterable, Codable, Sendable {
        case startingOut, somePractice, regularPractice
        public var title: String {
            switch self {
            case .startingOut: return "Starting out"
            case .somePractice: return "Some practice"
            case .regularPractice: return "Regular practice"
            }
        }
        public var suggestedLevel: Int {
            switch self {
            case .startingOut: return 1
            case .somePractice: return 2
            case .regularPractice: return 3
            }
        }
    }
    public enum Invalid: LocalizedError, Sendable {
        case name, weeklyTarget, goals
        public var errorDescription: String? {
            switch self {
            case .name: return "Use a name of 40 characters or fewer, on one line."
            case .weeklyTarget: return "Choose between 1 and 7 training days per week."
            case .goals: return "Choose at least one training goal."
            }
        }
    }
    public let name: String
    public let weeklyTarget: Int
    public let goals: Set<TrainingAttribute>
    public let baselineAbility: BaselineAbility?

    public init(name: String = "", weeklyTarget: Int = 3, goals: Set<TrainingAttribute> = [.strength],
                baselineAbility: BaselineAbility? = nil) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 40, !trimmed.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw Invalid.name }
        guard (1...7).contains(weeklyTarget) else { throw Invalid.weeklyTarget }
        guard !goals.isEmpty else { throw Invalid.goals }
        self.name = trimmed
        self.weeklyTarget = weeklyTarget
        self.goals = goals
        self.baselineAbility = baselineAbility
    }

    private enum CodingKeys: String, CodingKey { case name, weeklyTarget, goals, baselineAbility }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(name: values.decode(String.self, forKey: .name),
                      weeklyTarget: values.decode(Int.self, forKey: .weeklyTarget),
                      goals: values.decode(Set<TrainingAttribute>.self, forKey: .goals),
                      baselineAbility: values.decodeIfPresent(BaselineAbility.self, forKey: .baselineAbility))
    }
}

import Foundation

public struct LocalProfile: Codable, Equatable, Sendable {
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

    public init(name: String = "", weeklyTarget: Int = 3, goals: Set<TrainingAttribute> = [.strength]) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 40, !trimmed.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw Invalid.name }
        guard (1...7).contains(weeklyTarget) else { throw Invalid.weeklyTarget }
        guard !goals.isEmpty else { throw Invalid.goals }
        self.name = trimmed
        self.weeklyTarget = weeklyTarget
        self.goals = goals
    }

    private enum CodingKeys: String, CodingKey { case name, weeklyTarget, goals }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(name: values.decode(String.self, forKey: .name),
                      weeklyTarget: values.decode(Int.self, forKey: .weeklyTarget),
                      goals: values.decode(Set<TrainingAttribute>.self, forKey: .goals))
    }
}

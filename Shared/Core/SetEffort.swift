import Foundation

public enum SetEffort: Int, CaseIterable, Codable, Sendable {
    case veryEasy = 2, easy = 4, moderate = 6, hard = 8, veryHard = 10
    public var title: String {
        switch self {
        case .veryEasy: return "Very easy"
        case .easy: return "Easy"
        case .moderate: return "Moderate"
        case .hard: return "Hard"
        case .veryHard: return "Very hard"
        }
    }
}

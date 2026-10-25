import Foundation

public struct LocalBodyMeasurements: Codable, Equatable, Sendable {
    public enum Thresholds: String, Codable, CaseIterable, Sendable { case standard, lower }
    public enum Category: String, Codable, Sendable { case underweight, healthyWeight, overweight, obesity }
    public enum Invalid: LocalizedError, Sendable {
        case height, weight
        public var errorDescription: String? {
            switch self {
            case .height: return "Enter a height between 50 and 275 cm."
            case .weight: return "Enter a weight between 10 and 500 kg."
            }
        }
    }
    public let heightCM: Double
    public let weightKG: Double
    public let bmiEligible: Bool
    public let thresholds: Thresholds?

    public init(heightCM: Double, weightKG: Double, bmiEligible: Bool = false, thresholds: Thresholds? = nil) throws {
        guard heightCM.isFinite, (50...275).contains(heightCM) else { throw Invalid.height }
        guard weightKG.isFinite, (10...500).contains(weightKG) else { throw Invalid.weight }
        self.heightCM = heightCM
        self.weightKG = weightKG
        self.bmiEligible = bmiEligible
        self.thresholds = thresholds
    }

    public var bmi: Double? {
        guard bmiEligible else { return nil }
        let metres = heightCM / 100
        return weightKG / (metres * metres)
    }

    public var category: Category? {
        guard let bmi, let thresholds else { return nil }
        if bmi < 18.5 { return .underweight }
        if bmi < (thresholds == .lower ? 23 : 25) { return .healthyWeight }
        if bmi < (thresholds == .lower ? 27.5 : 30) { return .overweight }
        return .obesity
    }

    private enum CodingKeys: String, CodingKey { case heightCM, weightKG, bmiEligible, thresholds }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(heightCM: values.decode(Double.self, forKey: .heightCM),
                      weightKG: values.decode(Double.self, forKey: .weightKG),
                      bmiEligible: values.decode(Bool.self, forKey: .bmiEligible),
                      thresholds: values.decodeIfPresent(Thresholds.self, forKey: .thresholds))
    }
}

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
    public let bodyMeasurements: LocalBodyMeasurements?

    public init(name: String = "", weeklyTarget: Int = 3, goals: Set<TrainingAttribute> = [.strength],
                baselineAbility: BaselineAbility? = nil, bodyMeasurements: LocalBodyMeasurements? = nil) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 40, !trimmed.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw Invalid.name }
        guard (1...7).contains(weeklyTarget) else { throw Invalid.weeklyTarget }
        guard !goals.isEmpty else { throw Invalid.goals }
        self.name = trimmed
        self.weeklyTarget = weeklyTarget
        self.goals = goals
        self.baselineAbility = baselineAbility
        self.bodyMeasurements = bodyMeasurements
    }

    private enum CodingKeys: String, CodingKey { case name, weeklyTarget, goals, baselineAbility, bodyMeasurements }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(name: values.decode(String.self, forKey: .name),
                      weeklyTarget: values.decode(Int.self, forKey: .weeklyTarget),
                      goals: values.decode(Set<TrainingAttribute>.self, forKey: .goals),
                      baselineAbility: values.decodeIfPresent(BaselineAbility.self, forKey: .baselineAbility),
                      bodyMeasurements: values.decodeIfPresent(LocalBodyMeasurements.self, forKey: .bodyMeasurements))
    }
}

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
    public let comfortableExercises: Set<String>
    public let weightManagementGoal: Bool
    public let onboardingRevision: Int
    public let programmePreferences: ProgrammePreferences?

    public init(name: String = "", weeklyTarget: Int = 3, goals: Set<TrainingAttribute> = [.strength],
                baselineAbility: BaselineAbility? = nil, bodyMeasurements: LocalBodyMeasurements? = nil,
                comfortableExercises: Set<String> = [], weightManagementGoal: Bool = false, onboardingRevision: Int = 2,
                programmePreferences: ProgrammePreferences? = nil) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 40, !trimmed.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw Invalid.name }
        guard (1...7).contains(weeklyTarget) else { throw Invalid.weeklyTarget }
        guard !goals.isEmpty else { throw Invalid.goals }
        self.name = trimmed
        self.weeklyTarget = weeklyTarget
        self.goals = goals
        self.baselineAbility = baselineAbility
        self.bodyMeasurements = bodyMeasurements
        self.comfortableExercises = comfortableExercises.filter { ExerciseCatalog.find($0) != nil }
        self.weightManagementGoal = weightManagementGoal
        self.onboardingRevision = onboardingRevision
        self.programmePreferences = programmePreferences
    }

    private enum CodingKeys: String, CodingKey { case name, weeklyTarget, goals, baselineAbility, bodyMeasurements, comfortableExercises, weightManagementGoal, onboardingRevision, programmePreferences }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(name: values.decode(String.self, forKey: .name),
                      weeklyTarget: values.decode(Int.self, forKey: .weeklyTarget),
                      goals: values.decode(Set<TrainingAttribute>.self, forKey: .goals),
                      baselineAbility: values.decodeIfPresent(BaselineAbility.self, forKey: .baselineAbility),
                      bodyMeasurements: values.decodeIfPresent(LocalBodyMeasurements.self, forKey: .bodyMeasurements),
                      comfortableExercises: values.decodeIfPresent(Set<String>.self, forKey: .comfortableExercises) ?? [],
                      weightManagementGoal: values.decodeIfPresent(Bool.self, forKey: .weightManagementGoal) ?? false,
                      onboardingRevision: values.decodeIfPresent(Int.self, forKey: .onboardingRevision) ?? 0,
                      programmePreferences: values.decodeIfPresent(ProgrammePreferences.self, forKey: .programmePreferences))
    }
}


public struct BMIReference: Equatable, Sendable {
    public enum Band: String, CaseIterable, Sendable {
        case underweight, healthyWeight, overweight, obesityClass1, obesityClass2, obesityClass3
    }
    public enum Edge: String, Sendable { case below, above }
    public let value: Double
    public let boundaries: [Double]
    public let referenceWeightKG: Range<Double>
    public var band: Band { Band.allCases[boundaries.filter { value >= $0 }.count] }
    public var markerPosition: Double { (value - 15) / 30 }
    public var visualMarkerPosition: Double { min(1, max(0, markerPosition)) }
    public var edge: Edge? { markerPosition < 0 ? .below : markerPosition > 1 ? .above : nil }
}

public extension LocalBodyMeasurements {
    var reference: BMIReference? {
        guard let bmi, let thresholds else { return nil }
        let boundaries: [Double] = thresholds == .standard ? [18.5, 25, 30, 35, 40] : [18.5, 23, 27.5, 32.5, 37.5]
        let heightSquared = (heightCM / 100) * (heightCM / 100)
        return .init(value: bmi, boundaries: boundaries, referenceWeightKG: (18.5 * heightSquared)..<(boundaries[1] * heightSquared))
    }
}


public struct AgeAwareBMI: Equatable, Sendable {
    public let value: Double?
    public let adultReference: BMIReference?
    public let adultCategory: LocalBodyMeasurements.Category?
    public let needsChildGrowthReference: Bool
}

public extension LocalProfile {
    var bmiAssessment: AgeAwareBMI {
        guard let age = programmePreferences?.ageContext?.ageYears, age >= 2, let bodyMeasurements else {
            return .init(value: nil, adultReference: nil, adultCategory: nil, needsChildGrowthReference: false)
        }
        guard age >= 18 else {
            let metres = bodyMeasurements.heightCM / 100
            return .init(value: bodyMeasurements.weightKG / (metres * metres), adultReference: nil,
                         adultCategory: nil, needsChildGrowthReference: true)
        }
        return .init(value: bodyMeasurements.bmi, adultReference: bodyMeasurements.reference,
                     adultCategory: bodyMeasurements.category, needsChildGrowthReference: false)
    }
}

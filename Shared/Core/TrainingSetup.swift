import Foundation

public enum TrainingSetup {
    public static let revision = 3
    public enum Stage: Int, CaseIterable, Sendable {
        case account = 1, body, goals, comfort, permissions, coach
        public var title: String {
            switch self {
            case .account: return "Account and privacy"
            case .body: return "Your training profile"
            case .goals: return "Goals and rhythm"
            case .comfort: return "Your starting point"
            case .permissions: return "Phone and Watch"
            case .coach: return "Your coach and week"
            }
        }
        public var canSkip: Bool { self == .permissions || self == .coach }
    }
    public enum Comfort: Codable, Equatable, Sendable {
        case unsure
        case movement(String)
    }
    public static func nextUnanswered(_ answers: [ExerciseFamily: Comfort]) -> ExerciseFamily? {
        ExerciseFamily.allCases.first { answers[$0] == nil }
    }
    public static func comfortComplete(_ preferences: ProgrammePreferences) -> Bool {
        if (preferences.ageContext?.ageYears ?? 120) < 5 { return true }
        guard preferences.startingPoint != nil else { return false }
        return ExerciseFamily.allCases.allSatisfy { family in
            guard let answer = preferences.comfortAnswers[family] else { return false }
            switch answer {
            case .unsure: return true
            case .movement(let id): return ExerciseCatalog.find(id)?.family == family && ExerciseCatalog.find(id).map(preferences.canUse) == true
            }
        }
    }
}

public enum MeasurementUnits: String, CaseIterable, Sendable {
    case metric, imperial
    public func measurements(height: String, weight: String, locale: Locale = .current,
                             bmiEligible: Bool, thresholds: LocalBodyMeasurements.Thresholds?) throws -> LocalBodyMeasurements {
        func parse(_ text: String) -> Double? {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let separator = locale.decimalSeparator ?? "."
            let normalized = trimmed.replacingOccurrences(of: separator, with: ".")
            guard !normalized.isEmpty, normalized.allSatisfy({ $0.isNumber || $0 == "." }),
                  normalized.filter({ $0 == "." }).count <= 1 else { return nil }
            return Double(normalized)
        }
        guard let height = parse(height) else { throw LocalBodyMeasurements.Invalid.height }
        guard let weight = parse(weight) else { throw LocalBodyMeasurements.Invalid.weight }
        return try LocalBodyMeasurements(heightCM: height * (self == .metric ? 1 : 2.54),
            weightKG: weight * (self == .metric ? 1 : 0.45359237), bmiEligible: bmiEligible, thresholds: thresholds)
    }
}

public extension ProgrammePreferences {
    func changingAge(to age: TrainingAgeContext) throws -> ProgrammePreferences {
        try ProgrammePreferences(goals: age.ageYears < 18 ? goals.subtracting([.weightManagement]).isEmpty ? [.balance] : goals.subtracting([.weightManagement]) : goals,
            weekdays: weekdays, minutesPerSession: minutesPerSession, preferredLocalHour: preferredLocalHour,
            availableSupport: availableSupport, allowsFloorWork: allowsFloorWork, excludedExerciseIDs: excludedExerciseIDs,
            startingPoint: startingPoint, ageContext: age, comfortAnswers: [:])
    }
}

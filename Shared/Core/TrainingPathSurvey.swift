import Foundation

/// The two training paths a person can choose. Each follows one catalogue family in level order, and its goal exercise
/// is the movement the camera can track.
public enum PathGoal: String, Codable, CaseIterable, Sendable {
    case squat, pushup
    public var exerciseID: String { rawValue }
    public var title: String { self == .squat ? "Squat path" : "Push-up path" }
    public var family: ExerciseFamily { self == .squat ? .legs : .push }
    /// The main chain of the family, foundation first.
    public var chain: [String] {
        ExerciseCatalog.all.filter { $0.family == family }.sorted { $0.level < $1.level }.map(\.id)
    }
    /// Movements a person may leave out: the rest of the chain and its catalogue support steps. Never the goal itself.
    public var avoidable: [String] {
        let supports = chain.flatMap(TrainingPathRules.supportLinks(of:))
        return (chain.filter { $0 != exerciseID } + supports).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
    }
    /// Concrete self-report statements. Each maps to a placement band; none of them is a strength or fitness score.
    public var abilityOptions: [AbilityOption] {
        switch self {
        case .squat: return [
            .init(key: "new", label: "I'm new to squats", band: .beginner),
            .init(key: "control", label: "I can squat, but want help with control", band: .intermediate),
            .init(key: "comfortable", label: "I can do a comfortable set", band: .advanced),
            .init(key: "unsure", label: "I'm not sure", band: .unsure)
        ]
        case .pushup: return [
            .init(key: "notTried", label: "I haven't tried recently", band: .beginner),
            .init(key: "first", label: "I'm working towards my first standard push-up", band: .beginner),
            .init(key: "few", label: "I can do a few", band: .intermediate),
            .init(key: "comfortable", label: "I can do a comfortable set", band: .advanced),
            .init(key: "unsure", label: "I'm not sure", band: .unsure)
        ]
        }
    }
}

public enum PlacementBand: String, Codable, Sendable { case beginner, intermediate, advanced, unsure }

public struct AbilityOption: Equatable, Sendable {
    public let key: String
    public let label: String
    public let band: PlacementBand
}

public enum PathFocus: String, Codable, CaseIterable, Sendable {
    case learn, consistency, improve, unsure
    public var title: String {
        switch self {
        case .learn: return "Learn the movement"
        case .consistency: return "Build consistency"
        case .improve: return "Improve a skill I have"
        case .unsure: return "Balance all three"
        }
    }
}

public enum CoachingStyle: String, Codable, CaseIterable, Sendable {
    case concise, encouraging, explanatory
    public var title: String { rawValue.capitalized }
}

/// Answers to "Build my training path". Saved as they are given so the survey can resume, and kept separate from the
/// onboarding profile, which it only reads.
public struct PathSurvey: Codable, Equatable, Sendable {
    public var goal: PathGoal
    public var abilityKey: String?
    /// The onboarding baseline, used for placement until the person answers the starting-point question.
    public var fallbackBand: PlacementBand?
    /// Catalogue support names the person has nearby (the same names the Coach tab and workout setup use).
    /// `nil` means the question was not answered, so no movement is filtered out for equipment.
    public var equipment: Set<String>?
    public var minutesPerSession: Int
    public var sessionsPerWeek: Int
    public var focus: PathFocus?
    public var coachingStyle: CoachingStyle?
    public var avoid: Set<String>

    public init(goal: PathGoal = .squat, abilityKey: String? = nil, fallbackBand: PlacementBand? = nil, equipment: Set<String>? = nil,
                minutesPerSession: Int = 20, sessionsPerWeek: Int = 3, focus: PathFocus? = nil, coachingStyle: CoachingStyle? = nil,
                avoid: Set<String> = []) {
        self.goal = goal; self.abilityKey = abilityKey; self.fallbackBand = fallbackBand; self.equipment = equipment
        self.minutesPerSession = minutesPerSession; self.sessionsPerWeek = sessionsPerWeek; self.focus = focus
        self.coachingStyle = coachingStyle; self.avoid = avoid
    }

    /// Starting answers from the onboarding profile, so nobody is asked twice for what they already told the app.
    public init(profile: LocalProfile?, goal: PathGoal = .squat) {
        let band: PlacementBand? = profile?.baselineAbility.map {
            switch $0 {
            case .startingOut: return .beginner
            case .somePractice: return .intermediate
            case .regularPractice: return .advanced
            }
        }
        self.init(goal: goal, fallbackBand: band, sessionsPerWeek: min(6, max(1, profile?.weeklyTarget ?? 3)))
    }

    public var band: PlacementBand { goal.abilityOptions.first { $0.key == abilityKey }?.band ?? fallbackBand ?? .beginner }

    /// Equipment the survey offers: every catalogue support that a movement actually needs.
    public static var equipmentChoices: [String] {
        Array(Set(ExerciseCatalog.all.compactMap(requiredEquipment(for:)))).sorted()
    }
    /// The support a movement needs, or `nil` when it needs none or the support is optional.
    public static func requiredEquipment(for entry: ExerciseEntry) -> String? {
        guard let support = entry.support, !support.lowercased().hasPrefix("optional") else { return nil }
        return support
    }

    /// Whether a movement can be in this person's path: not left out, and its equipment is available when they said what they have.
    public func canUse(_ exerciseID: String) -> Bool {
        guard let entry = ExerciseCatalog.find(exerciseID) else { return false }
        if avoid.contains(exerciseID) && exerciseID != goal.exerciseID { return false }
        guard let need = Self.requiredEquipment(for: entry), let equipment else { return true }
        return equipment.contains(need)
    }

    private enum CodingKeys: String, CodingKey { case goal, abilityKey, fallbackBand, equipment, minutesPerSession, sessionsPerWeek, focus, coachingStyle, avoid }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(goal: try values.decodeIfPresent(PathGoal.self, forKey: .goal) ?? .squat,
                  abilityKey: try values.decodeIfPresent(String.self, forKey: .abilityKey),
                  fallbackBand: try values.decodeIfPresent(PlacementBand.self, forKey: .fallbackBand),
                  equipment: try values.decodeIfPresent(Set<String>.self, forKey: .equipment),
                  minutesPerSession: try values.decodeIfPresent(Int.self, forKey: .minutesPerSession) ?? 20,
                  sessionsPerWeek: try values.decodeIfPresent(Int.self, forKey: .sessionsPerWeek) ?? 3,
                  focus: try values.decodeIfPresent(PathFocus.self, forKey: .focus),
                  coachingStyle: try values.decodeIfPresent(CoachingStyle.self, forKey: .coachingStyle),
                  avoid: try values.decodeIfPresent(Set<String>.self, forKey: .avoid) ?? [])
    }
}

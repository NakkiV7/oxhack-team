import Foundation

public enum TrainingAttribute: String, CaseIterable, Codable, Sendable {
    case strength, stamina, mobility, balance
    public var title: String { rawValue.capitalized }
}
public enum ExerciseFamily: String, CaseIterable, Codable, Sendable {
    case push, legs, core, conditioning, mobility, balance
    public var title: String {
        switch self {
        case .push: return "Push-ups"
        case .legs: return "Lower body"
        case .core: return "Core"
        case .conditioning: return "Conditioning"
        case .mobility: return "Mobility"
        case .balance: return "Balance"
        }
    }
}
public struct ExerciseEntry: Identifiable, Sendable {
    public enum Unit: String, Codable, Sendable { case reps, seconds }
    public let id: String
    public let name: String
    public let family: ExerciseFamily
    public let level: Int
    public let goal: Int
    public let unit: Unit
    public let attribute: TrainingAttribute
    public let instruction: String
    public let support: String?
    public let tracking: Exercise?
    public var levelName: String { "\(family.title) \(["I", "II", "III", "IV", "V"][min(4, max(0, level - 1))])" }
    public var goalText: String { "3 × \(goal) \(unit == .reps ? "reps" : "sec") · 2 days" }
    public var art: String { tracking.map { "\($0.rawValue)-mid" } ?? id }
}

public enum ExerciseCatalog {
    public static let version = 1
    public static let all: [ExerciseEntry] = [
        .init(id: "wallPushup", name: "Wall push-ups", family: .push, level: 1, goal: 8, unit: .reps, attribute: .strength, instruction: "Keep your body straight. Bend your elbows toward the wall, then press away.", support: "Wall", tracking: nil),
        .init(id: "inclinePushup", name: "Incline push-ups", family: .push, level: 2, goal: 8, unit: .reps, attribute: .strength, instruction: "Use a stable raised surface. Keep your body in one line as you lower and press.", support: "Stable sofa or counter", tracking: nil),
        .init(id: "kneePushup", name: "Knee push-ups", family: .push, level: 3, goal: 8, unit: .reps, attribute: .strength, instruction: "Rest your knees on the floor. Keep shoulders, hips and knees in one line.", support: nil, tracking: nil),
        .init(id: "pushup", name: "Push-ups", family: .push, level: 4, goal: 10, unit: .reps, attribute: .strength, instruction: "Brace your body. Lower with control and return to extended arms.", support: nil, tracking: .pushup),
        .init(id: "closeGripPushup", name: "Close-grip push-ups", family: .push, level: 5, goal: 6, unit: .reps, attribute: .strength, instruction: "Place your hands closer together under your chest. Keep elbows close to your sides.", support: nil, tracking: nil),
        .init(id: "gluteBridge", name: "Glute bridges", family: .legs, level: 1, goal: 12, unit: .reps, attribute: .strength, instruction: "Plant your feet, lift your hips with control, then lower without arching your back.", support: nil, tracking: nil),
        .init(id: "squat", name: "Squats", family: .legs, level: 2, goal: 12, unit: .reps, attribute: .strength, instruction: "Sit back to a comfortable depth. Keep your feet planted and return to standing.", support: nil, tracking: .squat),
        .init(id: "reverseLunge", name: "Reverse lunges", family: .legs, level: 3, goal: 8, unit: .reps, attribute: .balance, instruction: "Step back, lower with control and return. Count each completed side as one rep.", support: nil, tracking: nil),
        .init(id: "splitSquat", name: "Split squats", family: .legs, level: 4, goal: 8, unit: .reps, attribute: .strength, instruction: "Keep a stable split stance. Lower and rise without stepping. Alternate sides between sets.", support: nil, tracking: nil),
        .init(id: "assistedSquat", name: "Assisted single-leg squats", family: .legs, level: 5, goal: 5, unit: .reps, attribute: .balance, instruction: "Hold a stable support. Use a comfortable single-leg range and rise with control.", support: "Stable support", tracking: nil),
        .init(id: "deadBug", name: "Dead bugs", family: .core, level: 1, goal: 8, unit: .reps, attribute: .balance, instruction: "Lie on your back. Slowly extend opposite arm and leg, then return. Count each side.", support: nil, tracking: nil),
        .init(id: "plank", name: "Forearm plank", family: .core, level: 2, goal: 20, unit: .seconds, attribute: .stamina, instruction: "Rest on forearms and toes. Keep your body in one line and breathe steadily.", support: nil, tracking: nil),
        .init(id: "sidePlank", name: "Side plank", family: .core, level: 3, goal: 15, unit: .seconds, attribute: .balance, instruction: "Support yourself on one forearm and the side of your feet. Alternate sides between sets.", support: nil, tracking: nil),
        .init(id: "stepJack", name: "Step jacks", family: .conditioning, level: 1, goal: 20, unit: .reps, attribute: .stamina, instruction: "Step one foot out while raising your arms. Return and alternate sides. Count each step out.", support: nil, tracking: nil),
        .init(id: "highKnees", name: "High knees", family: .conditioning, level: 2, goal: 30, unit: .seconds, attribute: .stamina, instruction: "March or jog in place, lifting alternate knees at a pace you can control.", support: nil, tracking: nil),
        .init(id: "mountainClimber", name: "Mountain climbers", family: .conditioning, level: 3, goal: 20, unit: .reps, attribute: .stamina, instruction: "From a high plank, bring one knee forward and return. Alternate and count each knee drive.", support: nil, tracking: nil),
        .init(id: "catCow", name: "Cat-cow", family: .mobility, level: 1, goal: 6, unit: .reps, attribute: .mobility, instruction: "On hands and knees, gently round and lengthen your back. One comfortable cycle is one rep.", support: nil, tracking: nil),
        .init(id: "hipFlexorStretch", name: "Hip-flexor stretch", family: .mobility, level: 2, goal: 30, unit: .seconds, attribute: .mobility, instruction: "Use a half-kneeling stance and gently shift forward. Keep the stretch comfortable; alternate sides.", support: nil, tracking: nil),
        .init(id: "singleLegBalance", name: "Single-leg stand", family: .balance, level: 1, goal: 20, unit: .seconds, attribute: .balance, instruction: "Stand on one leg near a stable support. Keep your gaze steady and alternate sides.", support: "Optional nearby support", tracking: nil)
    ]
    public static func find(_ id: String) -> ExerciseEntry? { all.first { $0.id == id } }
}

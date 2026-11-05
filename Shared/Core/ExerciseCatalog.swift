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
    public var art: String {
        ["widePushup", "diamondPushup", "wallSit", "calfRaise", "birdDog", "seatedKneeExtension"].contains(id)
            ? "stick-\(id)" : (tracking?.art ?? id)
    }
}

public enum ExerciseCatalog {
    public static let version = 3
    public static let all: [ExerciseEntry] = [
        .init(id: "wallPushup", name: "Wall push-ups", family: .push, level: 1, goal: 8, unit: .reps, attribute: .strength, instruction: "Keep your body straight. Bend your elbows toward the wall, then press away.", support: "Wall", tracking: .wallPushup),
        .init(id: "inclinePushup", name: "Incline push-ups", family: .push, level: 2, goal: 8, unit: .reps, attribute: .strength, instruction: "Use a stable raised surface. Keep your body in one line as you lower and press.", support: "Stable sofa or counter", tracking: .inclinePushup),
        .init(id: "kneePushup", name: "Knee push-ups", family: .push, level: 3, goal: 8, unit: .reps, attribute: .strength, instruction: "Rest your knees on the floor. Keep shoulders, hips and knees in one line.", support: nil, tracking: .kneePushup),
        .init(id: "pushup", name: "Push-ups", family: .push, level: 4, goal: 10, unit: .reps, attribute: .strength, instruction: "Brace your body. Lower with control and return to extended arms.", support: nil, tracking: .pushup),
        .init(id: "closeGripPushup", name: "Close-grip push-ups", family: .push, level: 5, goal: 6, unit: .reps, attribute: .strength, instruction: "Place your hands closer together under your chest. Keep elbows close to your sides.", support: nil, tracking: .closeGripPushup),
        .init(id: "gluteBridge", name: "Glute bridges", family: .legs, level: 1, goal: 12, unit: .reps, attribute: .strength, instruction: "Plant your feet, lift your hips with control, then lower without arching your back.", support: nil, tracking: .gluteBridge),
        .init(id: "squat", name: "Squats", family: .legs, level: 2, goal: 12, unit: .reps, attribute: .strength, instruction: "Sit back to a comfortable depth. Keep your feet planted and return to standing.", support: nil, tracking: .squat),
        .init(id: "halfSquat", name: "Half squats", family: .legs, level: 1, goal: 10, unit: .reps, attribute: .strength, instruction: "Stand side-on to the camera. Bend your knees to a comfortable half depth, then stand tall.", support: nil, tracking: .halfSquat),
        .init(id: "supportedSquat", name: "Supported squats", family: .legs, level: 1, goal: 8, unit: .reps, attribute: .strength, instruction: "Hold a stable support lightly. Sit back to a comfortable depth and stand tall. Keep your near leg in view.", support: "Stable support", tracking: .supportedSquat),
        .init(id: "wideSquat", name: "Wide squats", family: .legs, level: 3, goal: 10, unit: .reps, attribute: .strength, instruction: "Take a comfortably wider stance. Keep knees following your toes and sit back with control. Film from the side.", support: nil, tracking: .wideSquat),
        .init(id: "reverseLunge", name: "Reverse lunges", family: .legs, level: 3, goal: 8, unit: .reps, attribute: .balance, instruction: "Step back, lower with control and return. Count each completed side as one rep.", support: nil, tracking: .reverseLunge),
        .init(id: "splitSquat", name: "Split squats", family: .legs, level: 4, goal: 8, unit: .reps, attribute: .strength, instruction: "Keep a stable split stance. Lower and rise without stepping. Alternate sides between sets.", support: nil, tracking: .splitSquat),
        .init(id: "assistedSquat", name: "Assisted single-leg squats", family: .legs, level: 5, goal: 5, unit: .reps, attribute: .balance, instruction: "Hold a stable support. Use a comfortable single-leg range and rise with control.", support: "Stable support", tracking: .assistedSquat),
        .init(id: "deadBug", name: "Dead bugs", family: .core, level: 1, goal: 8, unit: .reps, attribute: .balance, instruction: "Lie on your back. Slowly extend opposite arm and leg, then return. Count each side.", support: nil, tracking: .deadBug),
        .init(id: "plank", name: "Forearm plank", family: .core, level: 2, goal: 20, unit: .seconds, attribute: .stamina, instruction: "Rest on forearms and toes. Keep your body in one line and breathe steadily.", support: nil, tracking: .plank),
        .init(id: "sidePlank", name: "Side plank", family: .core, level: 3, goal: 15, unit: .seconds, attribute: .balance, instruction: "Support yourself on one forearm and the side of your feet. Alternate sides between sets.", support: nil, tracking: .sidePlank),
        .init(id: "stepJack", name: "Step jacks", family: .conditioning, level: 1, goal: 20, unit: .reps, attribute: .stamina, instruction: "Step one foot out while raising your arms. Return and alternate sides. Count each step out.", support: nil, tracking: .stepJack),
        .init(id: "highKnees", name: "High knees", family: .conditioning, level: 2, goal: 30, unit: .seconds, attribute: .stamina, instruction: "March or jog in place, lifting alternate knees at a pace you can control.", support: nil, tracking: .highKnees),
        .init(id: "mountainClimber", name: "Mountain climbers", family: .conditioning, level: 3, goal: 20, unit: .reps, attribute: .stamina, instruction: "From a high plank, bring one knee forward and return. Alternate and count each knee drive.", support: nil, tracking: .mountainClimber),
        .init(id: "catCow", name: "Cat-cow", family: .mobility, level: 1, goal: 6, unit: .reps, attribute: .mobility, instruction: "On hands and knees, gently round and lengthen your back. One comfortable cycle is one rep.", support: nil, tracking: nil),
        .init(id: "hipFlexorStretch", name: "Hip-flexor stretch", family: .mobility, level: 2, goal: 30, unit: .seconds, attribute: .mobility, instruction: "Use a half-kneeling stance and gently shift forward. Keep the stretch comfortable; alternate sides.", support: nil, tracking: .hipFlexorStretch),
        .init(id: "singleLegBalance", name: "Single-leg stand", family: .balance, level: 1, goal: 20, unit: .seconds, attribute: .balance, instruction: "Stand on one leg near a stable support. Keep your gaze steady and alternate sides.", support: "Optional nearby support", tracking: .singleLegBalance),
        .init(id: "tempoSquat", name: "Tempo squats", family: .legs, level: 3, goal: 6, unit: .reps, attribute: .strength, instruction: "Film from the side. Take at least 3 seconds from leaving standing to reaching squat depth, then stand tall. Keep your near leg visible throughout.", support: nil, tracking: .tempoSquat),
        .init(id: "pausedSquat", name: "Paused squats", family: .legs, level: 3, goal: 6, unit: .reps, attribute: .strength, instruction: "Film from the side. Lower to squat depth, hold there for at least 2 seconds, then stand tall. Use a comfortable range; choose half squats if needed.", support: nil, tracking: .pausedSquat),
        .init(id: "tempoPushup", name: "Tempo push-ups", family: .push, level: 5, goal: 6, unit: .reps, attribute: .strength, instruction: "Film from the side with shoulders, hands, hips and feet visible. Take at least 3 seconds to lower from extended arms to depth, then press back up.", support: nil, tracking: .tempoPushup),
        .init(id: "pausedPushup", name: "Paused push-ups", family: .push, level: 5, goal: 6, unit: .reps, attribute: .strength, instruction: "Keep your body in one line and film from the side with feet visible. Lower, hold at depth for at least 2 seconds, then press to extended arms.", support: nil, tracking: .pausedPushup),
        .init(id: "widePushup", name: "Wide push-ups", family: .push, level: 4, goal: 6, unit: .reps, attribute: .strength, instruction: "Place your hands a little wider than your shoulders. Lower through a comfortable range and press back up. Camera counts elbow cycles; hand width is not checked.", support: nil, tracking: .widePushup),
        .init(id: "diamondPushup", name: "Diamond push-ups", family: .push, level: 5, goal: 5, unit: .reps, attribute: .strength, instruction: "Bring your hands close together under your chest in a comfortable diamond shape. Lower and press with control. Camera counts elbow cycles; hand placement is not checked.", support: nil, tracking: .diamondPushup),
        .init(id: "wallSit", name: "Wall sit", family: .legs, level: 1, goal: 20, unit: .seconds, attribute: .stamina, instruction: "Rest your back against a wall and slide to a comfortable seated height. Keep feet planted, breathe steadily, then stand. Keep your side visible; wall contact is not checked.", support: "Wall", tracking: .wallSit),
        .init(id: "calfRaise", name: "Supported calf raises", family: .legs, level: 1, goal: 12, unit: .reps, attribute: .strength, instruction: "Stand near a stable support. Rise onto the balls of both feet, then lower your heels with control. Count one rise and return as one rep.", support: "Stable support", tracking: .calfRaise),
        .init(id: "birdDog", name: "Bird dog", family: .core, level: 1, goal: 8, unit: .reps, attribute: .balance, instruction: "Start on hands and knees. Reach one arm and the opposite leg without twisting, then return and switch sides. Count each side as one rep.", support: nil, tracking: .birdDog),
        .init(id: "seatedKneeExtension", name: "Seated knee extensions", family: .legs, level: 1, goal: 10, unit: .reps, attribute: .mobility, instruction: "Sit on a stable chair with both feet down. Straighten one knee through a comfortable range, then lower the foot and alternate. Count each side as one rep.", support: "Stable chair", tracking: .seatedKneeExtension),
        .init(id: "quarterSquat", name: "Quarter squats", family: .legs, level: 1, goal: 10, unit: .reps, attribute: .strength, instruction: "Film from the side. Bend both knees a little, then stand tall.", support: nil, tracking: .quarterSquat),
        .init(id: "sitToStand", name: "Sit to stand", family: .legs, level: 1, goal: 8, unit: .reps, attribute: .strength, instruction: "Use a stable chair. Begin seated and rise with control, then sit to repeat. Film from the side; chair contact is not checked.", support: "Stable chair", tracking: .sitToStand),
        .init(id: "narrowSquat", name: "Narrow squats", family: .legs, level: 3, goal: 8, unit: .reps, attribute: .strength, instruction: "Use a comfortable narrow stance. Film from the side and lower then stand tall.", support: nil, tracking: .narrowSquat),
        .init(id: "tempoHalfSquat", name: "Tempo half squats", family: .legs, level: 2, goal: 6, unit: .reps, attribute: .strength, instruction: "Film from the side. Lower for at least 3 seconds to half depth, then stand tall.", support: nil, tracking: .tempoHalfSquat),
        .init(id: "pausedHalfSquat", name: "Paused half squats", family: .legs, level: 2, goal: 6, unit: .reps, attribute: .strength, instruction: "Film from the side. Lower to half depth, hold for 2 seconds, then stand tall.", support: nil, tracking: .pausedHalfSquat),
        .init(id: "forwardLunge", name: "Forward lunges", family: .legs, level: 3, goal: 8, unit: .reps, attribute: .balance, instruction: "Film from a three-quarter side view. Step forward, lower and return. Each complete side is one rep.", support: nil, tracking: .forwardLunge),
        .init(id: "lateralLunge", name: "Lateral lunges", family: .legs, level: 3, goal: 8, unit: .reps, attribute: .mobility, instruction: "Face the camera in a wide stance. Bend one knee while the other leg stays long, then return.", support: nil, tracking: .lateralLunge),
        .init(id: "supportedSplitSquat", name: "Supported split squats", family: .legs, level: 2, goal: 8, unit: .reps, attribute: .strength, instruction: "Use a stable support and split stance. Film from the side, lower and rise; change sides between sets.", support: "Stable support", tracking: .supportedSplitSquat),
        .init(id: "standingKneeRaise", name: "Standing knee raises", family: .legs, level: 1, goal: 10, unit: .reps, attribute: .balance, instruction: "Face the camera near a support. Lift one knee, lower fully and alternate.", support: "Optional nearby support", tracking: .standingKneeRaise),
        .init(id: "seatedMarch", name: "Seated marching", family: .legs, level: 1, goal: 10, unit: .reps, attribute: .mobility, instruction: "Sit tall on a stable chair. Film from a three-quarter view. Lift and lower alternate knees.", support: "Stable chair", tracking: .seatedMarch),
        .init(id: "standingHipAbduction", name: "Standing side leg raises", family: .legs, level: 2, goal: 10, unit: .reps, attribute: .strength, instruction: "Face the camera. Keep one leg straight while moving the other out sideways and returning.", support: "Optional nearby support", tracking: .standingHipAbduction),
        .init(id: "standingHipExtension", name: "Standing back leg raises", family: .legs, level: 2, goal: 10, unit: .reps, attribute: .strength, instruction: "Film from the side. Stay tall and move one straight leg behind you, then return.", support: "Optional nearby support", tracking: .standingHipExtension),
        .init(id: "kneePlank", name: "Knee forearm plank", family: .core, level: 1, goal: 15, unit: .seconds, attribute: .stamina, instruction: "Film from the side. Support on forearms and knees, with shoulders, hips and knees in a line.", support: nil, tracking: .kneePlank),
        .init(id: "highPlank", name: "High plank", family: .core, level: 3, goal: 20, unit: .seconds, attribute: .stamina, instruction: "Film from the side. Hold on extended arms and toes with shoulders, hips and ankles in a line.", support: nil, tracking: .highPlank),
        .init(id: "wallPlank", name: "Wall plank", family: .core, level: 1, goal: 20, unit: .seconds, attribute: .stamina, instruction: "Face a wall with extended arms. Film from the side and keep your body in a line. Wall contact is not checked.", support: "Wall", tracking: .wallPlank),
        .init(id: "kneeSidePlank", name: "Knee side plank", family: .core, level: 2, goal: 15, unit: .seconds, attribute: .balance, instruction: "Face the camera side-on along the floor. Support on one forearm and bent knees; lift your hips.", support: nil, tracking: .kneeSidePlank),
        .init(id: "tandemBalance", name: "Tandem balance", family: .balance, level: 2, goal: 20, unit: .seconds, attribute: .balance, instruction: "Film from the side. Place one foot directly ahead of the other, heel near toe. Stand tall near a support.", support: "Optional nearby support", tracking: .tandemBalance),
        .init(id: "frontArmRaise", name: "Front arm raises", family: .mobility, level: 1, goal: 10, unit: .reps, attribute: .mobility, instruction: "Film from the side. Lift a straight arm forward to shoulder height, then lower fully.", support: nil, tracking: .frontArmRaise),
        .init(id: "lateralArmRaise", name: "Side arm raises", family: .mobility, level: 2, goal: 10, unit: .reps, attribute: .mobility, instruction: "Face the camera. Raise a straight arm sideways to shoulder height, then lower fully.", support: nil, tracking: .lateralArmRaise),
        .init(id: "standingBicepsCurl", name: "Standing arm curls", family: .push, level: 2, goal: 10, unit: .reps, attribute: .strength, instruction: "Film from the side. Keep your upper arm by your torso, bend your elbow and straighten it. Load is not checked.", support: nil, tracking: .standingBicepsCurl),
        .init(id: "wallSlide", name: "Wall slides", family: .mobility, level: 2, goal: 8, unit: .reps, attribute: .mobility, instruction: "Face the camera with your back near a wall. Start with elbows bent at shoulder height, slide arms overhead, then return. Wall contact is not checked.", support: "Wall", tracking: .wallSlide)
    ]
    public static func find(_ id: String) -> ExerciseEntry? { all.first { $0.id == id } }
}

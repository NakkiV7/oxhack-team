import Foundation

public struct ExerciseDemonstrationGuide: Identifiable, Sendable {
    public enum CameraAngle: String, Sendable {
        case side, front, frontOblique
        public var instructions: String {
            switch self {
            case .side: return "Side view (90°). Point the camera across your body so your full profile stays visible."
            case .front: return "Front view (0°). Face the camera so both arms, legs and feet remain visible."
            case .frontOblique: return "Three-quarter view (about 45°). Place the camera between a front and side view so both sides of the movement are visible."
            }
        }
    }
    public let exerciseID: String
    public let name: String
    public let art: String
    public let cameraAngle: CameraAngle
    public let framing: String
    public let phases: [String]
    public let sideInstructions: String
    public let recordingInstructions: [String]
    public let requiresBothSides: Bool
    public let takeInstructions: String
    public let support: String?
    public var id: String { exerciseID }

    public static var all: [Self] { ExerciseCatalog.all.map(Self.init) }
    public static func find(_ exerciseID: String) -> Self? { all.first { $0.exerciseID == exerciseID } }

    private init(entry: ExerciseEntry) {
        exerciseID = entry.id; name = entry.name; art = entry.art
        support = entry.support
        takeInstructions = entry.unit == .reps
            ? "Record 3 complete, controlled repetitions from the starting position back to the starting position."
            : (entry.id == "highKnees"
                ? "Record 10–15 seconds of the alternating movement, including a clear start and finish."
                : "Record a 10–15 second steady hold, including how you enter the position and return to rest.")
        let front: Set<String> = ["stepJack", "highKnees", "singleLegBalance"]
        let oblique: Set<String> = ["closeGripPushup", "reverseLunge", "splitSquat", "assistedSquat", "deadBug", "sidePlank", "mountainClimber"]
        cameraAngle = front.contains(entry.id) ? .front : (oblique.contains(entry.id) ? .frontOblique : .side)
        let floor: Set<String> = ["kneePushup", "pushup", "closeGripPushup", "gluteBridge", "deadBug", "plank", "sidePlank", "mountainClimber", "catCow", "hipFlexorStretch"]
        framing = floor.contains(entry.id)
            ? "Use a low, steady camera angle that includes the floor contacts and your whole body, from head to hands and feet. Leave room for the full reach."
            : "Keep your whole body in frame, including your head, hands and feet. Leave space above your hands and behind your stepping leg."
        requiresBothSides = ["reverseLunge", "splitSquat", "assistedSquat", "deadBug", "sidePlank", "stepJack", "highKnees", "mountainClimber", "hipFlexorStretch", "singleLegBalance"].contains(entry.id)
        sideInstructions = requiresBothSides
            ? "Include both left and right sides. For alternating movements, show a complete cycle on each side; for single-side holds, record each side separately."
            : "Record one complete take with both hands and feet visible throughout the movement."
        phases = Self.phases(for: entry)
        recordingInstructions = [
            entry.instruction,
            "Keep the camera still. Record horizontally with even lighting and an uncluttered, contrasting background.",
            "Include two seconds before the movement and after returning to rest. Keep the original full frame for later editing."
        ]
    }

    private static func phases(for entry: ExerciseEntry) -> [String] {
        if entry.family == .push { return ["Show the extended-arm starting position", "Lower with control", "Press back to the starting position"] }
        switch entry.id {
        case "gluteBridge": return ["Show hips resting on the floor", "Lift the hips with control", "Lower back to the floor"]
        case "squat": return ["Stand tall", "Sit back and lower to a comfortable depth", "Return to standing"]
        case "reverseLunge": return ["Stand tall", "Step back and lower", "Return to standing and alternate sides"]
        case "splitSquat": return ["Show a stable split stance", "Lower in place", "Rise in place; repeat on the other side"]
        case "assistedSquat": return ["Show the support and single-leg stance", "Lower through a comfortable range", "Rise with the support visible; repeat on the other side"]
        case "deadBug": return ["Show the starting position on your back", "Extend opposite arm and leg", "Return and switch sides"]
        case "plank": return ["Set the forearms and toes", "Show a steady hold while breathing", "Return to rest"]
        case "sidePlank": return ["Set up on one forearm and the side of the feet", "Lift and show a steady hold", "Lower to rest and repeat on the other side"]
        case "stepJack": return ["Show the standing start", "Step out while lifting the arms", "Return and alternate sides"]
        case "highKnees": return ["Stand ready", "Show alternating knee lifts at a controlled pace", "Slow down and return to standing"]
        case "mountainClimber": return ["Show the high-plank start", "Bring one knee forward", "Return and alternate knees"]
        case "catCow": return ["Show the hands-and-knees start", "Gently round the back", "Lengthen the back and return through the full cycle"]
        case "hipFlexorStretch": return ["Show the half-kneeling setup", "Gently shift forward and hold comfortably", "Return and change sides"]
        case "singleLegBalance": return ["Stand near the support", "Lift one foot and show the balance hold", "Lower the foot and repeat on the other leg"]
        default: return ["Show the starting position", "Show the full movement", "Return to rest"]
        }
    }
}

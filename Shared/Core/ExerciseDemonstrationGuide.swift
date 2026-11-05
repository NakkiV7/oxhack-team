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
        cameraAngle = entry.tracking.flatMap { CameraAngle(rawValue: $0.cameraView.rawValue) } ?? .side
        let floor: Set<String> = ["kneePushup", "pushup", "closeGripPushup", "tempoPushup", "pausedPushup", "widePushup", "diamondPushup", "birdDog", "gluteBridge", "deadBug", "plank", "sidePlank", "mountainClimber", "catCow", "hipFlexorStretch", "kneePlank", "highPlank", "kneeSidePlank"]
        framing = floor.contains(entry.id)
            ? "Use a low, steady camera angle that includes the floor contacts and your whole body, from head to hands and feet. Leave room for the full reach."
            : "Keep your whole body in frame, including your head, hands and feet. Leave space above your hands and behind your stepping leg."
        requiresBothSides = entry.tracking?.tracksAlternatingLimbs == true || ["birdDog", "seatedKneeExtension", "reverseLunge", "splitSquat", "assistedSquat", "deadBug", "sidePlank", "stepJack", "highKnees", "mountainClimber", "hipFlexorStretch", "singleLegBalance", "kneeSidePlank", "supportedSplitSquat", "tandemBalance"].contains(entry.id)
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
        if entry.tracking?.minimumLoweringSeconds == 3 {
            return ["Show the standing or extended-arm start", "Lower for at least 3 seconds with all measured joints visible", "Return to the starting position"]
        }
        if entry.tracking?.minimumBottomHoldSeconds == 2 {
            return ["Show the standing or extended-arm start", "Lower to depth and hold for at least 2 seconds", "Return to the starting position"]
        }
        if entry.tracking?.isSquat == true {
            return entry.id == "sitToStand" ? ["Sit on the stable chair with feet planted", "Stand up with control", "Sit back down comfortably"] : ["Stand tall with feet planted", "Lower to the comfortable depth for this variation", "Return to standing"]
        }
        if entry.tracking?.isPushup == true { return ["Show the extended-arm starting position", "Lower with control", "Press back to the starting position"] }
        switch entry.id {
        case "frontArmRaise": return ["Stand with arms lowered", "Raise a straight arm forward to shoulder height", "Lower and repeat on the other side"]
        case "lateralArmRaise": return ["Stand with arms lowered", "Raise a straight arm out to the side", "Lower and repeat on the other side"]
        case "standingBicepsCurl": return ["Stand with upper arms beside your torso", "Bend the elbow with control", "Straighten the elbow and repeat on the other side"]
        case "wallSlide": return ["Stand by the wall with elbows bent and hands raised", "Slide both arms upward comfortably", "Return to the bent-elbow position"]
        case "seatedMarch": return ["Sit tall on a stable chair", "Lift one bent knee", "Lower and alternate knees"]
        case "standingKneeRaise": return ["Stand tall with both feet planted", "Lift one bent knee", "Lower and alternate knees"]
        case "standingHipAbduction": return ["Stand tall near your stable support", "Move a straight leg out to the side", "Return and repeat on the other side"]
        case "standingHipExtension": return ["Stand tall near your stable support", "Move a straight leg behind you without leaning", "Return and repeat on the other side"]
        case "forwardLunge": return ["Stand tall", "Step forward and bend the front knee", "Return and alternate sides"]
        case "lateralLunge": return ["Stand with a wide stance", "Bend one knee while the other leg stays straight", "Return and repeat on the other side"]
        case "supportedSplitSquat": return ["Set a split stance beside stable support", "Bend the front knee with control", "Rise in place and repeat on the other side"]
        case "kneePlank": return ["Set forearms and bent knees on the floor", "Hold a long shoulder-to-knee line while breathing", "Return to rest"]
        case "highPlank": return ["Set hands and toes with arms straight", "Hold a long body line while breathing", "Return to rest"]
        case "wallPlank": return ["Place hands against a stable wall", "Keep arms straight and hold a comfortable body line", "Step back to rest"]
        case "kneeSidePlank": return ["Set one forearm and bent knees on the floor", "Lift the hips and hold while breathing", "Lower and repeat on the other side"]
        case "tandemBalance": return ["Stand beside support", "Place one foot directly in front of the other and hold", "Step apart and change the leading foot"]
        case "wallSit": return ["Show your back against the wall and feet planted", "Slide to a comfortable height and hold while breathing", "Slide up and return to standing"]
        case "calfRaise": return ["Stand with your support visible", "Raise both heels with control", "Lower both heels to the floor"]
        case "birdDog": return ["Show the hands-and-knees start", "Reach opposite arm and leg without twisting", "Return and show the other side"]
        case "seatedKneeExtension": return ["Sit on the chair with feet planted", "Straighten one knee through a comfortable range", "Lower the foot and show the other side"]
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

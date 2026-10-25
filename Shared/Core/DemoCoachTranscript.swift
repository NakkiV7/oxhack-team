import Foundation

public enum DemoCoachTranscript {
    public enum DayKind: String, Sendable { case strength = "Strength", mobility = "Mobility", recovery = "Recovery", rest = "Rest" }
    public struct Day: Identifiable, Sendable {
        public let id: String
        public let title: String
        public let kind: DayKind
        public let note: String
        public let exerciseIDs: [String]
    }

    public static let days: [Day] = [
        .init(id: "monday", title: "Monday", kind: .strength, note: "An easy full-body restart. Leave a few comfortable reps in reserve.", exerciseIDs: ["wallPushup", "gluteBridge", "deadBug"]),
        .init(id: "tuesday", title: "Tuesday", kind: .mobility, note: "Move gently through a comfortable range. Do not force a stretch.", exerciseIDs: ["catCow", "hipFlexorStretch"]),
        .init(id: "wednesday", title: "Wednesday", kind: .rest, note: "Rest from planned training. Let recovery set the pace.", exerciseIDs: []),
        .init(id: "thursday", title: "Thursday", kind: .strength, note: "Repeat the easy push and core work; introduce a comfortable squat depth.", exerciseIDs: ["wallPushup", "squat", "deadBug"]),
        .init(id: "friday", title: "Friday", kind: .mobility, note: "A short mobility reset, with the stretch optional.", exerciseIDs: ["catCow", "hipFlexorStretch"]),
        .init(id: "saturday", title: "Saturday", kind: .recovery, note: "Optional gentle movement. An easy walk can replace this; no need to log it.", exerciseIDs: ["stepJack"]),
        .init(id: "sunday", title: "Sunday", kind: .rest, note: "Rest and reflect on comfort and consistency before next week.", exerciseIDs: [])
    ]
    public static let defaultSelection: Set<String> = ["wallPushup", "gluteBridge", "deadBug", "catCow", "squat", "stepJack"]

    public static func requiredSupport(selected: Set<String>) -> Set<String> {
        Set(selected.compactMap { ExerciseCatalog.find($0)?.support })
    }

    public static func target(exerciseID: String) -> Int {
        switch exerciseID {
        case "deadBug", "catCow": return 6
        case "hipFlexorStretch": return 15
        case "stepJack": return 10
        default: return 5
        }
    }

    public static func plan(dayID: String, selected: Set<String>, support: Set<String>) throws -> CoachSavedPlan {
        let offered = Set(days.flatMap(\.exerciseIDs))
        guard selected.isSubset(of: offered), let day = days.first(where: { $0.id == dayID }) else {
            throw CoachContractError.selectionRequired
        }
        let ids = day.exerciseIDs.filter { selected.contains($0) }
        guard !ids.isEmpty else { throw CoachContractError.selectionRequired }
        let items: [[String: Any]] = try ids.map { id in
            guard let entry = ExerciseCatalog.find(id) else { throw CoachContractError.invalidProposal }
            return ["exerciseID": id, "sets": 1, "target": target(exerciseID: id), "unit": entry.unit.rawValue,
                    "restSeconds": 60, "factIDs": ["preview-restart"]]
        }
        let payload: [String: Any] = ["generationID": "preview-restart", "items": items,
            "rationale": ["text": "A prewritten sample restart session. Keep the effort comfortable and review before progressing.", "factIDs": ["preview-restart"]]]
        let context = CoachValidationContext(generationID: "preview-restart", suppliedFactIDs: ["preview-restart"], availableSupport: support)
        let proposal = try CoachContracts.parseProposal(JSONSerialization.data(withJSONObject: payload), context: context)
        return try CoachSavedPlan(proposal: proposal, selectedExerciseIDs: Set(ids), context: context)
    }
}

import Foundation

public enum CoachGrounding {
    public static func facts(history: [SessionRecord]) -> [CoachFact] {
        var seen = Set<UUID>()
        let unique = history.sorted { $0.date > $1.date }.filter { seen.insert($0.id).inserted }
        let recent = Array(unique.prefix(8))
        let progress = SkillProgress.evaluate(history: unique)
        let context = CoachFact(id: "context", text: "\(unique.count) saved sessions in local history. This request shares up to 8 recent sessions. Manual entries are self-reported; video entries are replay observations. No health status, recovery, calorie burn or fitness score is established. No heart-rate or motion data is shared in this request.")
        let sessions = recent.flatMap { session -> [CoachFact] in
            let report = WorkoutReport(record: session)
            let sessionFact = CoachFact(id: "session-\(session.id.uuidString)", text: "Session \(session.date.ISO8601Format()): \(report.setCount) sets, \(report.reps) reps, \(Int(report.holdSeconds)) seconds of holds, \(Int(report.activeSeconds)) recorded active seconds.")
            let sets = report.sets.prefix(8).map { set in
                CoachFact(id: "set-\(set.id.uuidString)", text: "\(set.exerciseName): \(set.quantityText); source \(set.source.rawValue); stop reason: \(set.reason.title)." + (set.reserve.map { " Self-reported reps in reserve: \($0)." } ?? " Reps in reserve not supplied."))
            }
            return [sessionFact] + sets
        }
        let skills = TrainingAttribute.allCases.map { attribute in
            CoachFact(id: "skill-\(attribute.rawValue)", text: "\(attribute.title): \(progress.points(for: attribute)) game points from goal-meeting recorded sets. Game points are not a physical capability measurement.")
        }
        let nodes = progress.nodes.filter { $0.isComplete }.prefix(19).map {
            CoachFact(id: "node-\($0.exerciseID)", text: "\($0.exerciseID) challenge completed: \($0.qualifyingSets) qualifying sets across \($0.trainingDays) training days, including \($0.manualSets) manual and \($0.cameraSets) camera sets.")
        }
        var factIDs = Set<String>()
        return ([context] + sessions + skills + nodes).filter { factIDs.insert($0.id).inserted }
    }
}

public struct CoachSavedPlan: Codable, Sendable {
    public struct Item: Codable, Sendable, Identifiable {
        public var id: String { exerciseID }
        public let exerciseID: String
        public let sets: Int
        public let target: Int
        public let unit: ExerciseEntry.Unit
        public let restSeconds: Int
    }
    public let items: [Item]
    public let approvedAt: Date
    public let rationale: String
    public init(proposal: WorkoutProposal, selectedExerciseIDs: Set<String>, context: CoachValidationContext, approvedAt: Date = Date()) throws {
        items = try CoachContracts.approvedItems(from: proposal, selectedExerciseIDs: selectedExerciseIDs, context: context).map {
            Item(exerciseID: $0.exerciseID, sets: $0.sets, target: $0.target, unit: $0.unit, restSeconds: $0.restSeconds)
        }
        self.approvedAt = approvedAt; rationale = proposal.rationale.text
    }
}

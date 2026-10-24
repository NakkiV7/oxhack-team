import Foundation

public enum CoachGrounding {
    public static func facts(history: [SessionRecord]) -> [CoachFact] {
        var seen = Set<UUID>()
        let unique = history.filter { $0.date.timeIntervalSince1970.isFinite }
            .sorted { $0.date > $1.date }.filter { seen.insert($0.id).inserted }
        let reports = unique.map(WorkoutReport.init)
        let progress = SkillProgress.evaluate(history: unique)
        let context = CoachFact(id: "context", text: "\(unique.count) saved sessions in supplied history scope. Scope totals include every supplied session; detailed facts cover up to 8 recent sessions and 8 sets each. Manual entries are self-reported; camera entries are CV observations; video entries are replay observations. Only recorded Watch summaries are shared. Raw sensor streams are not shared. No health status, recovery, calorie burn or fitness score is established. Wrist motion does not establish exercise form.")
        let sessions = reports.prefix(8).flatMap(sessionFacts)
        let skills = TrainingAttribute.allCases.map { attribute in
            CoachFact(id: "skill-\(attribute.rawValue)", text: "\(attribute.title): \(progress.points(for: attribute)) game points from goal-meeting recorded sets. Game points are not a physical capability measurement.")
        }
        let nodes = progress.nodes.filter { $0.isComplete }.prefix(19).map {
            CoachFact(id: "node-\($0.exerciseID)", text: "\($0.exerciseID) challenge completed: \($0.qualifyingSets) qualifying sets across \($0.trainingDays) training days, including \($0.manualSets) manual and \($0.cameraSets) camera sets.")
        }
        var factIDs = Set<String>()
        return ([context, scopeTotals(reports)] + scopeSignals(reports) + sessions + skills + nodes)
            .filter { factIDs.insert($0.id).inserted }
    }

    private static func sessionFacts(_ report: WorkoutReport) -> [CoachFact] {
        let timing = timingText(mean: report.averageRepSeconds, count: report.timedRepCount, rest: report.recordedRestSeconds)
        let sources = Set(report.sets.map { $0.source.rawValue }).sorted().joined(separator: ", ")
        let session = CoachFact(id: "session-\(report.id.uuidString)", text: "Session date \(report.date.ISO8601Format()) (UTC): \(report.setCount) sets, \(report.reps) reps, \(number(report.holdSeconds)) seconds of holds, \(number(report.activeSeconds)) recorded active seconds. Sources: \(sources.isEmpty ? "none" : sources). \(timing)")
        let sets = report.sets.prefix(8).map { set in
            let rest = set.restSecondsBefore.map { " Recorded rest before this set: \(number($0)) seconds." } ?? " Rest before this set not recorded."
            let tempo = set.averageRepSeconds.map { " Recorded rep mean \(number($0)) seconds across \(set.repDurations.count) timed reps." } ?? " Rep timing not recorded."
            return CoachFact(id: "set-\(set.id.uuidString)", text: "Session date \(report.date.ISO8601Format()); \(set.exerciseName): \(set.quantityText); source \(set.source.rawValue); \(number(set.activeSeconds)) recorded active seconds; stop reason: \(set.reason.title)." + (set.reserve.map { " Self-reported reps in reserve: \($0)." } ?? " Reps in reserve not supplied.") + tempo + rest)
        }
        return [session] + sets + signals(prefix: "watch", suffix: report.id.uuidString, reports: [report])
    }

    private static func scopeTotals(_ reports: [WorkoutReport]) -> CoachFact {
        var setIDs = Set<UUID>()
        let sets = reports.flatMap(\.sets).filter { setIDs.insert($0.id).inserted }
        let days = Set(reports.map { String($0.date.ISO8601Format().prefix(10)) }).sorted()
        let range = reports.last.flatMap { first in reports.first.map { last in "Session dates from \(first.date.ISO8601Format()) through \(last.date.ISO8601Format())." } } ?? "No recorded session dates."
        let durations = sets.flatMap(\.repDurations)
        let rests = sets.compactMap(\.restSecondsBefore)
        let timing = timingText(mean: durations.isEmpty ? nil : durations.reduce(0, +) / Double(durations.count), count: durations.count, rest: rests.isEmpty ? nil : rests.reduce(0, +))
        let sources = [InputSource.manual, .camera, .video].map { source in "\(sets.filter { $0.source == source }.count) \(source.rawValue)" }.joined(separator: ", ")
        return CoachFact(id: "scope-totals", text: "Complete supplied history scope: \(reports.count) sessions, \(sets.count) distinct sets, \(sets.reduce(0) { $0 + $1.reps }) reps, \(number(sets.reduce(0) { $0 + $1.holdSeconds })) seconds of holds, \(number(sets.reduce(0) { $0 + $1.activeSeconds })) recorded active seconds. Set sources: \(sources). \(days.count) UTC session days. \(range) \(timing)")
    }

    private static func scopeSignals(_ reports: [WorkoutReport]) -> [CoachFact] {
        signals(prefix: "scope", suffix: "watch", reports: reports)
    }

    private static func signals(prefix: String, suffix: String, reports: [WorkoutReport]) -> [CoachFact] {
        let kinds: [(String, String, KeyPath<WorkoutReport, ReportSignal>)] = [
            ("heartRate", "bpm", \.heartRate), ("acceleration", "g", \.acceleration), ("rotation", "rad/s", \.rotation)
        ]
        return kinds.compactMap { kind, unit, key in
            let observed = reports.reduce(into: [Date: (sample: ReportSample, coverage: Set<String>)]()) { readings, report in
                for sample in report[keyPath: key].samples {
                    let previous = readings[sample.date]
                    let coverage = "\(report.id.uuidString):\(sample.segment)"
                    readings[sample.date] = (previous?.sample ?? sample, (previous?.coverage ?? []).union([coverage]))
                }
            }.values.sorted { $0.sample.date < $1.sample.date }
            guard let first = observed.first, let last = observed.last else { return nil }
            let mean = observed.reduce(0) { $0 + $1.sample.value / Double(observed.count) }
            let peak = observed.map { $0.sample.value }.max() ?? first.sample.value
            let segments = zip(observed, observed.dropFirst()).reduce(1) { count, pair in
                let gap = pair.1.sample.date.timeIntervalSince(pair.0.sample.date) > 12
                return count + (gap || pair.0.coverage.isDisjoint(with: pair.1.coverage) ? 1 : 0)
            }
            let label = kind == "heartRate" ? "Watch heart rate" : "Watch wrist \(kind) magnitude"
            return CoachFact(id: "\(prefix)-\(kind)-\(suffix)", text: "\(label): \(observed.count) distinct readings, mean \(number(mean)) \(unit), peak \(number(peak)) \(unit). Observed timestamps \(first.sample.date.ISO8601Format()) through \(last.sample.date.ISO8601Format()); \(segments) observed segments. Gaps over 12 seconds and intervals between sessions are not filled. Means weight each recorded reading once; no continuous coverage is implied.")
        }
    }

    private static func timingText(mean: Double?, count: Int, rest: Double?) -> String {
        let tempo = mean.map { "Recorded rep mean \(number($0)) seconds across \(count) timed reps." } ?? "Rep timing not recorded."
        let restText = rest.map { "\(number($0)) recorded rest seconds from known intervals only." } ?? "Rest timing not recorded."
        return tempo + " " + restText
    }

    private static func number(_ value: Double) -> String {
        String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
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

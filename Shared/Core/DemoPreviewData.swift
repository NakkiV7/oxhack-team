import Foundation

public struct DemoPreviewBiometrics: Equatable, Sendable {
    public let presagePulse: Double
    public let presageBreathing: Double
    public let effortBand: String
    public let rationale: String
    public let sourceLabel = "Synthetic preview · not recorded health data"
}

public struct DemoPreviewReportMetrics: Equatable, Sendable {
    public let exampleRecord: SessionRecord
    public let angleSamples: [SensorReading]
    public let sourceLabel = "Synthetic preview · not recorded health data"
}

public struct DemoPreviewInsight: Equatable, Sendable {
    public let sessionID: UUID
    public let title: String
    public let summary: String
    public let grade: String
    public let score: Int
    public let rationale: String
    public let achievementScore: Int
    public let effortScore: Int
    public let biometrics: DemoPreviewBiometrics
    public let sourceLabel = "Synthetic preview"
}

public enum DemoPreviewData {
    public static var profile: LocalProfile {
        try! LocalProfile(name: "Demo Alex", weeklyTarget: 4, goals: [.strength, .mobility], baselineAbility: .somePractice)
    }

    public static func sessions(referenceDate: Date, calendar: Calendar = .current) -> [SessionRecord] {
        guard referenceDate.timeIntervalSince1970.isFinite else { return [] }
        return workouts.enumerated().compactMap { index, workout in
            guard let date = calendar.date(byAdding: .day, value: index - 6, to: referenceDate) else { return nil }
            return record(workout, index: index, date: date)
        }
    }

    public static func enrichedRecord(_ record: SessionRecord) -> SessionRecord? {
        guard record.date.timeIntervalSince1970.isFinite,
              let index = workouts.indices.first(where: { identifier(session: $0) == record.id }) else { return nil }
        let enriched = self.record(workouts[index], index: index, date: record.date)
        guard record == enriched || record == self.record(workouts[index], index: index, date: record.date, includeTelemetry: false) else { return nil }
        return enriched
    }

    public static func reportMetrics(for record: SessionRecord, previewEnabled: Bool) -> DemoPreviewReportMetrics? {
        guard previewEnabled, record.date.timeIntervalSince1970.isFinite,
              record.sets.contains(where: { $0.reps > 0 }) || record.loggedSets.contains(where: { $0.reps > 0 || $0.seconds > 0 }) else { return nil }
        let template = self.record(workouts[0], index: 0, date: record.date)
        let telemetry = template.telemetry.map { sample in
            WatchTelemetry(sessionID: record.id, sentAt: sample.sentAt, heartRate: sample.heartRate,
                accelerationG: sample.accelerationG, rotationRadiansPerSecond: sample.rotationRadiansPerSecond,
                activeEnergy: sample.activeEnergy.map { .init(recordingID: record.id, kilocalories: $0.kilocalories, asOf: $0.asOf) })
        }
        let example = SessionRecord(id: record.id, date: record.date, sets: record.sets,
                                    telemetry: telemetry, loggedSets: record.loggedSets, skippedSets: record.skippedSets)
        let angles: [Double] = [170, 145, 105, 90, 120, 160, 170, 130, 95, 110, 150, 170]
        return .init(exampleRecord: example, angleSamples: angles.enumerated().map {
            .init(value: $0.element, date: record.date.addingTimeInterval(Double($0.offset) * 5))
        })
    }

    public static func insight(for record: SessionRecord) -> DemoPreviewInsight? {
        guard record.date.timeIntervalSince1970.isFinite,
              let index = workouts.indices.first(where: { identifier(session: $0) == record.id }),
              record == self.record(workouts[index], index: index, date: record.date) ||
                record == self.record(workouts[index], index: index, date: record.date, includeTelemetry: false) else { return nil }
        let workout = workouts[index]
        let quantities = workout.groups.flatMap { group in
            group.counts.map { min(1, Double($0) / Double(group.target)) }
        }
        let achievement = Int((quantities.reduce(0, +) / Double(quantities.count) * 100).rounded())
        let score = (achievement + workout.effort) / 2
        let report = WorkoutReport(record: record)
        let hold = report.holdSeconds > 0 ? ", \(Int(report.holdSeconds)) sec of holds" : ""
        return DemoPreviewInsight(sessionID: record.id, title: workout.title,
            summary: "Synthetic session: \(record.setCount) sets, \(record.reps) reps\(hold). \(workout.reflection)",
            grade: grade(score), score: score,
            rationale: "Demo achievement \(achievement)/100 is the mean completed share of each set target, capped at 100. Demo effort \(workout.effort)/100 is authored for this fictional session. The score averages these two values; it is not a health, readiness or measured effort assessment.",
            achievementScore: achievement, effortScore: workout.effort,
            biometrics: .init(presagePulse: [82, 88, 72, 94, 78, 102, 98][index],
                presageBreathing: [16, 18, 13, 20, 15, 23, 21][index],
                effortBand: workout.effort >= 80 ? "Higher effort" : "Lower effort",
                rationale: "These authored Watch signals and stationary Presage-style pulse/breathing examples are not measured health data. Lower/higher effort describes the fictional workout narrative, not a physiological assessment; no readiness or fitness conclusion follows."))
    }

    private struct Group {
        let exerciseID: String
        let counts: [Int]
        let target: Int
        let source: InputSource
        var isHold: Bool { ExerciseCatalog.find(exerciseID)?.unit == .seconds }
    }
    private struct Workout {
        let title: String
        let reflection: String
        let effort: Int
        let groups: [Group]
    }
    private static let workouts: [Workout] = [
        .init(title: "A starting point", reflection: "Short push-up and squat sets leave room to build toward the demo targets.", effort: 64,
              groups: [camera("pushup", [3, 3, 3], 10), camera("squat", [5, 5, 5], 12)]),
        .init(title: "Finding repeatable sets", reflection: "The sample counts rise while the final sets remain below target.", effort: 73,
              groups: [camera("pushup", [5, 5, 4], 10), camera("squat", [7, 7, 6], 12)]),
        .init(title: "A deliberate mobility day", reflection: "Cat-cow cycles and hip-flexor holds are manual self-reports; no camera form assessment is implied.", effort: 74,
              groups: [manual("catCow", [4, 4, 4], 6), manual("hipFlexorStretch", [20, 20], 30)]),
        .init(title: "Building the main movements", reflection: "More of the planned push-up and squat repetitions are completed in this fictional workout.", effort: 83,
              groups: [camera("pushup", [7, 7, 6], 10), camera("squat", [10, 10, 9], 12)]),
        .init(title: "Complete the foundations", reflection: "Wall push-ups, glute bridges and cat-cow reach their sample targets through manual logging.", effort: 68,
              groups: [manual("wallPushup", [8, 8, 8], 8), manual("gluteBridge", [12, 12, 12], 12), manual("catCow", [6, 6, 6], 6)]),
        .init(title: "One rep from the plan", reflection: "All squat targets are reached; the final push-up set is one repetition short.", effort: 90,
              groups: [camera("pushup", [10, 10, 9], 10), camera("squat", [12, 12, 12], 12)]),
        .init(title: "A complete sample session", reflection: "All authored strength and mobility targets are reached. Camera counts and manual mobility logs remain distinct.", effort: 98,
              groups: [camera("pushup", [10, 10, 10], 10), camera("squat", [12, 12, 12], 12),
                       manual("catCow", [6, 6, 6], 6), manual("hipFlexorStretch", [30, 30], 30)])
    ]

    private static func camera(_ id: String, _ counts: [Int], _ target: Int) -> Group {
        Group(exerciseID: id, counts: counts, target: target, source: .camera)
    }
    private static func manual(_ id: String, _ counts: [Int], _ target: Int) -> Group {
        Group(exerciseID: id, counts: counts, target: target, source: .manual)
    }
    private static func identifier(session: Int, set: Int = 0) -> UUID {
        UUID(uuidString: String(format: "DE000000-0000-4000-A000-%012d", (session + 1) * 100 + set))!
    }
    private static func record(_ workout: Workout, index: Int, date: Date, includeTelemetry: Bool = true) -> SessionRecord {
        let groups = workout.groups.enumerated().flatMap { groupIndex, group in
            group.counts.enumerated().map { number, count in
                (group, number, count, identifier(session: index, set: groupIndex * 10 + number + 1))
            }
        }
        let sets = groups.compactMap { group, number, count, id -> SetRecord? in
            guard group.source == .camera, let exercise = Exercise(rawValue: group.exerciseID) else { return nil }
            return SetRecord(id: id, exercise: exercise, number: number + 1, reps: count, target: group.target,
                activeSeconds: Double(count) * 2.5 + 2, source: .camera, reserve: 2,
                reason: count >= group.target ? .target : .voluntary,
                repDurations: Array(repeating: 2.5, count: count), restSecondsBefore: number == 0 ? nil : 60)
        }
        let logs = groups.compactMap { group, number, count, id -> LoggedSet? in
            guard group.source == .manual else { return nil }
            return LoggedSet(id: id, exerciseID: group.exerciseID, reps: group.isHold ? 0 : count,
                seconds: group.isHold ? Double(count) : 0, source: .manual,
                reason: count >= group.target ? .target : .voluntary, number: number + 1, target: group.target,
                activeSeconds: Double(count) * (group.isHold ? 1 : 3),
                restSecondsBefore: number == 0 ? nil : 45, reserve: nil, quantityOrigin: .selfReport)
        }
        let sessionID = identifier(session: index)
        let active = sets.reduce(0) { $0 + $1.activeSeconds } + logs.reduce(0) { $0 + ($1.activeSeconds ?? $1.seconds) }
        let levels: [Double] = [0, 6, 16, 24, 32, 20, 10, 30, 38, 22, 10, 0]
        let base: Double = [88, 94, 76, 104, 86, 112, 108][index]
        let telemetry: [WatchTelemetry] = includeTelemetry ? levels.enumerated().map { number, level in
            let observed = date.addingTimeInterval(Double(number) * 5)
            return WatchTelemetry(sessionID: sessionID, sentAt: observed,
                heartRate: .init(value: base + level, date: observed),
                accelerationG: .init(value: 1 + level / 100, date: observed),
                rotationRadiansPerSecond: .init(value: 0.1 + level / 30, date: observed),
                activeEnergy: .init(recordingID: sessionID, kilocalories: active / 60 * 3.5 * Double(number) / 11, asOf: observed))
        } : []
        return SessionRecord(id: sessionID, date: date, sets: sets, telemetry: telemetry, loggedSets: logs)
    }
    private static func grade(_ score: Int) -> String {
        switch score {
        case 97...: return "A+"
        case 93...: return "A"
        case 90...: return "A-"
        case 87...: return "B+"
        case 83...: return "B"
        case 80...: return "B-"
        case 77...: return "C+"
        case 73...: return "C"
        case 70...: return "C-"
        case 67...: return "D+"
        case 63...: return "D"
        default: return "D-"
        }
    }
}

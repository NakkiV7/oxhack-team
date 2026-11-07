import Foundation

public enum AnalyticsKind: String, Codable, CaseIterable, Sendable { case usage, workout }
public struct AnalyticsCapture: Codable, Equatable, Sendable {
    public let owner: WorkoutOwner
    public let age: TrainingAgeContext
    public let epoch: UUID
}
public struct CoarseAnalyticsSnapshot: Codable, Equatable, Sendable {
    public var version = 1
    public let kind: AnalyticsKind
    public let week: String
    public var tag: UUID
    public var sequence: Int
    public var counts: [String: Int]
}
public struct AnalyticsLedger: Codable, Sendable {
    public let owner: WorkoutOwner
    public let age: TrainingAgeContext?
    public private(set) var usage = false
    public private(set) var workout = false
    public private(set) var usageEpoch = UUID()
    public private(set) var workoutEpoch = UUID()
    public private(set) var snapshots: [CoarseAnalyticsSnapshot] = []
    private var seen: [String: [UUID]] = [:]
    public init(owner: WorkoutOwner, age: TrainingAgeContext?) { self.owner = owner; self.age = age }
    public mutating func consent(_ kind: AnalyticsKind, enabled: Bool) {
        let allowed = enabled && age?.allowsTimePressureRewards == true
        guard (kind == .usage ? usage : workout) != allowed else { return }
        if kind == .usage { usage = allowed; usageEpoch = UUID() }
        else { workout = allowed; workoutEpoch = UUID() }
        snapshots.removeAll { $0.kind == kind }
    }
    public func capture(_ kind: AnalyticsKind) -> AnalyticsCapture? {
        guard let age, age.allowsTimePressureRewards, kind == .usage ? usage : workout else { return nil }
        return .init(owner: owner, age: age, epoch: kind == .usage ? usageEpoch : workoutEpoch)
    }
    private func permits(_ captured: AnalyticsCapture?, kind: AnalyticsKind, currentAge: TrainingAgeContext?) -> Bool {
        captured != nil && capture(kind) == captured && age == currentAge
    }
    public static func week(_ date: Date) -> String {
        var calendar = Calendar(identifier: .iso8601); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.dateInterval(of: .weekOfYear, for: date)!.start
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = calendar.timeZone; formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: start)
    }
    private mutating func add(_ counts: [String: Int], kind: AnalyticsKind, at date: Date) {
        let week = Self.week(date), previous = Self.week(date.addingTimeInterval(-7 * 86400))
        snapshots.removeAll { $0.week != week && $0.week != previous }
        seen = seen.filter { $0.key == week || $0.key == previous }
        let index: Int
        if let existing = snapshots.firstIndex(where: { $0.week == week && $0.kind == kind }) { index = existing }
        else { snapshots.append(.init(kind: kind, week: week, tag: UUID(), sequence: 1, counts: [:])); index = snapshots.count - 1 }
        for (key, value) in counts {
            let maximum = key == "reps" ? 20000 : key == "minutes" ? 10000 : 2000
            snapshots[index].counts[key] = min(maximum, (snapshots[index].counts[key] ?? 0) + max(0, value))
        }
    }
    public mutating func record(_ record: SessionRecord, captured: AnalyticsCapture?, currentAge: TrainingAgeContext?, at date: Date) {
        guard date.timeIntervalSince1970.isFinite, permits(captured, kind: .workout, currentAge: currentAge),
              record.trainingContext?.owner == owner, record.trainingContext?.age == age,
              record.trainingContext?.allowsAdultCompletion == true, let ended = record.endedAt,
              ended <= date, date.timeIntervalSince(ended) <= 7 * 86400 else { return }
        let week = Self.week(ended)
        guard !(seen[week] ?? []).contains(record.id), (seen[week]?.count ?? 0) < 256 else { return }
        let sets = record.loggedSets.filter { $0.source != .video }
        let legacy = record.sets.filter { $0.source != .video }
        guard !sets.isEmpty || !legacy.isEmpty else { return }
        let reps = sets.reduce(0) { $0 + min(2000, max(0, $1.reps)) } + legacy.reduce(0) { $0 + min(2000, max(0, $1.reps)) }
        let seconds = sets.reduce(0.0) { $0 + ($1.activeSeconds ?? $1.seconds) } + legacy.reduce(0.0) { $0 + $1.activeSeconds }
        guard seconds.isFinite, seconds >= 0 else { return }
        var counts = ["sessions": 1, "sets": sets.count + legacy.count, "reps": reps / 10 * 10, "minutes": Int(min(600000, seconds)) / 300 * 5]
        let familyNames: [ExerciseFamily: String] = [.legs: "squat", .push: "push", .core: "core", .conditioning: "cardio", .mobility: "mobility", .balance: "balance"]
        for id in sets.map(\.exerciseID) + legacy.map({ $0.exercise.rawValue }) {
            if let family = ExerciseCatalog.find(id)?.family, let name = familyNames[family] { counts[name, default: 0] += 1 }
        }
        for source in sets.map(\.source) + legacy.map(\.source) { counts[record.trainingContext?.recordingDevice == .watch ? "watch" : source == .camera ? "camera" : "manual", default: 0] += 1 }
        for effort in sets.compactMap(\.effort) { counts[effort.rawValue <= 4 ? "effortEasy" : effort.rawValue <= 6 ? "effortModerate" : "effortHard", default: 0] += 1 }
        add(counts, kind: .workout, at: ended)
        seen[week, default: []].append(record.id)
    }
    public mutating func feature(_ name: String, captured: AnalyticsCapture?, currentAge: TrainingAgeContext?, at date: Date) {
        guard date.timeIntervalSince1970.isFinite, permits(captured, kind: .usage, currentAge: currentAge),
              ["today", "programme", "practice", "insights", "coach", "quests"].contains(name) else { return }
        add([name: 1], kind: .usage, at: date)
    }
}

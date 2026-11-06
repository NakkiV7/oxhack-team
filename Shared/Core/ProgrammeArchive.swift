import Foundation

public struct ProgrammeArchive: Codable, Equatable, Sendable {
    public let owner: WorkoutOwner
    public private(set) var snapshots: [TrainingProgramme] = []
    private var ages: [String: TrainingAgeContext] = [:]
    private struct Inputs: Codable, Equatable, Sendable {
        let preferences: ProgrammePreferences
        let comfortableExercises: Set<String>
        init(_ profile: LocalProfile) { preferences = profile.effectiveProgrammePreferences; comfortableExercises = profile.comfortableExercises }
    }
    private var inputs: [String: Inputs]?
    private mutating func remember(_ profile: LocalProfile, for week: TrainingProgramme) {
        let key = "\(week.id)#\(week.revision)"
        ages[key] = profile.effectiveProgrammePreferences.ageContext
        if inputs == nil { inputs = [:] }
        inputs?[key] = Inputs(profile)
    }
    @discardableResult public mutating func reconcile(profile: LocalProfile, history: [SessionRecord], protecting: Set<String>, at date: Date, calendar: Calendar = .current) throws -> TrainingProgramme {
        guard let existing = week(at: date, calendar: calendar), ages["\(existing.id)#\(existing.revision)"] == profile.effectiveProgrammePreferences.ageContext else {
            return try prepare(profile: profile, history: history, at: date, calendar: calendar)
        }
        if inputs?["\(existing.id)#\(existing.revision)"] == Inputs(profile) { return existing }
        return try revise(profile: profile, history: history, protecting: protecting, at: date, calendar: calendar)
    }
    public func age(for week: TrainingProgramme) -> TrainingAgeContext? { ages["\(week.id)#\(week.revision)"] }
    public var currentAge: TrainingAgeContext? { current.flatMap { ages["\($0.id)#\($0.revision)"] } }
    public init(owner: WorkoutOwner) { self.owner = owner }
    public var current: TrainingProgramme? { snapshots.last }

    public func week(at date: Date, calendar: Calendar = .current) -> TrainingProgramme? {
        snapshots.last { week in
            week.timeZoneID == calendar.timeZone.identifier && week.days.contains { calendar.isDate($0.date, inSameDayAs: date) }
        }
    }
    @discardableResult public mutating func prepare(profile: LocalProfile, history: [SessionRecord], at date: Date, calendar: Calendar = .current) throws -> TrainingProgramme {
        if let existing = week(at: date, calendar: calendar), ages["\(existing.id)#\(existing.revision)"] == profile.effectiveProgrammePreferences.ageContext { return existing }
        let generated = try ProgrammePlanner.makeWeek(profile: profile, history: history, start: date, calendar: calendar)
        let revision = (snapshots.filter { $0.id == generated.id }.map(\.revision).max() ?? 0) + 1
        let result = TrainingProgramme(id: generated.id, timeZoneID: generated.timeZoneID, revision: revision, days: generated.days)
        snapshots.append(result)
        remember(profile, for: result)
        return result
    }
    @discardableResult public mutating func revise(profile: LocalProfile, history: [SessionRecord], protecting activeDayIDs: Set<String>, at date: Date, calendar: Calendar = .current) throws -> TrainingProgramme {
        guard let current = week(at: date, calendar: calendar) else { return try prepare(profile: profile, history: history, at: date, calendar: calendar) }
        var local = calendar
        local.timeZone = TimeZone(identifier: current.timeZoneID) ?? calendar.timeZone
        let past = current.days.filter { $0.date < local.startOfDay(for: date) }.map(\.id)
        let result = try ProgrammePlanner.revise(current, profile: profile, history: history, protecting: activeDayIDs.union(past), calendar: local)
        snapshots.append(result)
        remember(profile, for: result)
        return result
    }
    public enum Adjustment: Equatable, Sendable {
        case easier, shorter, rest, swap(exerciseID: String, replacementID: String), move(toDayID: String)
    }
    @discardableResult public mutating func adjust(dayID: String, action: Adjustment, profile: LocalProfile, history: [SessionRecord], protecting active: Set<String>, at date: Date, calendar: Calendar = .current) throws -> TrainingProgramme {
        guard let week = week(at: date, calendar: calendar), let day = week.days.first(where: { $0.id == dayID }) else { throw ProgrammePlanner.Invalid.date }
        let protected = active.union(history.compactMap(\.plannedWorkoutID)).union(week.days.filter { $0.date < calendar.startOfDay(for: date) }.map(\.id))
        guard !protected.contains(dayID) else { throw ConfigurableSession.Invalid.plan }
        let prefs = profile.effectiveProgrammePreferences
        var days = week.days
        if case .move(let destination) = action {
            guard let other = days.first(where: { $0.id == destination }), !protected.contains(destination) else { throw ConfigurableSession.Invalid.plan }
            days = days.map { value in
                if value.id == day.id { return .init(id: value.id, localDate: value.localDate, date: value.date, kind: other.kind, plan: other.plan) }
                if value.id == other.id { return .init(id: value.id, localDate: value.localDate, date: value.date, kind: day.kind, plan: day.plan) }
                return value
            }
        } else if action == .rest {
            days = days.map { $0.id == dayID ? .init(id: $0.id, localDate: $0.localDate, date: $0.date, kind: .rest, plan: nil) : $0 }
        } else {
            guard let plan = day.plan else { throw ConfigurableSession.Invalid.plan }
            let items = try plan.items.map { item -> CoachSavedPlan.Item in
                switch action {
                case .easier: return .init(exerciseID: item.exerciseID, sets: item.sets, target: max(1, Int(Double(item.target) * 0.75)), unit: item.unit, restSeconds: max(60, item.restSeconds))
                case .shorter: return .init(exerciseID: item.exerciseID, sets: max(1, item.sets - 1), target: item.target, unit: item.unit, restSeconds: item.restSeconds)
                case .swap(let old, let replacement) where item.exerciseID == old:
                    guard let entry = ExerciseCatalog.find(replacement), prefs.canUse(entry), !plan.items.contains(where: { $0.exerciseID == replacement }),
                          let oldEntry = ExerciseCatalog.find(old), entry.family == oldEntry.family else { throw ConfigurableSession.Invalid.plan }
                    let age = prefs.ageContext?.ageYears ?? 0
                    let cap = entry.unit == .reps ? (age < 13 ? 6 : age < 18 ? 10 : 200) : (age < 13 ? 10 : age < 18 ? 20 : 600)
                    return .init(exerciseID: entry.id, sets: item.sets, target: min(entry.goal, cap), unit: entry.unit, restSeconds: item.restSeconds)
                default: return item
                }
            }
            let adjusted = try CoachSavedPlan(items: action == .shorter ? Array(items.prefix(max(1, items.count - 1))) : items,
                availableSupport: prefs.availableSupport, createdAt: date, rationale: "Adjusted locally for your next session.")
            days = days.map { $0.id == dayID ? .init(id: $0.id, localDate: $0.localDate, date: $0.date, kind: $0.kind, plan: adjusted) : $0 }
        }
        let result = TrainingProgramme(id: week.id, timeZoneID: week.timeZoneID, revision: week.revision + 1, days: days)
        snapshots.append(result)
        remember(profile, for: result)
        return result
    }
    public mutating func install(_ programme: TrainingProgramme, profile: LocalProfile, history: [SessionRecord], protecting: Set<String>, at date: Date) throws {
        guard programme.days.count == 7, let zone = TimeZone(identifier: programme.timeZoneID), programme.revision > 0 else { throw ProgrammePlanner.Invalid.date }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let existing = week(at: date, calendar: calendar)
        let protected = protecting.union(history.compactMap(\.plannedWorkoutID)).union(existing?.days.filter { $0.date < calendar.startOfDay(for: date) }.map(\.id) ?? [])
        for day in programme.days {
            if let plan = day.plan {
                _ = try ConfigurableSession(plan: plan, availableSupport: profile.effectiveProgrammePreferences.availableSupport)
                guard plan.items.allSatisfy({ item in ExerciseCatalog.find(item.exerciseID).map(profile.effectiveProgrammePreferences.canUse) == true }) else { throw ConfigurableSession.Invalid.plan }
            }
        }
        let days = programme.days.map { day in
            protected.contains(day.id) ? existing?.days.first { $0.id == day.id } ?? day : day
        }
        let revision = max(programme.revision, (snapshots.filter { $0.id == programme.id }.map(\.revision).max() ?? 0) + 1)
        let installed = TrainingProgramme(id: programme.id, timeZoneID: programme.timeZoneID, revision: revision, days: days)
        snapshots.append(installed)
        remember(profile, for: installed)
    }
}

public struct DatedWeight: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let date: Date
    public let kilograms: Double
    public init(id: UUID = UUID(), date: Date, kilograms: Double) throws {
        guard date.timeIntervalSince1970.isFinite, kilograms.isFinite, (1...500).contains(kilograms) else { throw CocoaError(.coderInvalidValue) }
        self.id = id; self.date = date; self.kilograms = kilograms
    }
    private enum CodingKeys: String, CodingKey { case id, date, kilograms }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(id: c.decode(UUID.self, forKey: .id), date: c.decode(Date.self, forKey: .date), kilograms: c.decode(Double.self, forKey: .kilograms))
    }
}

public enum ProgrammeInsights {
    public struct EffortPoint: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let date: Date
        public let effort: SetEffort?
        public let source: InputSource
    }
    public static func effort(history: [SessionRecord], exerciseID: String) -> [EffortPoint] {
        var sessions = Set<UUID>(), sets = Set<UUID>()
        return history.sorted { $0.date < $1.date }.filter { sessions.insert($0.id).inserted }.flatMap { record in
            record.loggedSets.filter { $0.exerciseID == exerciseID && $0.source != .video && sets.insert($0.id).inserted }
                .map { EffortPoint(id: $0.id, date: record.date, effort: $0.effort, source: $0.source) }
        }
    }
    public struct DayProgress: Identifiable, Sendable {
        public let id: String
        public let plannedSets: Int
        public let recordedSets: Int
        public let recordedReps: Int
        public let recordedSeconds: Double
        public var completed: Bool { plannedSets > 0 && recordedSets >= plannedSets }
    }
    public static func progress(week: TrainingProgramme, history: [SessionRecord]) -> [DayProgress] {
        let distinct = Dictionary(history.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last }).values
        return week.days.map { day in
            let records = distinct.filter { $0.plannedWorkoutID == day.id }
            var seen = Set<UUID>()
            let sets = records.flatMap(\.loggedSets).filter { $0.source != .video && seen.insert($0.id).inserted }
            return DayProgress(id: day.id, plannedSets: day.plan?.items.reduce(0) { $0 + $1.sets } ?? 0,
                recordedSets: sets.count, recordedReps: sets.reduce(0) { $0 + $1.reps }, recordedSeconds: sets.reduce(0) { $0 + $1.seconds })
        }
    }
}

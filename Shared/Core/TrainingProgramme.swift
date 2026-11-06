import Foundation

public enum TrainingGoal: String, CaseIterable, Codable, Sendable {
    case strength, stamina, mobility, balance, weightManagement
}

public enum TrainingStartingPoint: String, CaseIterable, Codable, Sendable {
    case startingOut, somePractice, regularPractice, experienced
    public var suggestedLevel: Int {
        switch self {
        case .startingOut: return 1
        case .somePractice: return 2
        case .regularPractice: return 3
        case .experienced: return 4
        }
    }
}

public struct TrainingAgeContext: Codable, Equatable, Sendable {
    public enum Invalid: Error { case age, guardianRequired }
    public let ageYears: Int
    public let guardianManaged: Bool
    public var allowsAnalytics: Bool { ageYears >= 18 }
    public var allowsCloudPlanSync: Bool { ageYears >= 18 }
    public var allowsHealthIntegration: Bool { ageYears >= 18 }
    public var allowsTimePressureRewards: Bool { ageYears >= 18 }

    public init(ageYears: Int, guardianManaged: Bool) throws {
        guard (0...120).contains(ageYears) else { throw Invalid.age }
        guard ageYears >= 18 || guardianManaged else { throw Invalid.guardianRequired }
        self.ageYears = ageYears; self.guardianManaged = guardianManaged
    }
    private enum CodingKeys: String, CodingKey { case ageYears, guardianManaged }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(ageYears: c.decode(Int.self, forKey: .ageYears), guardianManaged: c.decode(Bool.self, forKey: .guardianManaged))
    }
}

public struct ProgrammePreferences: Codable, Equatable, Sendable {
    public enum Invalid: Error { case goals, weekdays, duration, hour, support, exercise }
    public let goals: Set<TrainingGoal>
    public let weekdays: Set<Int>
    public let minutesPerSession: Int
    public let preferredLocalHour: Int
    public let availableSupport: Set<String>
    public let allowsFloorWork: Bool
    public let excludedExerciseIDs: Set<String>
    public let startingPoint: TrainingStartingPoint?
    public let ageContext: TrainingAgeContext?
    public let comfortAnswers: [ExerciseFamily: TrainingSetup.Comfort]

    public init(goals: Set<TrainingGoal>, weekdays: Set<Int>, minutesPerSession: Int = 20,
                preferredLocalHour: Int = 18, availableSupport: Set<String> = [], allowsFloorWork: Bool = true,
                excludedExerciseIDs: Set<String> = [], startingPoint: TrainingStartingPoint? = nil,
                ageContext: TrainingAgeContext? = nil, comfortAnswers: [ExerciseFamily: TrainingSetup.Comfort] = [:]) throws {
        guard !goals.isEmpty else { throw Invalid.goals }
        guard !weekdays.isEmpty, weekdays.isSubset(of: Set(1...7)) else { throw Invalid.weekdays }
        guard [10, 20, 30, 45].contains(minutesPerSession) else { throw Invalid.duration }
        guard (0...23).contains(preferredLocalHour) else { throw Invalid.hour }
        guard availableSupport.isSubset(of: Set(PathSurvey.equipmentChoices)) else { throw Invalid.support }
        guard excludedExerciseIDs.isSubset(of: Set(ExerciseCatalog.all.map(\.id))) else { throw Invalid.exercise }
        self.goals = goals; self.weekdays = weekdays; self.minutesPerSession = minutesPerSession
        self.preferredLocalHour = preferredLocalHour; self.availableSupport = availableSupport
        self.allowsFloorWork = allowsFloorWork; self.excludedExerciseIDs = excludedExerciseIDs; self.startingPoint = startingPoint; self.ageContext = ageContext; self.comfortAnswers = comfortAnswers
    }

    public static let floorExerciseIDs: Set<String> = [
        "gluteBridge", "deadBug", "birdDog", "kneePlank", "catCow", "kneeSidePlank", "hipFlexorStretch",
        "plank", "kneePushup", "highPlank", "sidePlank", "mountainClimber", "pushup", "widePushup",
        "closeGripPushup", "tempoPushup", "pausedPushup", "diamondPushup"
    ]

    public func canUse(_ entry: ExerciseEntry) -> Bool {
        guard !excludedExerciseIDs.contains(entry.id),
              allowsFloorWork || !Self.floorExerciseIDs.contains(entry.id),
              PathSurvey.requiredEquipment(for: entry).map(availableSupport.contains) ?? true else { return false }
        guard let age = ageContext?.ageYears else { return true }
        guard age >= 5 else { return false }
        if age < 13 {
            return ["frontArmRaise", "standingKneeRaise", "seatedMarch", "stepJack", "sitToStand", "singleLegBalance"].contains(entry.id)
        }
        return age >= 18 || entry.level == 1 || entry.id == "standingBicepsCurl"
    }

    private enum CodingKeys: String, CodingKey {
        case goals, weekdays, minutesPerSession, preferredLocalHour, availableSupport, allowsFloorWork, excludedExerciseIDs, startingPoint, ageContext, comfortAnswers
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(goals: c.decode(Set<TrainingGoal>.self, forKey: .goals), weekdays: c.decode(Set<Int>.self, forKey: .weekdays),
                      minutesPerSession: c.decode(Int.self, forKey: .minutesPerSession), preferredLocalHour: c.decode(Int.self, forKey: .preferredLocalHour),
                      availableSupport: c.decode(Set<String>.self, forKey: .availableSupport), allowsFloorWork: c.decode(Bool.self, forKey: .allowsFloorWork),
                      excludedExerciseIDs: c.decode(Set<String>.self, forKey: .excludedExerciseIDs), startingPoint: c.decodeIfPresent(TrainingStartingPoint.self, forKey: .startingPoint),
                      ageContext: c.decodeIfPresent(TrainingAgeContext.self, forKey: .ageContext),
                      comfortAnswers: c.decodeIfPresent([ExerciseFamily: TrainingSetup.Comfort].self, forKey: .comfortAnswers) ?? [:])
    }
}

public extension LocalProfile {
    var trainingGoals: Set<TrainingGoal> {
        programmePreferences?.goals ?? Set(goals.compactMap { TrainingGoal(rawValue: $0.rawValue) })
            .union(weightManagementGoal ? [.weightManagement] : [])
    }
    var effectiveProgrammePreferences: ProgrammePreferences {
        if let programmePreferences { return programmePreferences }
        let rhythm = [1, 3, 5, 2, 4, 6, 7]
        return try! ProgrammePreferences(goals: trainingGoals, weekdays: Set(rhythm.prefix(weeklyTarget)),
            startingPoint: baselineAbility.flatMap { TrainingStartingPoint(rawValue: $0.rawValue) })
    }
}

public struct TrainingProgramme: Codable, Equatable, Sendable, Identifiable {
    public enum DayKind: String, Codable, Sendable { case workout, rest, recovery, familyMovement }
    public struct Day: Codable, Equatable, Sendable, Identifiable {
        public let id: String
        public let localDate: String
        public let date: Date
        public let kind: DayKind
        public let plan: CoachSavedPlan?
    }
    public let id: String
    public let timeZoneID: String
    public let revision: Int
    public let days: [Day]
}

public enum ProgrammePlanner {
    public enum Invalid: Error, Equatable { case date, noUsableExercises, timeZone, ageRequired }

    public static func makeWeek(profile: LocalProfile, history: [SessionRecord], start: Date,
                                calendar: Calendar = .current) throws -> TrainingProgramme {
        guard start.timeIntervalSince1970.isFinite else { throw Invalid.date }
        var local = Calendar(identifier: .gregorian)
        local.timeZone = calendar.timeZone
        let prefs = profile.effectiveProgrammePreferences
        guard let age = prefs.ageContext?.ageYears else { throw Invalid.ageRequired }
        let first = local.startOfDay(for: start)
        var consecutive = 0
        var activity = 0
        let days: [TrainingProgramme.Day] = try (0..<7).map { offset in
            guard let day = local.date(byAdding: .day, value: offset, to: first),
                  let scheduled = local.date(bySettingHour: prefs.preferredLocalHour, minute: 0, second: 0, of: day) else { throw Invalid.date }
            let isoWeekday = (local.component(.weekday, from: day) + 5) % 7 + 1
            let selected = prefs.weekdays.contains(isoWeekday)
            let recovery = selected && consecutive >= 2
            let kind: TrainingProgramme.DayKind = !selected ? .rest : age < 5 ? .familyMovement : recovery ? .recovery : .workout
            consecutive = !selected || recovery ? 0 : consecutive + 1
            let key = localDate(day, calendar: local)
            let evidence = SkillProgress.evaluate(history: history.filter { $0.date < day }, calendar: local)
            let recent = recentHistory(history, before: day, calendar: local)
            let plan = selected && age >= 5 ? try makePlan(profile: profile, evidence: evidence, recent: recent, recovery: recovery, ordinal: activity, at: scheduled) : nil
            if selected { activity += 1 }
            return .init(id: "programme:\(local.timeZone.identifier):\(key)", localDate: key, date: scheduled, kind: kind, plan: plan)
        }
        return .init(id: "week:\(local.timeZone.identifier):\(localDate(first, calendar: local))", timeZoneID: local.timeZone.identifier, revision: 1, days: days)
    }

    public static func revise(_ programme: TrainingProgramme, profile: LocalProfile, history: [SessionRecord],
                              protecting activeDayIDs: Set<String>, calendar: Calendar = .current) throws -> TrainingProgramme {
        guard let first = programme.days.first else { throw Invalid.date }
        guard let zone = TimeZone(identifier: programme.timeZoneID) else { throw Invalid.timeZone }
        var local = calendar
        local.timeZone = zone
        let next = try makeWeek(profile: profile, history: history, start: first.date, calendar: local)
        let protected = activeDayIDs.union(history.compactMap(\.plannedWorkoutID))
        let days = next.days.map { day in
            protected.contains(day.id) ? programme.days.first { $0.id == day.id } ?? day : day
        }
        return .init(id: programme.id, timeZoneID: programme.timeZoneID, revision: programme.revision + 1, days: days)
    }

    private static func localDate(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    private static func recentHistory(_ history: [SessionRecord], before date: Date, calendar: Calendar) -> [LoggedSet] {
        let since = calendar.date(byAdding: .day, value: -28, to: date)!
        var sessions = Set<UUID>(), sets = Set<UUID>()
        return history.filter { $0.date >= since && $0.date < date }.sorted { $0.date > $1.date }
            .filter { sessions.insert($0.id).inserted }.flatMap { session in
                session.loggedSets + session.sets.map { set in
                    LoggedSet(id: set.id, exerciseID: set.exercise.rawValue, reps: set.reps, seconds: 0,
                              source: set.source, reason: set.reason, target: set.target)
                }
            }
            .filter { $0.source != .video && sets.insert($0.id).inserted }
    }

    private static func makePlan(profile: LocalProfile, evidence: SkillProgress, recent: [LoggedSet], recovery: Bool,
                                 ordinal: Int, at date: Date) throws -> CoachSavedPlan {
        let prefs = profile.effectiveProgrammePreferences
        let age = prefs.ageContext!.ageYears
        let isChild = age < 18
        let usable = ExerciseCatalog.all.filter(prefs.canUse)
        let planningGoals: Set<TrainingGoal> = isChild ? [] : prefs.goals
        let families = ExerciseFamily.allCases.sorted { left, right in
            let l = priority(left, goals: planningGoals, recovery: recovery)
            let r = priority(right, goals: planningGoals, recovery: recovery)
            return l == r ? left.rawValue < right.rawValue : l > r
        }
        let selected = families.compactMap { family -> ExerciseEntry? in
            let entries = usable.filter { $0.family == family }
            let placed = entries.filter { profile.comfortableExercises.contains($0.id) ||
                ((evidence.node(exerciseID: $0.id)?.qualifyingSets ?? 0) >= 3 && (evidence.node(exerciseID: $0.id)?.trainingDays ?? 0) >= 2) }
            let abilityLevel = placed.map(\.level).max() ?? prefs.startingPoint?.suggestedLevel ?? 1
            let gentleOnly = recovery || isChild || abilityLevel == 1
            let candidates = entries.filter {
                gentleOnly ? $0.level == 1 || $0.id == "standingBicepsCurl" : $0.level <= abilityLevel
            }
            let selectedLevel = gentleOnly ? candidates.map(\.level).min() : candidates.map(\.level).max()
            let peers = candidates.filter { $0.level == selectedLevel }.sorted { $0.id < $1.id }
            guard !peers.isEmpty else { return nil }
            return peers[ordinal % peers.count]
        }
        guard !selected.isEmpty else { throw Invalid.noUsableExercises }
        let count = recovery ? 3 : prefs.minutesPerSession == 10 ? 3 : prefs.minutesPerSession == 20 ? 4 : 6
        let items = selected.prefix(count).map { entry -> CoachSavedPlan.Item in
            let actual = recent.filter { $0.exerciseID == entry.id }.prefix(6)
            let difficult = actual.contains { set in set.reason == .discomfort || set.reason == .failure || (set.effort?.rawValue ?? 0) >= 8 ||
                set.target.map { target in (entry.unit == .reps ? Double(set.reps) : set.seconds) < Double(target) * 0.8 } == true }
            let easy = !actual.isEmpty && actual.allSatisfy { set in
                guard let effort = set.effort, effort.rawValue <= 4, let target = set.target, target > 0,
                      set.reason != .discomfort, set.reason != .failure else { return false }
                return (entry.unit == .reps ? Double(set.reps) : set.seconds) >= Double(target)
            }
            let base = recovery || prefs.startingPoint == nil || prefs.startingPoint == .startingOut ? max(2, entry.goal / 2) : entry.goal
            let adaptedTarget = difficult ? max(1, base * 3 / 4) : easy && !recovery && !isChild ? base + (entry.unit == .reps ? 1 : 5) : base
            let childCap = entry.unit == .reps ? (age < 13 ? 6 : 10) : (age < 13 ? 10 : 20)
            let target = isChild ? min(childCap, adaptedTarget) : adaptedTarget
            let plannedSets = recovery ? 1 : prefs.minutesPerSession == 10 ? 1 : prefs.minutesPerSession == 45 ? 3 : 2
            let sets = isChild ? min(age < 13 ? 1 : 2, plannedSets) : plannedSets
            return .init(exerciseID: entry.id, sets: difficult ? 1 : sets, target: target, unit: entry.unit,
                         restSeconds: recovery ? 30 : difficult ? 90 : 60)
        }
        return try CoachSavedPlan(items: items, availableSupport: prefs.availableSupport, createdAt: date,
                                  rationale: isChild ? "Gentle varied practice with your guardian." : recovery ? "An easier day with comfortable movement." : "Your prepared workout follows your goals and recorded practice.")
    }

    private static func priority(_ family: ExerciseFamily, goals: Set<TrainingGoal>, recovery: Bool) -> Int {
        if recovery { return family == .mobility ? 10 : family == .balance ? 9 : family == .conditioning ? 8 : 0 }
        let matched: Bool
        switch family {
        case .push, .legs: matched = goals.contains(.strength)
        case .conditioning: matched = goals.contains(.stamina) || goals.contains(.weightManagement)
        case .mobility: matched = goals.contains(.mobility)
        case .balance: matched = goals.contains(.balance)
        case .core: matched = goals.contains(.strength) || goals.contains(.stamina)
        }
        return matched ? 10 : 0
    }
}

import Foundation

public struct CloudProgrammePreferences: Codable, Equatable, Sendable {
    public let goals: [TrainingGoal]
    public let weekdays: [Int]
    public let minutesPerSession: Int
    public let preferredLocalHour: Int
    public let availableSupport: [String]
    public let allowsFloorWork: Bool
    public let excludedExerciseIDs: [String]
    public let startingPoint: TrainingStartingPoint?
    public init(_ local: ProgrammePreferences) {
        goals = local.goals.sorted { $0.rawValue < $1.rawValue }; weekdays = local.weekdays.sorted()
        minutesPerSession = local.minutesPerSession; preferredLocalHour = local.preferredLocalHour
        availableSupport = local.availableSupport.sorted(); allowsFloorWork = local.allowsFloorWork
        excludedExerciseIDs = local.excludedExerciseIDs.sorted(); startingPoint = local.startingPoint
    }
    enum CodingKeys: String, CodingKey { case goals, weekdays, minutesPerSession, preferredLocalHour, availableSupport, allowsFloorWork, excludedExerciseIDs, startingPoint }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(goals, forKey: .goals); try c.encode(weekdays, forKey: .weekdays)
        try c.encode(minutesPerSession, forKey: .minutesPerSession); try c.encode(preferredLocalHour, forKey: .preferredLocalHour)
        try c.encode(availableSupport, forKey: .availableSupport); try c.encode(allowsFloorWork, forKey: .allowsFloorWork)
        try c.encode(excludedExerciseIDs, forKey: .excludedExerciseIDs); try c.encode(startingPoint, forKey: .startingPoint)
    }
    public func restoringLocalPolicy(_ local: ProgrammePreferences) throws -> ProgrammePreferences {
        guard Set(goals).count == goals.count, Set(weekdays).count == weekdays.count,
              Set(availableSupport).count == availableSupport.count, Set(excludedExerciseIDs).count == excludedExerciseIDs.count else { throw ProgrammePreferences.Invalid.goals }
        return try ProgrammePreferences(goals: Set(goals), weekdays: Set(weekdays), minutesPerSession: minutesPerSession,
            preferredLocalHour: preferredLocalHour, availableSupport: Set(availableSupport), allowsFloorWork: allowsFloorWork,
            excludedExerciseIDs: Set(excludedExerciseIDs), startingPoint: startingPoint,
            ageContext: local.ageContext, comfortAnswers: local.comfortAnswers)
    }
}

public struct CloudProgramme: Codable, Equatable, Sendable {
    public struct Plan: Codable, Equatable, Sendable {
        public struct Item: Codable, Equatable, Sendable {
            public let exerciseID: String
            public let sets: Int
            public let target: Int
            public let unit: ExerciseEntry.Unit
            public let restSeconds: Int
        }
        public let approvedAt: Date
        public let items: [Item]
    }
    public struct Day: Codable, Equatable, Sendable {
        public let id: String
        public let localDate: String
        public let date: Date
        public let kind: TrainingProgramme.DayKind
        public let plan: Plan?
        enum CodingKeys: String, CodingKey { case id, localDate, date, kind, plan }
        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id); try c.encode(localDate, forKey: .localDate)
            try c.encode(date, forKey: .date); try c.encode(kind, forKey: .kind); try c.encode(plan, forKey: .plan)
        }
    }
    public let id: String
    public let timeZoneID: String
    public let revision: Int
    public let days: [Day]
    public init(_ week: TrainingProgramme) {
        id = week.id; timeZoneID = week.timeZoneID; revision = week.revision
        days = week.days.map { day in
            Day(id: day.id, localDate: day.localDate, date: day.date, kind: day.kind, plan: day.plan.map { plan in
                Plan(approvedAt: plan.approvedAt, items: plan.items.map { .init(exerciseID: $0.exerciseID, sets: $0.sets, target: $0.target, unit: $0.unit, restSeconds: $0.restSeconds) })
            })
        }
    }
    public func restoring(profile: LocalProfile) throws -> TrainingProgramme {
        guard profile.effectiveProgrammePreferences.ageContext?.allowsCloudPlanSync == true,
              let zone = TimeZone(identifier: timeZoneID), days.count == 7, revision > 0, let first = days.first,
              id == "week:\(timeZoneID):\(first.localDate)" else { throw ProgrammePlanner.Invalid.date }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let formatter = DateFormatter(); formatter.calendar = calendar; formatter.timeZone = zone
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        let restored = try days.enumerated().map { offset, day -> TrainingProgramme.Day in
            guard day.date.timeIntervalSince1970.isFinite, day.localDate == formatter.string(from: day.date),
                  day.id == "programme:\(timeZoneID):\(day.localDate)",
                  let expected = calendar.date(byAdding: .day, value: offset, to: first.date), calendar.isDate(expected, inSameDayAs: day.date),
                  day.kind != .familyMovement, (day.kind == .rest) == (day.plan == nil) else { throw ProgrammePlanner.Invalid.date }
            let plan = try day.plan.map { value -> CoachSavedPlan in
                guard value.approvedAt.timeIntervalSince1970.isFinite, (1...12).contains(value.items.count),
                      Set(value.items.map(\.exerciseID)).count == value.items.count else { throw ConfigurableSession.Invalid.plan }
                let items = try value.items.map { item -> CoachSavedPlan.Item in
                    guard let entry = ExerciseCatalog.find(item.exerciseID), profile.effectiveProgrammePreferences.canUse(entry), entry.unit == item.unit,
                          (1...10).contains(item.sets), (1...(item.unit == .reps ? 200 : 600)).contains(item.target), (0...600).contains(item.restSeconds) else { throw ConfigurableSession.Invalid.plan }
                    return .init(exerciseID: item.exerciseID, sets: item.sets, target: item.target, unit: item.unit, restSeconds: item.restSeconds)
                }
                return try CoachSavedPlan(items: items, availableSupport: profile.effectiveProgrammePreferences.availableSupport, createdAt: value.approvedAt, rationale: "Your saved programme, restored by your choice.")
            }
            return .init(id: day.id, localDate: day.localDate, date: day.date, kind: day.kind, plan: plan)
        }
        return .init(id: id, timeZoneID: timeZoneID, revision: revision, days: restored)
    }
}

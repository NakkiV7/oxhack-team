import Foundation

public struct DailyXPWindow: Codable, Equatable, Sendable {
    public enum Invalid: Error { case hour }
    public let startHour: Int
    public init(startHour: Int) throws {
        guard (0...22).contains(startHour) else { throw Invalid.hour }
        self.startHour = startHour
    }
    private enum CodingKeys: String, CodingKey { case startHour }
    public init(from decoder: Decoder) throws {
        try self.init(startHour: decoder.container(keyedBy: CodingKeys.self).decode(Int.self, forKey: .startHour))
    }
    public func interval(on date: Date, calendar: Calendar) -> DateInterval? {
        guard date.timeIntervalSince1970.isFinite,
              let start = calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: date,
                                        matchingPolicy: .nextTime, repeatedTimePolicy: .first),
              let end = calendar.date(byAdding: .hour, value: 2, to: start) else { return nil }
        return DateInterval(start: start, end: end)
    }
}

public struct XPWindowChange: Codable, Equatable, Sendable {
    public let window: DailyXPWindow
    public let effectiveAt: Date
}

public struct CompletionReward: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let completedAt: Date
    public let day: Date
    public let completedSetCount: Int
    public let baseXP: Int
    public let bonusXP: Int
}

public struct GamificationSummary: Equatable, Sendable {
    public let protectedStreak: Int
    public let actualTrainingDays: Int
    public let trainedToday: Bool
    public let remainingFreezes: Int
}

public struct GamificationLedger: Codable, Sendable {
    public enum Invalid: Error { case date, baseXP }
    public let createdAt: Date
    public let calendar: Calendar
    public private(set) var windowChanges: [XPWindowChange] = []
    public private(set) var events: [CompletionReward] = []
    public private(set) var frozenDays: [Date] = []
    public private(set) var restDays: [Date] = []
    private var retiredSessionIDs = Set<UUID>()
    public var totalBonusXP: Int { events.reduce(0) { $0 + $1.bonusXP } }
    public var remainingFreezes: Int { max(0, 2 - frozenDays.count) }

    public init(createdAt: Date = Date(), calendar: Calendar = .current) {
        self.createdAt = createdAt; self.calendar = calendar
    }
    private enum CodingKeys: String, CodingKey { case createdAt, calendar, windowChanges, events, frozenDays, restDays, retiredSessionIDs }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(createdAt: try values.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(),
                  calendar: try values.decodeIfPresent(Calendar.self, forKey: .calendar) ?? .current)
        windowChanges = try values.decodeIfPresent([XPWindowChange].self, forKey: .windowChanges) ?? []
        events = try values.decodeIfPresent([CompletionReward].self, forKey: .events) ?? []
        frozenDays = try values.decodeIfPresent([Date].self, forKey: .frozenDays) ?? []
        restDays = try values.decodeIfPresent([Date].self, forKey: .restDays) ?? []
        retiredSessionIDs = try values.decodeIfPresent(Set<UUID>.self, forKey: .retiredSessionIDs) ?? []
    }

    public mutating func scheduleWindow(_ window: DailyXPWindow, at now: Date) throws {
        guard createdAt.timeIntervalSince1970.isFinite, now >= createdAt, let today = day(now),
              let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { throw Invalid.date }
        windowChanges.removeAll { $0.effectiveAt == tomorrow }
        windowChanges.append(.init(window: window, effectiveAt: tomorrow))
        windowChanges.sort { $0.effectiveAt < $1.effectiveAt }
    }
    public func window(at date: Date) -> DailyXPWindow? {
        guard date.timeIntervalSince1970.isFinite else { return nil }
        return windowChanges.last { $0.effectiveAt <= date }?.window
    }

    @discardableResult
    public mutating func awardCompletion(record: SessionRecord, completedAt: Date, eligibleBaseXP: Int, now: Date) throws -> CompletionReward? {
        if let existing = events.first(where: { $0.sessionID == record.id }) { return existing }
        guard !retiredSessionIDs.contains(record.id) else { return nil }
        guard createdAt.timeIntervalSince1970.isFinite, now.timeIntervalSince1970.isFinite,
              completedAt.timeIntervalSince1970.isFinite, completedAt >= createdAt, completedAt <= now,
              record.date.timeIntervalSince1970.isFinite, record.date <= completedAt,
              let completedDay = day(completedAt) else { throw Invalid.date }
        let count = Self.completedSetCount(record)
        guard count > 0 else { retiredSessionIDs.insert(record.id); return nil }
        let progress = SkillProgress.evaluate(history: [record], calendar: calendar)
        let maximumBase = TrainingAttribute.allCases.reduce(0) { $0 + progress.points(for: $1) }
        guard eligibleBaseXP >= 0, eligibleBaseXP % 10 == 0, eligibleBaseXP <= maximumBase else { throw Invalid.baseXP }
        let interval = window(at: completedAt)?.interval(on: completedAt, calendar: calendar)
        let doubled = interval.map { completedAt >= $0.start && completedAt < $0.end } ?? false
        let reward = CompletionReward(sessionID: record.id, completedAt: completedAt, day: completedDay,
                                      completedSetCount: count, baseXP: eligibleBaseXP, bonusXP: doubled ? eligibleBaseXP : 0)
        events.append(reward)
        return reward
    }

    @discardableResult
    public mutating func advance(to now: Date, plannedRestDays: [Date] = [], baselineActivityDays: [Date] = []) -> [Date] {
        let activity = trainingDays(at: now, baselineActivityDays: baselineActivityDays)
        guard let today = day(now), let activated = day(createdAt), let first = activity.min() else { return [] }
        let rests = plannedRestDays.compactMap(day).filter { $0 >= first && $0 < today && !activity.contains($0) }
        restDays = Set(restDays + rests).sorted()
        var protected = activity.union(frozenDays).union(restDays), added: [Date] = []
        var cursor = first, connected = true
        while cursor < today {
            if activity.contains(cursor) { connected = true }
            else if !protected.contains(cursor) {
                if connected && cursor >= activated && remainingFreezes > 0 {
                    frozenDays.append(cursor); added.append(cursor); protected.insert(cursor)
                } else { connected = false }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor else { break }
            cursor = next
        }
        return added
    }

    public mutating func removeCompletion(sessionID: UUID) {
        events.removeAll { $0.sessionID == sessionID }
        retiredSessionIDs.insert(sessionID)
    }
    public func summary(at now: Date, baselineActivityDays: [Date] = []) -> GamificationSummary {
        let activity = trainingDays(at: now, baselineActivityDays: baselineActivityDays)
        guard let today = day(now), let first = activity.min() else {
            return .init(protectedStreak: 0, actualTrainingDays: 0, trainedToday: false, remainingFreezes: remainingFreezes)
        }
        let protected = activity.union(frozenDays).union(restDays).filter { $0 >= first && $0 <= today }
        let trainedToday = activity.contains(today)
        var cursor = trainedToday ? today : (calendar.date(byAdding: .day, value: -1, to: today) ?? today)
        var streak = 0, anchoredStreak = 0
        while protected.contains(cursor) {
            streak += 1
            if activity.contains(cursor) { anchoredStreak = streak }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor), previous < cursor else { break }
            cursor = previous
        }
        return .init(protectedStreak: anchoredStreak, actualTrainingDays: activity.count, trainedToday: trainedToday, remainingFreezes: remainingFreezes)
    }
    private func day(_ date: Date) -> Date? {
        guard date.timeIntervalSince1970.isFinite else { return nil }
        return calendar.dateInterval(of: .day, for: date)?.start
    }
    private func trainingDays(at now: Date, baselineActivityDays: [Date]) -> Set<Date> {
        guard now.timeIntervalSince1970.isFinite else { return [] }
        let baseline = baselineActivityDays.filter { $0.timeIntervalSince1970.isFinite && $0 <= now }.compactMap(day)
        return Set(events.filter { $0.completedAt <= now && $0.completedSetCount > 0 }.map(\.day)).union(baseline)
    }
    private static func completedSetCount(_ record: SessionRecord) -> Int {
        let tracked = record.sets.filter { $0.source != .video && $0.reps > 0 }.map(\.id)
        let logged = record.loggedSets.filter { set in
            guard set.source != .video, let entry = ExerciseCatalog.find(set.exerciseID) else { return false }
            return entry.unit == .reps ? set.reps > 0 && set.seconds == 0 : set.reps == 0 && set.seconds.isFinite && set.seconds > 0
        }.map(\.id)
        return Set(tracked + logged).count
    }
}

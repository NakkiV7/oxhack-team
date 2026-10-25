import Foundation

/// Training days from the person's own history, for the calendar and the weekly review. Video replays are not training and
/// never make a day count, as in the skill tree and the measured attributes.
public enum TrainingCalendar {
    public struct Day: Identifiable, Equatable, Sendable {
        public enum Kind: Sendable { case camera, manual }
        /// Start of the day in the person's calendar.
        public let date: Date
        public let sessionIDs: [UUID]
        public let sets: Int
        public let reps: Int
        public let holdSeconds: Double
        public let activeSeconds: Double
        public let cameraSets: Int
        public let manualSets: Int
        public var id: Date { date }
        /// A day with any camera-tracked set shows as camera tracked; otherwise it was logged.
        public var kind: Kind { cameraSets > 0 ? .camera : .manual }
    }

    public struct WeekComparison: Equatable, Sendable {
        public let thisWeek: DateInterval
        public let sessions: (now: Int, before: Int)
        public let trainingDays: (now: Int, before: Int)
        public let sets: (now: Int, before: Int)
        public let reps: (now: Int, before: Int)
        public let averageRepSeconds: (now: Double?, before: Double?)
        public static func == (a: WeekComparison, b: WeekComparison) -> Bool {
            a.thisWeek == b.thisWeek && a.sessions == b.sessions && a.trainingDays == b.trainingDays && a.sets == b.sets && a.reps == b.reps
                && a.averageRepSeconds.now == b.averageRepSeconds.now && a.averageRepSeconds.before == b.averageRepSeconds.before
        }
    }

    /// One entry per training day, keyed by the start of the day.
    public static func days(history: [SessionRecord], calendar: Calendar = .current) -> [Date: Day] {
        var seen = Set<UUID>()
        let sessions = history.filter { $0.date.timeIntervalSince1970.isFinite && seen.insert($0.id).inserted }
        let grouped = Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.date) }
        return grouped.compactMapValues { records -> Day? in
            let tracked = records.flatMap(\.sets).filter { $0.source != .video }
            let logged = records.flatMap(\.loggedSets).filter { $0.source != .video }
            guard !tracked.isEmpty || !logged.isEmpty else { return nil }
            let day = calendar.startOfDay(for: records[0].date)
            return Day(date: day, sessionIDs: records.filter { !$0.sets.filter { $0.source != .video }.isEmpty || !$0.loggedSets.filter { $0.source != .video }.isEmpty }.map(\.id),
                       sets: tracked.count + logged.count, reps: tracked.reduce(0) { $0 + $1.reps } + logged.reduce(0) { $0 + $1.reps },
                       holdSeconds: logged.reduce(0) { $0 + $1.seconds },
                       activeSeconds: tracked.reduce(0) { $0 + $1.activeSeconds } + logged.reduce(0) { $0 + ($1.activeSeconds ?? 0) },
                       cameraSets: tracked.filter { $0.source == .camera }.count + logged.filter { $0.source == .camera }.count,
                       manualSets: tracked.filter { $0.source == .manual }.count + logged.filter { $0.source == .manual }.count)
        }
    }

    /// The month containing `date`, as weeks of seven slots starting on the calendar's first weekday; nil slots pad the
    /// first and last week.
    public static func monthGrid(containing date: Date, calendar: Calendar = .current) -> [[Date?]] {
        guard let month = calendar.dateInterval(of: .month, for: date),
              let count = calendar.range(of: .day, in: .month, for: date)?.count else { return [] }
        let first = month.start, lead = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        let slots: [Date?] = Array(repeating: nil, count: lead) + (0..<count).map { calendar.date(byAdding: .day, value: $0, to: first) }
        let padded = slots + Array(repeating: nil, count: (7 - slots.count % 7) % 7)
        return stride(from: 0, to: padded.count, by: 7).map { Array(padded[$0..<$0 + 7]) }
    }

    /// Weekday initials in the calendar's order, for the grid header.
    public static func weekdaySymbols(calendar: Calendar = .current) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        return (0..<7).map { symbols[(calendar.firstWeekday - 1 + $0) % 7] }
    }

    /// Consecutive training days ending today (or yesterday, so a streak is not lost before today's session), and the
    /// longest run in the history.
    public static func streaks(trainingDays: Set<Date>, today: Date, calendar: Calendar = .current) -> (current: Int, longest: Int) {
        let days = Set(trainingDays.map { calendar.startOfDay(for: $0) })
        func run(from start: Date) -> Int {
            var count = 0, day = start
            while days.contains(day) { count += 1; day = calendar.date(byAdding: .day, value: -1, to: day)! }
            return count
        }
        let todayStart = calendar.startOfDay(for: today)
        let current = days.contains(todayStart) ? run(from: todayStart) : run(from: calendar.date(byAdding: .day, value: -1, to: todayStart)!)
        // Each run is counted back from its last day.
        let longest = days.filter { !days.contains(calendar.date(byAdding: .day, value: 1, to: $0)!) }.map(run).max() ?? 0
        return (current, max(current, longest))
    }

    /// Sample training for presentations: about five days a week over the last six weeks, ending yesterday, with camera
    /// sessions of squats and push-ups and logged accessory work. The same day always gets the same sample, today never gets
    /// one, and a day with real training keeps only its own sessions.
    public static func sampleHistory(now: Date, excluding history: [SessionRecord] = [], calendar: Calendar = .current) -> [SessionRecord] {
        let today = calendar.startOfDay(for: now)
        let real = Set(history.map { calendar.startOfDay(for: $0.date) })
        // A fixed scramble of the day number into 0..<100, so the pattern looks irregular but never changes between renders.
        func roll(_ day: Int, _ salt: Int) -> Int { Int(UInt64(truncatingIfNeeded: day &* 31 &+ salt) &* 2_654_435_761 % 100) }
        func id(_ day: Int, _ index: Int) -> UUID { UUID(uuidString: String(format: "5A3B1E00-0000-4000-8000-%012ld", day * 100 + index))! }
        return (1...41).compactMap { offset -> SessionRecord? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today), !real.contains(day) else { return nil }
            let n = calendar.ordinality(of: .day, in: .era, for: day) ?? offset
            guard offset <= 5 || roll(n, 1) < 62 else { return nil }   // the last five days are a streak
            let start = calendar.date(bySettingHour: roll(n, 2) < 50 ? 7 : 18, minute: roll(n, 3) < 50 ? 15 : 40, second: 0, of: day) ?? day
            let growth = (41 - offset) / 10   // a little stronger each week
            if roll(n, 4) < 68 {
                let exercises: [Exercise] = roll(n, 5) < 40 ? [.squat, .pushup] : [roll(n, 6) < 55 ? .squat : .pushup]
                var sets: [SetRecord] = []
                for exercise in exercises {
                    for number in 1...3 {
                        let reps = min(exercise.target + 3, exercise.target - 4 + growth + roll(n, 10 + sets.count) % 3)
                        let durations = (0..<reps).map { 2.1 + Double(roll(n, 40 + $0 + sets.count * 20) % 60) / 100 }
                        sets.append(SetRecord(id: id(n, sets.count), exercise: exercise, number: number, reps: reps, target: exercise.target,
                                              activeSeconds: durations.reduce(0, +), source: .camera, reserve: 2,
                                              reason: reps >= exercise.target ? .target : .voluntary, repDurations: durations,
                                              restSecondsBefore: number == 1 ? nil : 75))
                    }
                }
                return SessionRecord(id: id(n, 99), date: start, sets: sets)
            }
            let options = ["gluteBridge", "wallPushup", "kneePushup"]
            guard let entry = ExerciseCatalog.find(options[roll(n, 7) % options.count]) else { return nil }
            let logs = (1...3).map { number in
                LoggedSet(id: id(n, 10 + number), exerciseID: entry.id, reps: entry.goal - 2 + growth, seconds: 0, source: .manual,
                          reason: .voluntary, number: number, target: entry.goal)
            }
            return SessionRecord(id: id(n, 99), date: start, sets: [], loggedSets: logs)
        }
    }

    /// This calendar week against the week before.
    public static func weekComparison(history: [SessionRecord], now: Date, calendar: Calendar = .current) -> WeekComparison {
        let week = calendar.dateInterval(of: .weekOfYear, for: now) ?? DateInterval(start: calendar.startOfDay(for: now), duration: 7 * 86_400)
        let previous = DateInterval(start: calendar.date(byAdding: .day, value: -7, to: week.start)!, end: week.start)
        let all = days(history: history, calendar: calendar)
        func stats(_ interval: DateInterval) -> (sessions: Int, days: Int, sets: Int, reps: Int, repSeconds: Double?) {
            let inside = all.values.filter { $0.date >= interval.start && $0.date < interval.end }   // half-open: Monday belongs to one week
            let ids = Set(inside.flatMap(\.sessionIDs))
            let durations = history.filter { ids.contains($0.id) }.flatMap(\.sets).filter { $0.source != .video }.flatMap { $0.repDurations ?? [] }
            return (ids.count, inside.count, inside.reduce(0) { $0 + $1.sets }, inside.reduce(0) { $0 + $1.reps },
                    durations.isEmpty ? nil : durations.reduce(0, +) / Double(durations.count))
        }
        let a = stats(week), b = stats(previous)
        return .init(thisWeek: week, sessions: (a.sessions, b.sessions), trainingDays: (a.days, b.days), sets: (a.sets, b.sets),
                     reps: (a.reps, b.reps), averageRepSeconds: (a.repSeconds, b.repSeconds))
    }
}

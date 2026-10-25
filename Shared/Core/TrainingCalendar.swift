import Foundation

// The training calendar and weekly review, computed only from the saved history. Every number shown in the Insights tab
// comes from here or from `WorkoutReport`; nothing is generated.

/// One day of the month grid.
public struct CalendarDay: Identifiable, Sendable {
    public let date: Date
    /// False for the leading and trailing days that fill the first and last week of the grid.
    public let inMonth: Bool
    public let reports: [WorkoutReport]
    public var id: Date { date }

    public var trained: Bool { reports.contains { $0.setCount > 0 } }
    public var hasCameraSets: Bool { reports.contains { $0.sets.contains { $0.source == .camera } } }
    public var hasManualSets: Bool { reports.contains { $0.sets.contains { $0.source == .manual } } }
    public var setCount: Int { reports.reduce(0) { $0 + $1.setCount } }
    public var reps: Int { reports.reduce(0) { $0 + $1.reps } }
    public var holdSeconds: Double { reports.reduce(0) { $0 + $1.holdSeconds } }
    public var activeSeconds: Double { reports.reduce(0) { $0 + $1.activeSeconds } }
    /// Average of every recorded Apple Watch heart-rate sample that day, or nil when none was recorded.
    public var averageHeartRate: Double? {
        let samples = reports.flatMap(\.heartRate.samples).map(\.value)
        return samples.isEmpty ? nil : samples.reduce(0, +) / Double(samples.count)
    }
}

/// A month laid out in whole weeks, starting on the calendar's first weekday.
public struct TrainingMonth: Sendable {
    public let interval: DateInterval
    public let days: [CalendarDay]
    /// Short weekday names in grid order, for example Mon to Sun.
    public let weekdaySymbols: [String]

    public init(containing date: Date, history: [SessionRecord], calendar: Calendar = .current) {
        let month = calendar.dateInterval(of: .month, for: date) ?? DateInterval(start: calendar.startOfDay(for: date), duration: 31 * 86_400)
        interval = month
        let symbols = calendar.shortWeekdaySymbols
        weekdaySymbols = (0..<7).map { symbols[(calendar.firstWeekday - 1 + $0) % 7] }
        let firstWeekday = calendar.component(.weekday, from: month.start)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        let gridStart = calendar.date(byAdding: .day, value: -leading, to: month.start)!
        let monthDays = calendar.range(of: .day, in: .month, for: month.start)?.count ?? 30
        let cells = Int((Double(leading + monthDays) / 7).rounded(.up)) * 7
        let reports = TrainingMonth.unique(history).map(WorkoutReport.init)
        days = (0..<cells).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: gridStart) else { return nil }
            return CalendarDay(date: day, inMonth: month.contains(day) && day < month.end,
                               reports: reports.filter { calendar.isDate($0.date, inSameDayAs: day) }.sorted { $0.date < $1.date })
        }
    }

    public var trainedDays: Int { days.filter { $0.inMonth && $0.trained }.count }

    static func unique(_ history: [SessionRecord]) -> [SessionRecord] {
        var seen = Set<UUID>()
        return history.filter { $0.date.timeIntervalSince1970.isFinite && seen.insert($0.id).inserted }
    }
}

/// This week against the one before, from the same history.
public struct WeekComparison: Sendable {
    public let thisWeek: WeekReport
    public let lastWeek: WeekReport

    public init(history: [SessionRecord], now: Date = Date(), calendar: Calendar = .current) {
        let unique = TrainingMonth.unique(history)
        thisWeek = WeekReport(history: unique, containing: now, calendar: calendar)
        lastWeek = WeekReport(history: unique, containing: calendar.date(byAdding: .day, value: -7, to: now) ?? now, calendar: calendar)
    }

    /// Mean rep duration over timed reps, and mean Apple Watch heart rate over recorded samples; nil without data.
    public var averageRepSeconds: (this: Double?, last: Double?) { (Self.repSeconds(thisWeek), Self.repSeconds(lastWeek)) }
    public var averageHeartRate: (this: Double?, last: Double?) { (Self.heartRate(thisWeek), Self.heartRate(lastWeek)) }
    static func repSeconds(_ week: WeekReport) -> Double? {
        let values = week.sessions.flatMap(\.sets).flatMap(\.repDurations)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
    static func heartRate(_ week: WeekReport) -> Double? {
        let values = week.sessions.flatMap(\.heartRate.samples).map(\.value)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    public var trainingDays: (this: Int, last: Int) { (thisWeek.days.filter { $0.setCount > 0 }.count, lastWeek.days.filter { $0.setCount > 0 }.count) }

    /// A change against last week in words. There is never a percentage from a zero week.
    public static func delta(_ current: Double, _ previous: Double, unit: String = "") -> String {
        if current == previous { return "Same as last week" }
        if previous == 0 { return "New this week" }
        let change = current - previous
        let amount = change.rounded() == change ? String(Int(abs(change))) : String(format: "%.1f", abs(change))
        return "\(change > 0 ? "+" : "−")\(amount)\(unit) vs last week"
    }

    /// Plain statements about the week, each one a count from the history.
    public var highlights: [String] {
        var lines: [String] = []
        let sets = (thisWeek.setCount, lastWeek.setCount), days = trainingDays
        if sets.0 == 0 { lines.append(sets.1 == 0 ? "No sets recorded this week or last week yet." : "No sets recorded yet this week; last week had \(sets.1).") }
        else if sets.1 == 0 { lines.append("\(sets.0) sets this week; none were recorded the week before.") }
        else { lines.append("\(sets.0) sets this week, \(sets.0 >= sets.1 ? "up from" : "down from") \(sets.1) last week.") }
        if days.this > 0 { lines.append("Trained on \(days.this) \(days.this == 1 ? "day" : "days") this week (last week: \(days.last)).") }
        if let top = thisWeek.categories.max(by: { $0.setCount < $1.setCount }) {
            lines.append("Most of the work went to \(top.category.rawValue.lowercased()): \(top.setCount) \(top.setCount == 1 ? "set" : "sets").")
        }
        let all = thisWeek.sessions.flatMap(\.sets)
        let camera = all.filter { $0.source == .camera }.count
        if !all.isEmpty { lines.append("\(camera) of \(all.count) sets were counted by the camera; the rest were logged by you.") }
        let withHeartRate = thisWeek.sessions.filter { !$0.heartRate.samples.isEmpty }.count
        if !thisWeek.sessions.isEmpty {
            lines.append(withHeartRate == 0 ? "No Apple Watch heart-rate readings this week; missing readings are never shown as zero."
                         : "Apple Watch heart rate was recorded in \(withHeartRate) of \(thisWeek.sessions.count) sessions.")
        }
        return lines
    }
}

/// The last 30 days as a heatmap: each day's rep volume, a level from 0 (no session) to 4 set by the person's own
/// training days (quartiles, not fixed thresholds), and the current and best runs of training days.
public struct ConsistencyStrip: Sendable {
    public struct Day: Identifiable, Sendable {
        public let date: Date
        public let trained: Bool
        /// Reps plus held seconds that day.
        public let volume: Int
        public let level: Int
        public var id: Date { date }
    }
    public let days: [Day]

    public init(history: [SessionRecord], now: Date = Date(), length: Int = 30, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        let reports = TrainingMonth.unique(history).map(WorkoutReport.init).filter { $0.setCount > 0 }
        let dates = (0..<length).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        let volumes = dates.map { day in
            reports.filter { calendar.isDate($0.date, inSameDayAs: day) }.reduce((trained: false, volume: 0)) { ($0.trained || true, $0.volume + $1.reps + Int($1.holdSeconds)) }
        }
        let sorted = volumes.filter(\.trained).map(\.volume).sorted()
        func quartile(_ q: Double) -> Int { sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * q))] }
        let cuts = [quartile(0.25), quartile(0.5), quartile(0.75)]
        days = zip(dates, volumes).map { date, value in
            Day(date: date, trained: value.trained, volume: value.volume,
                level: value.trained ? 1 + cuts.filter { value.volume > $0 }.count : 0)
        }
    }

    public var trainedDays: Int { days.filter(\.trained).count }
    /// Consecutive training days ending today, or ending yesterday while today has no session yet.
    public var currentStreak: Int {
        var run = days
        if run.last?.trained == false { run.removeLast() }
        return run.reversed().prefix { $0.trained }.count
    }
    /// The longest run of consecutive training days in the strip.
    public var bestStreak: Int {
        days.reduce(into: (best: 0, run: 0)) { state, day in
            state.run = day.trained ? state.run + 1 : 0
            state.best = max(state.best, state.run)
        }.best
    }
}

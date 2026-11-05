import Foundation

public struct TrainingDashboard: Sendable {
    public struct Day: Identifiable, Sendable {
        public let date: Date
        public let setCount: Int
        public var id: Date { date }
    }
    public let days: [Day]
    public let trainingDays: Int
    public let sessionCount: Int
    public let totalSets: Int
    public let totalReps: Int
    public let latestRecord: SessionRecord?
    public let recentRecords: [SessionRecord]

    public init(history: [SessionRecord], now: Date = Date(), calendar: Calendar = .current) {
        let interval = calendar.dateInterval(of: .weekOfYear, for: now)
            ?? DateInterval(start: calendar.startOfDay(for: now), duration: 7 * 86_400)
        let start = interval.start
        let eligible = history.filter {
            $0.date.timeIntervalSince1970.isFinite && $0.date <= now && !TrainingCalendar.isSample($0.id)
        }
        let unique = eligible.reduce(into: [UUID: SessionRecord]()) { records, record in
            if records[record.id] == nil { records[record.id] = record }
        }
        let actual = unique.values.map { (record: $0, counts: Self.activityCounts($0)) }
            .filter { $0.counts.sets > 0 }.sorted { $0.record.date > $1.record.date }
        recentRecords = actual.map(\.record)
        latestRecord = actual.first?.record
        let week = actual.filter { $0.record.date >= start && $0.record.date < interval.end }
        sessionCount = week.count
        totalSets = week.reduce(0) { $0 + $1.counts.sets }
        totalReps = week.reduce(0) { $0 + $1.counts.reps }
        days = (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: start).map { date in
                let count = week.filter { calendar.isDate($0.record.date, inSameDayAs: date) }
                    .reduce(0) { $0 + $1.counts.sets }
                return Day(date: date, setCount: count)
            }
        }
        trainingDays = days.filter { $0.setCount > 0 }.count
    }

    private static func activityCounts(_ record: SessionRecord) -> (sets: Int, reps: Int) {
        let quantities = record.sets.map { (id: $0.id, source: $0.source, reps: $0.reps, seconds: 0.0) }
            + record.loggedSets.map { (id: $0.id, source: $0.source, reps: $0.reps, seconds: $0.seconds) }
        let unique = quantities.reduce(into: [UUID: (source: InputSource, reps: Int, seconds: Double)]()) { values, item in
            if values[item.id] == nil { values[item.id] = (item.source, item.reps, item.seconds) }
        }
        let activity = unique.values.filter {
            $0.source != .video && ($0.reps > 0 || ($0.seconds.isFinite && $0.seconds > 0))
        }
        return (activity.count, activity.reduce(0) { $0 + $1.reps })
    }
}

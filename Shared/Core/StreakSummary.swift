import Foundation

public struct StreakSummary: Sendable {
    public let currentStreak: Int
    public let longestStreak: Int
    public let daysThisWeek: Int
    public let totalTrainingDays: Int
    public let trainedToday: Bool

    public init(history: [SessionRecord], now: Date = Date(), calendar: Calendar = .current) {
        var sessionIDs = Set<UUID>(), setIDs = Set<UUID>()
        let dates = history.filter { $0.date.timeIntervalSince1970.isFinite && $0.date <= now }
            .sorted { $0.date < $1.date }
            .filter { sessionIDs.insert($0.id).inserted }
            .compactMap { session -> Date? in
                let tracked = session.sets.filter { $0.source != .video && $0.reps > 0 }.map(\.id)
                let logged = session.loggedSets.filter {
                    $0.source != .video && ($0.reps > 0 || ($0.seconds.isFinite && $0.seconds > 0))
                }.map(\.id)
                let distinct = (tracked + logged).filter { setIDs.insert($0).inserted }
                return distinct.isEmpty ? nil : calendar.startOfDay(for: session.date)
            }
        let days = Set(dates)
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        trainedToday = days.contains(today)
        totalTrainingDays = days.count
        let week = calendar.dateInterval(of: .weekOfYear, for: now)
        daysThisWeek = days.filter { day in week.map { day >= $0.start && day < $0.end } ?? false }.count
        var cursor = trainedToday ? today : yesterday
        var streak = 0
        while days.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        currentStreak = streak
        longestStreak = days.sorted().reduce((last: Date?.none, run: 0, best: 0)) { state, day in
            let consecutive = state.last.flatMap { calendar.date(byAdding: .day, value: 1, to: $0) } == day
            let run = consecutive ? state.run + 1 : 1
            return (day, run, max(state.best, run))
        }.best
    }
}

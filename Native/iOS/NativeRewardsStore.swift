import Foundation
import Observation

@MainActor @Observable
final class NativeRewardsStore {
    enum Failure: Error { case unreadableHistory, recordNotSaved }
    private(set) var ledger: GamificationLedger
    private(set) var loadError: String?
    private let url: URL

    init(url: URL, createdAt: Date = Date(), calendar: Calendar = .current) {
        self.url = url
        ledger = GamificationLedger(createdAt: createdAt, calendar: calendar)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do { ledger = try JSONDecoder().decode(GamificationLedger.self, from: Data(contentsOf: url)) }
        catch { loadError = "Your saved rewards couldn’t be read. They haven’t been changed. Reset workout history to reset rewards." }
    }

    func schedule(startHour: Int, at date: Date) throws {
        try requireReadable()
        var candidate = ledger
        try candidate.scheduleWindow(DailyXPWindow(startHour: startHour), at: date)
        try save(candidate)
    }

    func award(record: SessionRecord, before: [SessionRecord], history: [SessionRecord], completedAt: Date) throws {
        try requireReadable()
        guard !before.contains(where: { $0.id == record.id }),
              !ledger.events.contains(where: { $0.sessionID == record.id }) else { return }
        guard history.contains(record) else { throw Failure.recordNotSaved }
        let delta = max(0, baseXP(history: history) - baseXP(history: before))
        var candidate = ledger
        try candidate.awardCompletion(record: record, completedAt: completedAt, eligibleBaseXP: delta, now: completedAt)
        try save(candidate)
    }

    func totalXP(history: [SessionRecord]) -> Int {
        baseXP(history: history) + reconciled(history: history).totalBonusXP
    }

    func summary(history: [SessionRecord], at date: Date) -> GamificationSummary {
        let candidate = reconciled(history: history)
        return candidate.summary(at: date, baselineActivityDays: baselineDays(history: history, ledger: candidate, at: date))
    }

    func advance(history: [SessionRecord], at date: Date, plannedRestDays: [Date] = []) throws {
        try requireReadable()
        var candidate = reconciled(history: history)
        candidate.advance(to: date, plannedRestDays: plannedRestDays,
                          baselineActivityDays: baselineDays(history: history, ledger: candidate, at: date))
        guard candidate.events != ledger.events || candidate.frozenDays != ledger.frozenDays || candidate.restDays != ledger.restDays else { return }
        try save(candidate)
    }

    func reset(at date: Date) throws {
        guard date.timeIntervalSince1970.isFinite else { throw GamificationLedger.Invalid.date }
        try save(GamificationLedger(createdAt: date, calendar: ledger.calendar))
        loadError = nil
    }

    private func requireReadable() throws {
        if loadError != nil { throw Failure.unreadableHistory }
    }

    private func save(_ candidate: GamificationLedger) throws {
        let data = try JSONEncoder().encode(candidate)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        ledger = candidate
    }

    private func baseXP(history: [SessionRecord]) -> Int {
        let progress = SkillProgress.evaluate(history: history, calendar: ledger.calendar)
        return TrainingAttribute.allCases.reduce(0) { $0 + progress.points(for: $1) }
    }

    private func reconciled(history: [SessionRecord]) -> GamificationLedger {
        let retained = Set(history.map(\.id))
        var candidate = ledger
        for event in ledger.events where !retained.contains(event.sessionID) { candidate.removeCompletion(sessionID: event.sessionID) }
        return candidate
    }

    private func baselineDays(history: [SessionRecord], ledger: GamificationLedger, at date: Date) -> [Date] {
        let represented = Set(ledger.events.map(\.sessionID))
        return Array(StreakSummary.activityDays(history: history.filter { !represented.contains($0.id) }, now: date, calendar: ledger.calendar))
    }
}

import Foundation
import Observation

@MainActor @Observable final class ProgrammeStore {
    let scope: AccountDataScope
    private let profile: NativeProfileStore
    private(set) var archive: ProgrammeArchive
    private(set) var weights: [DatedWeight] = []
    private(set) var error: String?
    private var readable = true
    private var active = true
    func setActive(_ active: Bool) { self.active = active }
    var protectedDayIDs: () -> Set<String> = { [] }
    weak var sync: ProgrammeSyncStore?
    var current: TrainingProgramme? { archive.currentAge == profile.profile?.programmePreferences?.ageContext ? archive.current : nil }
    init(scope: AccountDataScope, profile: NativeProfileStore) {
        self.scope = scope; self.profile = profile
        archive = ProgrammeArchive(owner: .init(accountID: scope.accountID, profileID: scope.profileID))
        do {
            if FileManager.default.fileExists(atPath: scope.file("programme.json").path) {
                let saved = try JSONDecoder().decode(ProgrammeArchive.self, from: Data(contentsOf: scope.file("programme.json")))
                guard saved.owner == archive.owner else { throw AccountFailure.invalidResponse }
                archive = saved
            }
            if FileManager.default.fileExists(atPath: scope.file("weights.json").path) {
                weights = try JSONDecoder().decode([DatedWeight].self, from: Data(contentsOf: scope.file("weights.json")))
            }
        } catch { readable = false; self.error = "Your saved programme or measurements could not be read. The files have been preserved." }
    }
    func preview(profile: LocalProfile, history: [SessionRecord], at date: Date, calendar: Calendar = .current) throws -> TrainingProgramme {
        try requirePolicy()
        var preview = archive
        return try preview.reconcile(profile: profile, history: history, protecting: protectedDayIDs(), at: date, calendar: calendar)
    }

    func acceptPreview(_ week: TrainingProgramme, profile: LocalProfile) throws {
        try requirePolicy()
        if archive.snapshots.contains(week) { return }
        var next = archive
        try next.install(week, profile: profile, history: HistoryStore(url: scope.file("history.json")).load(), protecting: protectedDayIDs(), at: .now)
        try save(next)
    }
    @discardableResult func prepare(profile: LocalProfile, history: [SessionRecord], at date: Date = .now, calendar: Calendar = .current) throws -> TrainingProgramme {
        try requirePolicy()
        var next = archive
        let week = try next.prepare(profile: profile, history: history, at: date, calendar: calendar)
        if next != archive { try save(next) }
        return week
    }
    @discardableResult func reconcile(profile: LocalProfile, history: [SessionRecord], protecting: Set<String>, at date: Date = .now, calendar: Calendar = .current) throws -> TrainingProgramme {
        try requirePolicy()
        var next = archive
        let week = try next.reconcile(profile: profile, history: history, protecting: protecting, at: date, calendar: calendar)
        if next != archive { try save(next) }
        return week
    }
    @discardableResult func revise(profile: LocalProfile, history: [SessionRecord], protecting: Set<String>, at date: Date = .now, calendar: Calendar = .current) throws -> TrainingProgramme {
        try requirePolicy()
        var next = archive
        let week = try next.revise(profile: profile, history: history, protecting: protecting, at: date, calendar: calendar)
        try save(next)
        return week
    }
    @discardableResult func adjust(dayID: String, action: ProgrammeArchive.Adjustment, history: [SessionRecord], protecting: Set<String>, at date: Date = .now, calendar: Calendar = .current) throws -> TrainingProgramme {
        try requirePolicy()
        guard let profile = profile.profile else { throw AccountFailure.checkpointRequired }
        var next = archive
        let result = try next.adjust(dayID: dayID, action: action, profile: profile, history: history, protecting: protecting, at: date, calendar: calendar)
        try save(next)
        return result
    }
    func day(at date: Date = .now, calendar: Calendar = .current) -> TrainingProgramme.Day? {
        archive.week(at: date, calendar: calendar)?.days.first { calendar.isDate($0.date, inSameDayAs: date) }
    }
    func capture(dayID: String?, at date: Date = .now) -> SessionTrainingContext {
        let week = archive.week(at: date)
        let matches = dayID != nil && day(at: date)?.id == dayID
        return SessionTrainingContext(owner: archive.owner, age: profile.profile?.programmePreferences?.ageContext,
            programmeID: matches ? week?.id : nil, programmeRevision: matches ? week?.revision : nil)
    }
    func recordWeight(kilograms: Double, date: Date, now: Date = .now) throws {
        try requirePolicy()
        guard profile.profile?.programmePreferences?.ageContext?.ageYears ?? 0 >= 18, date <= now else { throw AccountFailure.checkpointRequired }
        let entry = try DatedWeight(date: date, kilograms: kilograms)
        let next = (weights + [entry]).sorted { $0.date < $1.date }
        try ProtectedLocalStorage.write(JSONEncoder().encode(next), to: scope.file("weights.json"))
        weights = next
    }
    func restore(_ week: TrainingProgramme?, profile: LocalProfile) throws {
        try requirePolicy()
        guard let week else { return }
        var next = archive
        let history = try HistoryStore(url: scope.file("history.json")).load()
        try next.install(week, profile: profile, history: history, protecting: protectedDayIDs(), at: .now)
        try save(next)
    }
    private func save(_ next: ProgrammeArchive) throws {
        try requirePolicy()
        try ProtectedLocalStorage.write(JSONEncoder().encode(next), to: scope.file("programme.json"))
        archive = next; error = nil
    }
    private func requirePolicy() throws {
        guard active, readable, profile.permitsPolicyCallbacks else { throw AccountFailure.checkpointRequired }
    }
}

import Foundation
import Observation

@MainActor @Observable final class QuestStore {
    enum Failure: Error { case unavailable, staleChoice, unreadable }
    private(set) var archive: QuestArchive
    private(set) var error: String?
    let programme: ProgrammeStore
    let profile: NativeProfileStore
    private let scope: AccountDataScope
    private let capturedAge: TrainingAgeContext?
    private let year: QuestCalendar.Year?
    private var active = true
    private var readable = true
    init(scope: AccountDataScope, profile: NativeProfileStore, programme: ProgrammeStore) {
        self.scope = scope; self.profile = profile; self.programme = programme
        capturedAge = profile.profile?.programmePreferences?.ageContext
        archive = QuestArchive(owner: .init(accountID: scope.accountID, profileID: scope.profileID))
        year = try? QuestCalendar.bundled()
        do {
            if FileManager.default.fileExists(atPath: scope.file("quests.json").path) {
                let saved = try JSONDecoder().decode(QuestArchive.self, from: Data(contentsOf: scope.file("quests.json")))
                guard saved.owner == archive.owner else { throw Failure.unreadable }
                archive = saved
            }
        } catch { readable = false; self.error = "Your saved quests couldn’t be read. The original file has been preserved." }
    }
    private var valid: Bool { active && profile.permitsPolicyCallbacks && capturedAge != nil && capturedAge == profile.profile?.programmePreferences?.ageContext }
    func choices(history: [SessionRecord], weekly: Bool = false) -> [Quest] {
        guard valid, let year, let person = profile.profile else { return [] }
        return QuestCalendar.choices(year: year, profile: person, programme: programme.current, history: history, at: programme.referenceDate, calendar: programme.localCalendar, weekly: weekly)
    }
    func progress(_ quest: Quest, history: [SessionRecord]) -> QuestEvidence {
        QuestProgress.evaluate(quest, owner: archive.owner, currentAge: valid ? capturedAge : nil, history: history, checkIns: archive.checkIns, now: programme.referenceDate, calendar: programme.localCalendar)
    }
    func checkIn(_ quest: Quest, history: [SessionRecord]) throws {
        try require(quest, history: history)
        guard quest.exerciseID == nil, let capturedAge else { throw Failure.staleChoice }
        var next = archive
        next.checkIn(kind: quest.kind, age: capturedAge, at: programme.referenceDate, calendar: programme.localCalendar)
        try save(next)
    }
    @discardableResult func claim(_ quest: Quest, history: [SessionRecord]) throws -> Bool {
        try require(quest, history: history)
        var next = archive
        let awarded = next.claim(quest, currentAge: capturedAge, history: history, now: programme.referenceDate, calendar: programme.localCalendar)
        if awarded { try save(next) }
        return awarded
    }
    func reconcile(history: [SessionRecord]) throws {
        guard valid else { throw Failure.unavailable }
        var next = archive
        next.reconcile(currentAge: capturedAge, history: history, now: programme.referenceDate, calendar: programme.localCalendar)
        if next != archive { try save(next) }
    }
    func removeCheckIn(id: UUID, history: [SessionRecord]) throws {
        guard valid else { throw Failure.unavailable }
        var next = archive
        next.removeCheckIn(id: id)
        next.reconcile(currentAge: capturedAge, history: history, now: programme.referenceDate, calendar: programme.localCalendar)
        try save(next)
    }
    func setActive(_ active: Bool) { self.active = active }
    private func require(_ quest: Quest, history: [SessionRecord]) throws {
        guard valid else { throw Failure.unavailable }
        guard (choices(history: history) + choices(history: history, weekly: true)).contains(quest) else { throw Failure.staleChoice }
    }
    private func save(_ next: QuestArchive) throws {
        guard readable else { throw Failure.unreadable }
        try ProtectedLocalStorage.write(JSONEncoder().encode(next), to: scope.file("quests.json"))
        archive = next
    }
}

import Foundation
import Testing
@testable import SpottrCore

private func journeyProfile(age: Int = 30, days: Set<Int> = Set(1...7), minutes: Int = 20) throws -> LocalProfile {
    try LocalProfile(programmePreferences: .init(goals: [.balance, .strength], weekdays: days, minutesPerSession: minutes,
        ageContext: .init(ageYears: age, guardianManaged: age < 18)))
}
private let journeyDate = Date(timeIntervalSince1970: 1793577600)
private var journeyCalendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/London")!; return c }

@Test func programmeJourneyPersistsScopeStableWeekAndEveryRevision() throws {
    let owner = WorkoutOwner(accountID: UUID(), profileID: UUID())
    var archive = ProgrammeArchive(owner: owner)
    let profile = try journeyProfile()
    let first = try archive.prepare(profile: profile, history: [], at: journeyDate, calendar: journeyCalendar)
    #expect(first.days.first?.plan?.items.count ?? 0 > 1)
    let restored = try JSONDecoder().decode(ProgrammeArchive.self, from: JSONEncoder().encode(archive))
    #expect(restored.owner == owner)
    archive = restored
    #expect(try archive.prepare(profile: journeyProfile(minutes: 10), history: [], at: journeyDate.addingTimeInterval(3600), calendar: journeyCalendar) == first)
    let changed = try archive.revise(profile: journeyProfile(minutes: 10), history: [], protecting: [first.days[0].id], at: journeyDate, calendar: journeyCalendar)
    #expect(changed.revision == 2)
    #expect(changed.days[0] == first.days[0])
    #expect(archive.snapshots.count == 2)
    #expect(archive.snapshots.first == first)
    #expect(try archive.prepare(profile: profile, history: [], at: journeyDate.addingTimeInterval(8 * 86400), calendar: journeyCalendar).id != first.id)
}

@Test func programmeJourneyProtectsPastCompletedAndActiveAndFamilyHasNoSets() throws {
    var archive = ProgrammeArchive(owner: .init(accountID: UUID(), profileID: UUID()))
    let first = try archive.prepare(profile: journeyProfile(), history: [], at: journeyDate, calendar: journeyCalendar)
    let history = [SessionRecord(id: UUID(), date: first.days[1].date, sets: [], plannedWorkoutID: first.days[1].id)]
    let revised = try archive.revise(profile: journeyProfile(days: [7], minutes: 10), history: history, protecting: [first.days[3].id], at: first.days[2].date, calendar: journeyCalendar)
    for index in [0, 1, 3] { #expect(revised.days[index] == first.days[index]) }
    var family = ProgrammeArchive(owner: .init(accountID: UUID(), profileID: UUID()))
    let week = try family.prepare(profile: journeyProfile(age: 3), history: [], at: journeyDate, calendar: journeyCalendar)
    #expect(week.days.allSatisfy { $0.kind == .familyMovement && $0.plan == nil })
}

@Test func programmeInsightsUsesOnlyActualEffortAndDatedWeights() throws {
    let rated = LoggedSet(id: UUID(), exerciseID: "squat", reps: 3, seconds: 0, source: .manual, reason: .voluntary, effort: .hard)
    let unknown = LoggedSet(id: UUID(), exerciseID: "squat", reps: 2, seconds: 0, source: .manual, reason: .voluntary)
    let video = LoggedSet(id: UUID(), exerciseID: "squat", reps: 20, seconds: 0, source: .video, reason: .voluntary, effort: .veryHard)
    let record = SessionRecord(id: UUID(), date: journeyDate, sets: [], loggedSets: [rated, unknown, video])
    let points = ProgrammeInsights.effort(history: [record, record], exerciseID: "squat")
    #expect(points.count == 2)
    #expect(points.first?.effort == .hard)
    #expect(points.last?.effort == nil)
    let weight = try DatedWeight(date: journeyDate, kilograms: 72.5)
    #expect(weight.date == journeyDate)
    #expect(throws: Error.self) { try DatedWeight(date: journeyDate, kilograms: .nan) }
    #expect(throws: Error.self) { try DatedWeight(date: journeyDate, kilograms: 0) }
}

@Test func programmeSessionContextSurvivesCodecAndLateWatchImport() throws {
    let owner = WorkoutOwner(accountID: UUID(), profileID: UUID())
    let context = SessionTrainingContext(owner: owner, age: try .init(ageYears: 12, guardianManaged: true), programmeID: "week:Europe/London:2026-11-02", programmeRevision: 2)
    let record = SessionRecord(id: UUID(), date: journeyDate, sets: [], endedAt: journeyDate.addingTimeInterval(20), plannedWorkoutID: "day", trainingContext: context)
    let decoded = try JSONDecoder().decode(SessionRecord.self, from: JSONEncoder().encode(record))
    let merged = try WatchTelemetryImporter.merge([WatchTelemetry(sessionID: record.id, sentAt: journeyDate, heartRate: .init(value: 90, date: journeyDate), accelerationG: nil, rotationRadiansPerSecond: nil)], into: decoded, through: journeyDate.addingTimeInterval(30))
    #expect(merged.trainingContext == context)
    #expect(merged.plannedWorkoutID == "day")
}

@Test func programmeAdjustmentsChangeOnlyFutureUnstartedDay() throws {
    var archive = ProgrammeArchive(owner: .init(accountID: UUID(), profileID: UUID()))
    let profile = try journeyProfile()
    let week = try archive.prepare(profile: profile, history: [], at: journeyDate, calendar: journeyCalendar)
    let target = week.days[1]
    let easier = try archive.adjust(dayID: target.id, action: .easier, profile: profile, history: [], protecting: [], at: journeyDate, calendar: journeyCalendar)
    #expect(easier.revision == 2)
    #expect(easier.days[0] == week.days[0])
    #expect(easier.days[1].plan != target.plan)
    #expect(throws: Error.self) { try archive.adjust(dayID: target.id, action: .rest, profile: profile, history: [], protecting: [target.id], at: journeyDate, calendar: journeyCalendar) }
    let rest = try archive.adjust(dayID: target.id, action: .rest, profile: profile, history: [], protecting: [], at: journeyDate, calendar: journeyCalendar)
    #expect(rest.days[1].kind == .rest)
    #expect(rest.days[1].plan == nil)
    #expect(archive.snapshots.first == week)
}

@Test func programmeJourneyAgeCorrectionCannotReuseAdultWeek() throws {
    var archive = ProgrammeArchive(owner: .init(accountID: UUID(), profileID: UUID()))
    let adult = try archive.prepare(profile: journeyProfile(), history: [], at: journeyDate, calendar: journeyCalendar)
    let family = try archive.prepare(profile: journeyProfile(age: 3), history: [], at: journeyDate, calendar: journeyCalendar)
    #expect(family.days.allSatisfy { $0.plan == nil })
    #expect(family.revision > adult.revision)
    #expect(archive.snapshots.first == adult)
}

@Test func programmeRestorationMergesProtectedDaysAndKeepsUniqueLocalRevisions() throws {
    var archive = ProgrammeArchive(owner: .init(accountID: UUID(), profileID: UUID()))
    let profile = try journeyProfile()
    let original = try archive.prepare(profile: profile, history: [], at: journeyDate, calendar: journeyCalendar)
    let changed = try ProgrammePlanner.makeWeek(profile: journeyProfile(minutes: 10), history: [], start: journeyDate, calendar: journeyCalendar)
    let done = SessionRecord(id: UUID(), date: original.days[0].date, sets: [], plannedWorkoutID: original.days[0].id)
    try archive.install(changed, profile: profile, history: [done], protecting: [], at: journeyDate)
    #expect(archive.current?.days[0] == original.days[0])
    #expect(archive.current?.days[1] == changed.days[1])
    #expect(archive.current?.revision == original.revision + 1)
    #expect(archive.snapshots.first == original)
}

@Test func programmeReconciliationRetainsAcceptedRemoteEditsUntilPreferencesChange() throws {
    var archive = ProgrammeArchive(owner: .init(accountID: UUID(), profileID: UUID()))
    let profile = try journeyProfile()
    let original = try archive.prepare(profile: profile, history: [], at: journeyDate, calendar: journeyCalendar)
    let changed = try archive.adjust(dayID: original.days[1].id, action: .rest, profile: profile, history: [], protecting: [], at: journeyDate, calendar: journeyCalendar)
    var restored = ProgrammeArchive(owner: archive.owner)
    try restored.install(changed, profile: profile, history: [], protecting: [], at: journeyDate)
    let accepted = try JSONDecoder().decode(ProgrammeArchive.self, from: JSONEncoder().encode(restored))
    restored = accepted
    #expect(try restored.reconcile(profile: profile, history: [], protecting: [], at: journeyDate, calendar: journeyCalendar) == accepted.current)
    let revised = try restored.reconcile(profile: journeyProfile(minutes: 10), history: [], protecting: [changed.days[0].id], at: journeyDate, calendar: journeyCalendar)
    #expect(revised.revision > changed.revision)
    #expect(revised.days[0] == changed.days[0])
}

@Test func programmeProgressDeduplicatesActualSetsAndDoesNotCompletePartialWork() throws {
    let week = try ProgrammePlanner.makeWeek(profile: journeyProfile(), history: [], start: journeyDate, calendar: journeyCalendar)
    let set = LoggedSet(id: UUID(), exerciseID: "squat", reps: 3, seconds: 0, source: .manual, reason: .voluntary, effort: .hard)
    let first = SessionRecord(id: UUID(), date: journeyDate, sets: [], loggedSets: [set], plannedWorkoutID: week.days[0].id)
    let late = SessionRecord(id: UUID(), date: journeyDate, sets: [], loggedSets: [set], plannedWorkoutID: week.days[0].id)
    let progress = ProgrammeInsights.progress(week: week, history: [first, late])[0]
    #expect(progress.recordedSets == 1)
    #expect(progress.recordedReps == 3)
    #expect(!progress.completed)
}

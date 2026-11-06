import Foundation
import XCTest
@testable import SpottrCore

final class QuestCalendarTests: XCTestCase {
    func testBundledYearProvidesEveryDailyAndWeeklyChoice() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Shared/Core/Resources/quest-calendar.json"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let daily = try XCTUnwrap(json["daily"] as? [[String: Any]])
        let weekly = try XCTUnwrap(json["weekly"] as? [[String: Any]])
        XCTAssertEqual(daily.count, 366)
        XCTAssertEqual(weekly.count, 53)
        XCTAssertTrue(daily.allSatisfy { ($0["options"] as? [String])?.count == 3 })
        XCTAssertTrue(weekly.allSatisfy { ($0["options"] as? [String])?.count == 2 })
    }
}

private let questOwner = WorkoutOwner(accountID: UUID(), profileID: UUID())
private func qDate(_ string: String) -> Date { ISO8601DateFormatter().date(from: string)! }
private func qCalendar(_ zone: String = "UTC") -> Calendar {
    var result = Calendar(identifier: .gregorian); result.timeZone = TimeZone(identifier: zone)!; return result
}
private func qProfile(age: Int = 30) throws -> LocalProfile {
    try LocalProfile(name: "Practice", programmePreferences: ProgrammePreferences(goals: [.balance], weekdays: [1, 3, 5], availableSupport: ["Stable chair"], ageContext: TrainingAgeContext(ageYears: age, guardianManaged: age < 18)))
}
private func qRecord(quest: Quest, age: TrainingAgeContext, source: InputSource = .manual, owner: WorkoutOwner = questOwner, id: UUID = UUID(), date: Date? = nil, origin: LoggedSet.QuantityOrigin? = .cameraObserved) -> SessionRecord {
    let entry = ExerciseCatalog.find(quest.exerciseID!)!
    return SessionRecord(id: id, date: date ?? quest.startsAt.addingTimeInterval(3600), sets: [], loggedSets: [LoggedSet(id: UUID(), exerciseID: entry.id, reps: entry.unit == .reps ? quest.target : 0, seconds: entry.unit == .seconds ? Double(quest.target) : 0, source: source, reason: .voluntary, quantityOrigin: source == .camera ? origin : .selfReport)], trainingContext: SessionTrainingContext(owner: owner, age: age, programmeID: nil, programmeRevision: nil))
}
extension QuestCalendarTests {
    func testLeapSlotIsStableAcrossNonLeapYearsAndWeekly53Exists() throws {
        let calendar = qCalendar()
        XCTAssertEqual(QuestCalendar.dailySlot(at: qDate("2024-02-29T12:00:00Z"), calendar: calendar), 60)
        XCTAssertEqual(QuestCalendar.dailySlot(at: qDate("2025-03-01T12:00:00Z"), calendar: calendar), 61)
        XCTAssertEqual(QuestCalendar.dailySlot(at: qDate("2026-12-31T12:00:00Z"), calendar: calendar), 366)
        let profile = try qProfile(), now = qDate("2026-12-31T12:00:00Z")
        let quests = QuestCalendar.choices(year: try QuestCalendar.bundled(), profile: profile, programme: nil, history: [], at: now, calendar: calendar, weekly: true)
        XCTAssertEqual(quests.count, 2)
        XCTAssertTrue(quests.allSatisfy { $0.periodID == "week:2026:53" })
    }
    func testRealJuniorPlanCreatesReachablePracticeAndRecoveryNeverDemandsExercise() throws {
        let now = qDate("2026-11-06T12:00:00Z"), calendar = qCalendar(), profile = try qProfile(age: 8)
        let week = try ProgrammePlanner.makeWeek(profile: profile, history: [], start: now, calendar: calendar)
        let quests = QuestCalendar.choices(year: try QuestCalendar.bundled(), profile: profile, programme: week, history: [], at: now, calendar: calendar)
        XCTAssertEqual(quests.count, 3)
        let practice = try XCTUnwrap(quests.first { $0.kind == .practice })
        XCTAssertLessThanOrEqual(practice.target, 10)
        let age = profile.programmePreferences!.ageContext!
        let record = qRecord(quest: practice, age: age)
        XCTAssertTrue(QuestProgress.evaluate(practice, owner: questOwner, currentAge: age, history: [record], checkIns: [], now: now, calendar: calendar).isComplete)
        let rest = try XCTUnwrap(week.days.first { $0.kind == .rest })
        let recovery = QuestCalendar.choices(year: try QuestCalendar.bundled(), profile: profile, programme: week, history: [], at: rest.date, calendar: calendar)
        XCTAssertEqual(recovery.count, 3)
        XCTAssertTrue(recovery.allSatisfy { $0.exerciseID == nil })
    }
    func testUnderFiveAndUnknownAbilityNeverReceiveAdultOrFabricatedSetQuests() throws {
        let now = qDate("2026-11-06T12:00:00Z"), calendar = qCalendar(), profile = try qProfile(age: 4)
        let quests = QuestCalendar.choices(year: try QuestCalendar.bundled(), profile: profile, programme: nil, history: [], at: now, calendar: calendar)
        XCTAssertEqual(quests.count, 3)
        XCTAssertTrue(quests.allSatisfy { $0.exerciseID == nil && $0.target == 0 })
        XCTAssertTrue(quests.contains { $0.kind == .familyActivity })
    }
    func testActualEvidenceDeduplicatesImportRejectsCameraForgeryAndForeignAgeAndRevokesDeletion() throws {
        let now = qDate("2026-11-06T12:00:00Z"), calendar = qCalendar(), profile = try qProfile()
        let week = try ProgrammePlanner.makeWeek(profile: profile, history: [], start: now, calendar: calendar)
        let quest = try XCTUnwrap(QuestCalendar.choices(year: try QuestCalendar.bundled(), profile: profile, programme: week, history: [], at: now, calendar: calendar).first { $0.kind == .practice })
        let age = profile.programmePreferences!.ageContext!, record = qRecord(quest: quest, age: age)
        var archive = QuestArchive(owner: questOwner)
        XCTAssertFalse(archive.claim(quest, currentAge: age, history: [], now: now, calendar: calendar))
        XCTAssertTrue(archive.claim(quest, currentAge: age, history: [record, record], now: now, calendar: calendar))
        XCTAssertFalse(archive.claim(quest, currentAge: age, history: [record], now: now, calendar: calendar))
        XCTAssertEqual(archive.claims.count, 1)
        XCTAssertEqual(archive.totalXP, quest.xp)
        archive.reconcile(currentAge: age, history: [], now: now, calendar: calendar)
        XCTAssertEqual(archive.totalXP, 0)
        XCTAssertFalse(archive.claim(quest, currentAge: age, history: [record], now: now, calendar: calendar))
        let foreign = qRecord(quest: quest, age: age, owner: WorkoutOwner(accountID: UUID(), profileID: UUID()))
        XCTAssertFalse(QuestProgress.evaluate(quest, owner: questOwner, currentAge: age, history: [foreign], checkIns: [], now: now, calendar: calendar).isComplete)
        XCTAssertFalse(QuestProgress.evaluate(quest, owner: questOwner, currentAge: try TrainingAgeContext(ageYears: 8, guardianManaged: true), history: [record], checkIns: [], now: now, calendar: calendar).isComplete)
        let camera = Quest(id: "camera", periodID: quest.periodID, title: "Camera", detail: "", kind: .camera, exerciseID: quest.exerciseID, target: quest.target, requiredDays: 1, startsAt: quest.startsAt, endsAt: quest.endsAt, xp: 10)
        XCTAssertFalse(QuestProgress.evaluate(camera, owner: questOwner, currentAge: age, history: [record], checkIns: [], now: now, calendar: calendar).isComplete)
        XCTAssertTrue(QuestProgress.evaluate(camera, owner: questOwner, currentAge: age, history: [qRecord(quest: quest, age: age, source: .camera)], checkIns: [], now: now, calendar: calendar).isComplete)
    }
    func testRecoveryCheckInIsExplicitIdempotentAndContainsNoTrainingRecord() throws {
        let now = qDate("2026-11-07T12:00:00Z"), calendar = qCalendar(), profile = try qProfile(age: 4), age = profile.programmePreferences!.ageContext!
        let quest = try XCTUnwrap(QuestCalendar.choices(year: try QuestCalendar.bundled(), profile: profile, programme: nil, history: [], at: now, calendar: calendar).first { $0.kind == .familyActivity })
        var archive = QuestArchive(owner: questOwner)
        XCTAssertFalse(archive.claim(quest, currentAge: age, history: [], now: now, calendar: calendar))
        archive.checkIn(kind: .familyActivity, age: age, at: now, calendar: calendar)
        archive.checkIn(kind: .familyActivity, age: age, at: now, calendar: calendar)
        XCTAssertEqual(archive.checkIns.count, 1)
        XCTAssertTrue(archive.claim(quest, currentAge: age, history: [], now: now, calendar: calendar))
        XCTAssertTrue(archive.claims.first?.sessionIDs.isEmpty == true)
        archive.removeCheckIn(id: try XCTUnwrap(archive.checkIns.first).id)
        archive.reconcile(currentAge: age, history: [], now: now, calendar: calendar)
        XCTAssertEqual(archive.totalXP, 0)
    }
    func testAbsoluteRemindersAreOneHourBeforeDSTWindowBoundedAndAdultConsentOnly() throws {
        let now = qDate("2026-03-28T12:00:00Z"), calendar = qCalendar("Europe/London"), age = try TrainingAgeContext(ageYears: 30, guardianManaged: false)
        var ledger = GamificationLedger(createdAt: now.addingTimeInterval(-86400), calendar: calendar)
        try ledger.scheduleWindow(DailyXPWindow(startHour: 1), at: now)
        let schedule = XPReminderSchedule.make(ledger: ledger, owner: questOwner, age: age, consent: true, authorized: true, now: now, calendar: calendar)
        XCTAssertEqual(schedule.count, 28)
        if schedule.count >= 2 {
            XCTAssertEqual(schedule[1].date.timeIntervalSince(schedule[0].date), 3600)
            XCTAssertEqual(schedule[0].startsAt, schedule[1].date)
        }
        XCTAssertEqual(Set(schedule.map(\.id)).count, schedule.count)
        XCTAssertTrue(schedule.allSatisfy { $0.date > now })
        XCTAssertLessThanOrEqual(XPReminderSchedule.make(ledger: ledger, owner: questOwner, age: age, consent: true, authorized: true, now: now, calendar: calendar, unrelatedPendingCount: 60).count, 3)
        XCTAssertTrue(XPReminderSchedule.make(ledger: ledger, owner: questOwner, age: age, consent: true, authorized: false, now: now, calendar: calendar).isEmpty)
        XCTAssertTrue(XPReminderSchedule.make(ledger: ledger, owner: questOwner, age: try TrainingAgeContext(ageYears: 12, guardianManaged: true), consent: true, authorized: true, now: now, calendar: calendar).isEmpty)
    }
}
extension QuestCalendarTests {
    func testClaimReconciliationRechecksEditedActualEvidenceWithoutErasingAgeCorrectedEarnedClaim() throws {
        let now = qDate("2026-11-06T12:00:00Z"), calendar = qCalendar(), profile = try qProfile()
        let week = try ProgrammePlanner.makeWeek(profile: profile, history: [], start: now, calendar: calendar)
        let quest = try XCTUnwrap(QuestCalendar.choices(year: try QuestCalendar.bundled(), profile: profile, programme: week, history: [], at: now, calendar: calendar).first { $0.kind == .practice })
        let age = profile.programmePreferences!.ageContext!, record = qRecord(quest: quest, age: age)
        var archive = QuestArchive(owner: questOwner)
        XCTAssertTrue(archive.claim(quest, currentAge: age, history: [record], now: now, calendar: calendar))
        archive.reconcile(currentAge: try .init(ageYears: 12, guardianManaged: true), history: [record], now: now, calendar: calendar)
        XCTAssertEqual(archive.totalXP, 10)
        let edited = SessionRecord(id: record.id, date: record.date, sets: [], trainingContext: record.trainingContext)
        archive.reconcile(currentAge: age, history: [edited], now: now, calendar: calendar)
        XCTAssertEqual(archive.totalXP, 0)
        XCTAssertTrue(archive.retiredPeriods.contains(quest.periodID))
    }
    func testCameraQuestRequiresObservedOriginAndWeeklyRecoveryOptionStaysRecovery() throws {
        let now = qDate("2026-11-06T12:00:00Z"), calendar = qCalendar(), profile = try qProfile()
        let quest = Quest(id: "camera", periodID: "day", title: "Camera", detail: "", kind: .camera, exerciseID: "frontArmRaise", target: 2, requiredDays: 1, startsAt: calendar.startOfDay(for: now), endsAt: now.addingTimeInterval(86400), xp: 10)
        let age = profile.programmePreferences!.ageContext!
        let ambiguous = qRecord(quest: quest, age: age, source: .camera, origin: nil)
        XCTAssertFalse(QuestProgress.evaluate(quest, owner: questOwner, currentAge: age, history: [ambiguous], checkIns: [], now: now, calendar: calendar).isComplete)
    }
}
extension QuestCalendarTests {
    func testWeeklyPracticeNeverRequiresMoreDaysThanTheSelectedMovementIsActuallyPlanned() throws {
        let date = qDate("2026-11-06T12:00:00Z"), calendar = qCalendar(), profile = try qProfile()
        let first = try CoachSavedPlan.catalogue(exerciseID: "frontArmRaise", sets: 1, target: 6, restSeconds: 60, availableSupport: [])
        let second = try CoachSavedPlan.catalogue(exerciseID: "singleLegBalance", sets: 1, target: 10, restSeconds: 60, availableSupport: [])
        let week = TrainingProgramme(id: "fixture", timeZoneID: "UTC", revision: 1, days: [
            .init(id: "fri", localDate: "2026-11-06", date: date, kind: .workout, plan: first),
            .init(id: "sat", localDate: "2026-11-07", date: date.addingTimeInterval(86400), kind: .workout, plan: second)
        ])
        let quests = QuestCalendar.choices(year: try QuestCalendar.bundled(), profile: profile, programme: week, history: [], at: date, calendar: calendar, weekly: true)
        for quest in quests where quest.exerciseID != nil {
            let matching = week.days.filter { $0.date >= quest.startsAt && $0.date < quest.endsAt && $0.plan?.items.contains { $0.exerciseID == quest.exerciseID } == true }
            XCTAssertLessThanOrEqual(quest.requiredDays, matching.count)
        }
    }
    func testReminderTimezoneAndChangedWindowReplaceDatesWithoutChangingEarnedLedger() throws {
        let date = qDate("2026-10-24T12:00:00Z"), adult = try TrainingAgeContext(ageYears: 30, guardianManaged: false)
        var ledger = GamificationLedger(createdAt: date.addingTimeInterval(-86400), calendar: qCalendar("Europe/London"))
        try ledger.scheduleWindow(DailyXPWindow(startHour: 18), at: date)
        let london = XPReminderSchedule.make(ledger: ledger, owner: questOwner, age: adult, consent: true, authorized: true, now: date, calendar: qCalendar("Europe/London"))
        let ny = XPReminderSchedule.make(ledger: ledger, owner: questOwner, age: adult, consent: true, authorized: true, now: date, calendar: qCalendar("America/New_York"))
        XCTAssertFalse(Set(london.map(\.id)) == Set(ny.map(\.id)))
        XCTAssertTrue(zip(ny, ny.dropFirst()).filter { $0.0.startsAt == $0.1.startsAt }.allSatisfy { $0.1.date.timeIntervalSince($0.0.date) == 3600 })
        XCTAssertTrue(ledger.events.isEmpty)
    }
}
extension QuestCalendarTests {
    func testUnknownAbilityCannotReceiveAdvancedQuestFromStaleProgramme() throws {
        let date = qDate("2026-11-06T12:00:00Z"), calendar = qCalendar(), profile = try qProfile()
        let plan = try CoachSavedPlan.catalogue(exerciseID: "diamondPushup", sets: 1, target: 10, restSeconds: 60, availableSupport: [])
        let week = TrainingProgramme(id: "stale", timeZoneID: "UTC", revision: 1, days: [.init(id: "fri", localDate: "2026-11-06", date: date, kind: .workout, plan: plan)])
        let quests = QuestCalendar.choices(year: try QuestCalendar.bundled(), profile: profile, programme: week, history: [], at: date, calendar: calendar)
        XCTAssertEqual(quests.count, 3)
        XCTAssertTrue(quests.allSatisfy { $0.exerciseID == nil })
    }
}

extension QuestCalendarTests {
    func testAuthoredWeeklyRecoveryUsesRecoveryCheckInEvidence() throws {
        let year = try QuestCalendar.bundled()
        let slot = try XCTUnwrap(year.weekly.first { $0.options.contains("weekRecovery") })
        var iso = Calendar(identifier: .iso8601); iso.timeZone = qCalendar().timeZone
        let date = try XCTUnwrap(iso.date(from: DateComponents(weekOfYear: slot.slot, yearForWeekOfYear: 2026)))
        let choices = QuestCalendar.choices(year: year, profile: try qProfile(), programme: nil, history: [], at: date, calendar: iso, weekly: true)
        XCTAssertEqual(choices[1].kind, .recovery)
        let family = QuestCalendar.choices(year: year, profile: try qProfile(age: 4), programme: nil, history: [], at: date, calendar: iso, weekly: true)
        XCTAssertEqual(family[1].kind, .recovery)
        XCTAssertNil(family[1].exerciseID)
    }
    func testAdultBenchmarkPolicySeparatesCapturedPracticeAndPreservesOnlyOwnedLegacyEarnings() throws {
        let adult = try qProfile(), teen = try qProfile(age: 15), calendar = qCalendar()
        func history(_ age: TrainingAgeContext?, legacy: Bool = false, owner: WorkoutOwner = questOwner, exercise: String = "catCow") -> [SessionRecord] {
            (0..<3).map { index in SessionRecord(id: UUID(), date: qDate("2026-11-01T12:00:00Z").addingTimeInterval(Double(index) * 86400), sets: [], loggedSets: [.init(id: UUID(), exerciseID: exercise, reps: 6, seconds: 0, source: .manual, reason: .voluntary)], trainingContext: legacy ? nil : .init(owner: owner, age: age)) }
        }
        let junior = history(teen.programmePreferences?.ageContext)
        let unknown = history(nil), legacy = history(nil, legacy: true)
        let grown = history(adult.programmePreferences?.ageContext)
        let policy = SkillCurriculum.BenchmarkPolicy(owner: questOwner, legacyHistory: legacy + junior + unknown, calendar: calendar)
        for profile in [teen, adult] {
            XCTAssertNotEqual(SkillCurriculum.evaluate(profile: profile, history: policy.qualifiedHistory(junior), calendar: calendar).node("catCow")?.state, .earned)
            XCTAssertNotEqual(SkillCurriculum.evaluate(profile: profile, history: policy.qualifiedHistory(unknown), calendar: calendar).node("catCow")?.state, .earned)
            XCTAssertEqual(SkillCurriculum.evaluate(profile: profile, history: policy.qualifiedHistory(grown), calendar: calendar).node("catCow")?.state, .earned)
            XCTAssertEqual(SkillCurriculum.evaluate(profile: profile, history: policy.qualifiedHistory(legacy), calendar: calendar).node("catCow")?.state, .earned)
        }
        let reopened = try JSONDecoder().decode(SkillCurriculum.BenchmarkPolicy.self, from: JSONEncoder().encode(policy))
        XCTAssertTrue(reopened.qualifiedHistory(history(nil, legacy: true)).isEmpty)
        XCTAssertTrue(reopened.qualifiedHistory(history(adult.programmePreferences?.ageContext, owner: .init(accountID: UUID(), profileID: UUID()))).isEmpty)
        XCTAssertTrue(reopened.qualifiedHistory([]).isEmpty)
        let replacementSets = legacy.map { SessionRecord(id: $0.id, date: $0.date, sets: [], loggedSets: [.init(id: UUID(), exerciseID: "catCow", reps: 6, seconds: 0, source: .manual, reason: .voluntary)]) }
        XCTAssertTrue(reopened.qualifiedHistory(replacementSets).isEmpty)
        XCTAssertNotEqual(SkillCurriculum.evaluate(profile: adult, history: reopened.qualifiedHistory(Array(legacy.prefix(2))), calendar: calendar).node("catCow")?.state, .earned)
    }
}

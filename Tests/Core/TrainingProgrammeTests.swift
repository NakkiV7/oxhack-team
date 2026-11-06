import Foundation
import Testing
@testable import SpottrCore

private let programmeStart = Date(timeIntervalSince1970: 1793577600)
private var programmeCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/London")!
    return calendar
}
private func programmeProfile(goals: Set<TrainingGoal> = [.strength], days: Set<Int> = [1, 3, 5],
                              starting: TrainingStartingPoint? = nil, minutes: Int = 20,
                              support: Set<String> = [], floor: Bool = true, excluded: Set<String> = [],
                              comfortable: Set<String> = []) throws -> LocalProfile {
    try LocalProfile(comfortableExercises: comfortable, programmePreferences: ProgrammePreferences(
        goals: goals, weekdays: days, minutesPerSession: minutes, preferredLocalHour: 18,
        availableSupport: support, allowsFloorWork: floor, excludedExerciseIDs: excluded, startingPoint: starting, ageContext: TrainingAgeContext(ageYears: 30, guardianManaged: false)))
}

@Test func programmePreferencesPreserveFiveGoalsAndFourStartingStatesWithoutChangingLegacyEnums() throws {
    #expect(TrainingAttribute.allCases.count == 4)
    #expect(LocalProfile.BaselineAbility.allCases.count == 3)
    #expect(TrainingGoal.allCases.count == 5)
    for goal in TrainingGoal.allCases {
        for start in TrainingStartingPoint.allCases {
            let profile = try programmeProfile(goals: [goal], starting: start)
            #expect(profile.trainingGoals == [goal])
            #expect(try JSONDecoder().decode(LocalProfile.self, from: JSONEncoder().encode(profile)) == profile)
        }
    }
    let old = try JSONDecoder().decode(LocalProfile.self, from: Data(#"{"name":"","weeklyTarget":3,"goals":["balance"],"weightManagementGoal":true}"#.utf8))
    #expect(old.programmePreferences == nil)
    #expect(old.trainingGoals == [.balance, .weightManagement])
    for days: Set<Int> in [[], [0], [8]] {
        #expect(throws: Error.self) { try programmeProfile(days: days) }
    }
    #expect(throws: Error.self) { try programmeProfile(goals: []) }
    #expect(throws: Error.self) { try programmeProfile(minutes: 15) }
    #expect(throws: Error.self) { try programmeProfile(support: ["wall"]) }
    let prefs = try #require(try programmeProfile().programmePreferences)
    let invalid = String(data: try JSONEncoder().encode(prefs), encoding: .utf8)!.replacingOccurrences(of: "18", with: "24")
    #expect(throws: Error.self) { try JSONDecoder().decode(ProgrammePreferences.self, from: Data(invalid.utf8)) }
}

@Test func programmeCreatesWholeWorkoutsForEachGoalAndExplicitRestOrRecovery() throws {
    for goal in TrainingGoal.allCases {
        for days: Set<Int> in [[1], [1, 3, 5], Set(1...7)] {
            let profile = try programmeProfile(goals: [goal], days: days)
            let week = try ProgrammePlanner.makeWeek(profile: profile, history: [], start: programmeStart, calendar: programmeCalendar)
            #expect(week.days.count == 7)
            #expect(week.days.filter { $0.kind != .rest }.count == days.count)
            #expect(week.days.filter { $0.kind == .rest }.count == 7 - days.count)
            if days.count == 7 { #expect(week.days.filter { $0.kind == .recovery }.count >= 2) }
            for day in week.days where day.kind != .rest {
                let plan = try #require(day.plan)
                #expect(plan.items.count >= 2)
                #expect(Set(plan.items.compactMap { ExerciseCatalog.find($0.exerciseID)?.family }).count >= 2)
                #expect(plan.items.allSatisfy { ExerciseCatalog.find($0.exerciseID)!.level <= 2 })
                #expect(!plan.items.contains { $0.exerciseID == "pushup" })
                _ = try ConfigurableSession(plan: plan, availableSupport: [])
            }
        }
    }
}

@Test func programmeHonoursSupportFloorExclusionsAndDoesNotUseBMIAsAbility() throws {
    let profile = try programmeProfile(support: ["Wall"], floor: false, excluded: ["quarterSquat"])
    let week = try ProgrammePlanner.makeWeek(profile: profile, history: [], start: programmeStart, calendar: programmeCalendar)
    for item in week.days.compactMap(\.plan).flatMap(\.items) {
        #expect(!ProgrammePreferences.floorExerciseIDs.contains(item.exerciseID))
        #expect(item.exerciseID != "quarterSquat")
        #expect(PathSurvey.requiredEquipment(for: ExerciseCatalog.find(item.exerciseID)!).map { $0 == "Wall" } ?? true)
    }
    let heavy = try LocalProfile(bodyMeasurements: LocalBodyMeasurements(heightCM: 170, weightKG: 140, bmiEligible: true, thresholds: .standard), programmePreferences: profile.programmePreferences)
    let other = try ProgrammePlanner.makeWeek(profile: heavy, history: [], start: programmeStart, calendar: programmeCalendar)
    #expect(other == week)
    let allExcluded = try programmeProfile(excluded: Set(ExerciseCatalog.all.map(\.id)))
    #expect(throws: Error.self) { try ProgrammePlanner.makeWeek(profile: allExcluded, history: [], start: programmeStart, calendar: programmeCalendar) }
}

@Test func programmeUsesRecentActualEffortCompletionAndFamilyPlacementConservatively() throws {
    let profile = try programmeProfile(comfortable: ["squat"])
    let initial = try ProgrammePlanner.makeWeek(profile: profile, history: [], start: programmeStart, calendar: programmeCalendar)
    let first = try #require(initial.days.compactMap(\.plan).first?.items.first)
    func history(_ effort: SetEffort?, count: Int) -> [SessionRecord] {
        let set = LoggedSet(id: UUID(), exerciseID: first.exerciseID, reps: first.unit == .reps ? count : 0,
                            seconds: first.unit == .seconds ? Double(count) : 0, source: .manual, reason: .target,
                            target: first.target, effort: effort)
        return [.init(id: UUID(), date: programmeStart.addingTimeInterval(-3600), sets: [], loggedSets: [set])]
    }
    let hard = try ProgrammePlanner.makeWeek(profile: profile, history: history(.veryHard, count: first.target), start: programmeStart, calendar: programmeCalendar)
    let easy = try ProgrammePlanner.makeWeek(profile: profile, history: history(.easy, count: first.target), start: programmeStart, calendar: programmeCalendar)
    let incomplete = try ProgrammePlanner.makeWeek(profile: profile, history: history(nil, count: 1), start: programmeStart, calendar: programmeCalendar)
    #expect(hard.days.compactMap(\.plan).first?.items.first?.target ?? 999 < first.target)
    #expect(easy.days.compactMap(\.plan).first?.items.first?.target ?? 0 > first.target)
    #expect(incomplete.days.compactMap(\.plan).first?.items.first?.target ?? 999 < first.target)
    let stale = history(.veryHard, count: first.target).map { SessionRecord(id: $0.id, date: programmeStart.addingTimeInterval(-40 * 86400), sets: [], loggedSets: $0.loggedSets) }
    #expect(try ProgrammePlanner.makeWeek(profile: profile, history: stale, start: programmeStart, calendar: programmeCalendar) == initial)
    #expect(initial.days.compactMap(\.plan).flatMap(\.items).contains { $0.exerciseID == "squat" })
}

@Test func programmeIDsSurviveRepeatedViewsAndRevisionsProtectStartedAndCompletedDays() throws {
    let profile = try programmeProfile()
    let original = try ProgrammePlanner.makeWeek(profile: profile, history: [], start: programmeStart, calendar: programmeCalendar)
    #expect(try ProgrammePlanner.makeWeek(profile: profile, history: [], start: programmeStart.addingTimeInterval(60), calendar: programmeCalendar) == original)
    let workouts = original.days.filter { $0.plan != nil }
    let active = workouts[0]
    let completed = workouts[1]
    let record = SessionRecord(id: UUID(), date: completed.date, sets: [], plannedWorkoutID: completed.id)
    let updated = try ProgrammePlanner.revise(original, profile: programmeProfile(days: [2, 4], minutes: 10), history: [record], protecting: [active.id], calendar: programmeCalendar)
    #expect(updated.days.first { $0.id == active.id } == active)
    #expect(updated.days.first { $0.id == completed.id } == completed)
    #expect(updated.revision == original.revision + 1)
    #expect(original.revision == 1)
    #expect(try JSONDecoder().decode(TrainingProgramme.self, from: JSONEncoder().encode(updated)) == updated)
}

@Test func programmeUsesLocalDaysAcrossDSTAndPreferredLocalHour() throws {
    var calendar = programmeCalendar
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    let start = ISO8601DateFormatter().date(from: "2026-10-30T12:00:00Z")!
    let week = try ProgrammePlanner.makeWeek(profile: programmeProfile(days: Set(1...7)), history: [], start: start, calendar: calendar)
    #expect(Set(week.days.map(\.id)).count == 7)
    #expect(week.timeZoneID == "America/New_York")
    #expect(week.days.allSatisfy { calendar.component(.hour, from: $0.date) == 18 })
    #expect(zip(week.days, week.days.dropFirst()).contains { $1.date.timeIntervalSince($0.date) == 25 * 3600 })
}

@Test func programmeAbilityAndDurationChangeFutureWorkWithoutInferringFitnessFromBody() throws {
    let starting = try ProgrammePlanner.makeWeek(profile: programmeProfile(starting: .startingOut, minutes: 10), history: [], start: programmeStart, calendar: programmeCalendar)
    let experienced = try ProgrammePlanner.makeWeek(profile: programmeProfile(starting: .experienced, minutes: 45), history: [], start: programmeStart, calendar: programmeCalendar)
    let short = try #require(starting.days.compactMap(\.plan).first)
    let long = try #require(experienced.days.compactMap(\.plan).first)
    #expect(short.items.reduce(0) { $0 + $1.sets } < long.items.reduce(0) { $0 + $1.sets })
    #expect(short.items.compactMap { ExerciseCatalog.find($0.exerciseID)?.level }.max()! < long.items.compactMap { ExerciseCatalog.find($0.exerciseID)?.level }.max()!)
    let invalid = Date(timeIntervalSince1970: .infinity)
    #expect(throws: Error.self) { try ProgrammePlanner.makeWeek(profile: programmeProfile(), history: [], start: invalid) }
}

@Test func programmeUsesRealLegacyCompletionAndIndependentEarnedFamilyEvidence() throws {
    let profile = try programmeProfile()
    let initial = try ProgrammePlanner.makeWeek(profile: profile, history: [], start: programmeStart, calendar: programmeCalendar)
    let initialPush = try #require(initial.days.compactMap(\.plan).first?.items.first { ExerciseCatalog.find($0.exerciseID)?.family == .push })
    let legacy = SetRecord(id: UUID(), exercise: .standingBicepsCurl, number: 1, reps: 1, target: initialPush.target,
                           activeSeconds: 10, source: .manual, reserve: nil, reason: .voluntary)
    let updated = try ProgrammePlanner.makeWeek(profile: profile, history: [.init(id: UUID(), date: programmeStart.addingTimeInterval(-3600), sets: [legacy])], start: programmeStart, calendar: programmeCalendar)
    let reduced = try #require(updated.days.compactMap(\.plan).first?.items.first { $0.exerciseID == initialPush.exerciseID })
    #expect(reduced.target < initialPush.target)
    let earned = try [LoggedWorkout.make(exerciseID: "pushup", count: 10, sets: 2, date: programmeStart.addingTimeInterval(-2 * 86400)),
                      LoggedWorkout.make(exerciseID: "pushup", count: 10, sets: 1, date: programmeStart.addingTimeInterval(-86400))]
    let progressed = try ProgrammePlanner.makeWeek(profile: profile, history: earned, start: programmeStart, calendar: programmeCalendar)
    #expect(progressed.days.compactMap(\.plan).flatMap(\.items).contains { $0.exerciseID == "pushup" })
}

@Test func programmeRevisionAdaptsLaterDaysFromActualWorkRecordedWithinItsWeek() throws {
    let profile = try programmeProfile(goals: [.weightManagement])
    let original = try ProgrammePlanner.makeWeek(profile: profile, history: [], start: programmeStart, calendar: programmeCalendar)
    let workouts = original.days.filter { $0.plan != nil }
    let first = workouts[0]
    let actual = try #require(first.plan?.items.first { $0.exerciseID == "stepJack" })
    let set = LoggedSet(id: UUID(), exerciseID: actual.exerciseID, reps: actual.target, seconds: 0, source: .manual,
                        reason: .target, target: actual.target, effort: .veryHard)
    let record = SessionRecord(id: UUID(), date: first.date, sets: [], loggedSets: [set], plannedWorkoutID: first.id)
    let updated = try ProgrammePlanner.revise(original, profile: profile, history: [record], protecting: [], calendar: programmeCalendar)
    #expect(updated.days.first { $0.id == first.id } == first)
    let later = try #require(updated.days.first { $0.id == workouts[1].id }?.plan?.items.first { $0.exerciseID == actual.exerciseID })
    let before = try #require(workouts[1].plan?.items.first { $0.exerciseID == actual.exerciseID })
    #expect(later.target < before.target)
}

@Test func programmeUsesAgeAppropriateFamilyMovementAndBoundedSupervisedPractice() throws {
    let allowed: Set<String> = ["frontArmRaise", "standingKneeRaise", "seatedMarch", "stepJack", "sitToStand", "singleLegBalance"]
    for age in [0, 4, 5, 12, 13, 17, 18, 120] {
        let prefs = try ProgrammePreferences(goals: [.weightManagement], weekdays: Set(1...7), minutesPerSession: 45,
            availableSupport: ["Stable chair"], startingPoint: .experienced,
            ageContext: TrainingAgeContext(ageYears: age, guardianManaged: age < 18))
        let profile = try LocalProfile(comfortableExercises: ["pushup"], programmePreferences: prefs)
        let week = try ProgrammePlanner.makeWeek(profile: profile, history: [], start: programmeStart, calendar: programmeCalendar)
        if age < 5 {
            #expect(week.days.allSatisfy { $0.kind == .familyMovement && $0.plan == nil })
            continue
        }
        let items = week.days.compactMap(\.plan).flatMap(\.items)
        #expect(!items.isEmpty)
        if age < 13 {
            #expect(items.allSatisfy { allowed.contains($0.exerciseID) && $0.sets == 1 && $0.target <= ($0.unit == .reps ? 6 : 10) })
        } else if age < 18 {
            #expect(items.allSatisfy { $0.sets <= 2 && $0.target <= ($0.unit == .reps ? 10 : 20) })
            #expect(!items.contains { $0.exerciseID == "pushup" })
        } else {
            #expect(items.contains { $0.sets == 3 })
        }
        #expect(week.days.contains { $0.kind == .recovery })
        if age < 18 {
            let changedGoals = try ProgrammePreferences(goals: [.strength], weekdays: Set(1...7), minutesPerSession: 45,
                availableSupport: ["Stable chair"], startingPoint: .experienced, ageContext: prefs.ageContext)
            let noWeightLogic = try ProgrammePlanner.makeWeek(profile: LocalProfile(comfortableExercises: ["pushup"], programmePreferences: changedGoals), history: [], start: programmeStart, calendar: programmeCalendar)
            #expect(noWeightLogic == week)
        }
    }
}

@Test func programmeChildEffortNeverAutomaticallyIncreasesPracticeAndRespectsExclusions() throws {
    for age in [5, 12, 13, 17] {
        let prefs = try ProgrammePreferences(goals: [.strength], weekdays: [1, 3, 5], availableSupport: [], allowsFloorWork: false,
            excludedExerciseIDs: ["standingKneeRaise"], ageContext: TrainingAgeContext(ageYears: age, guardianManaged: true))
        let profile = try LocalProfile(programmePreferences: prefs)
        let original = try ProgrammePlanner.makeWeek(profile: profile, history: [], start: programmeStart, calendar: programmeCalendar)
        let items = try #require(original.days.compactMap(\.plan).first?.items)
        let sets = items.map { item in LoggedSet(id: UUID(), exerciseID: item.exerciseID,
            reps: item.unit == .reps ? item.target : 0, seconds: item.unit == .seconds ? Double(item.target) : 0,
            source: .manual, reason: .target, target: item.target, effort: .veryEasy) }
        let record = SessionRecord(id: UUID(), date: programmeStart.addingTimeInterval(-3600), sets: [], loggedSets: sets)
        let updated = try ProgrammePlanner.makeWeek(profile: profile, history: [record], start: programmeStart, calendar: programmeCalendar)
        #expect(updated == original)
        #expect(updated.days.compactMap(\.plan).flatMap(\.items).allSatisfy {
            $0.exerciseID != "standingKneeRaise" && !ProgrammePreferences.floorExerciseIDs.contains($0.exerciseID)
                && PathSurvey.requiredEquipment(for: ExerciseCatalog.find($0.exerciseID)!) == nil
        })
    }
}

@Test func programmePreferencesCrossLanguageFixtureKeepsExactRawValuesAndOptionalAgeCompatibility() throws {
    let fixture = #"{"goals":["balance","weightManagement"],"weekdays":[1,3,5],"minutesPerSession":20,"preferredLocalHour":18,"availableSupport":["Wall","Stable chair"],"allowsFloorWork":false,"excludedExerciseIDs":["wallSit"],"startingPoint":"somePractice","ageContext":{"ageYears":30,"guardianManaged":false}}"#
    let prefs = try JSONDecoder().decode(ProgrammePreferences.self, from: Data(fixture.utf8))
    #expect(prefs.goals == [.balance, .weightManagement])
    #expect(prefs.weekdays == [1, 3, 5])
    #expect(prefs.ageContext?.ageYears == 30)
    #expect(prefs.startingPoint == .somePractice)
    #expect(try JSONDecoder().decode(ProgrammePreferences.self, from: JSONEncoder().encode(prefs)) == prefs)
    let legacy = fixture.replacingOccurrences(of: #","ageContext":{"ageYears":30,"guardianManaged":false}"#, with: "")
    #expect(try JSONDecoder().decode(ProgrammePreferences.self, from: Data(legacy.utf8)).ageContext == nil)
}

@Test func programmeUnknownAbilityOmitsAdvancedOnlyFamiliesWhenSupportAndExclusionsRemoveGentleChoices() throws {
    let profile = try programmeProfile(days: Set(1...7), excluded: ["standingBicepsCurl", "kneePushup"])
    let week = try ProgrammePlanner.makeWeek(profile: profile, history: [], start: programmeStart, calendar: programmeCalendar)
    #expect(week.days.contains { $0.kind == .recovery })
    for day in week.days {
        let items = try #require(day.plan?.items)
        #expect(items.count >= 2)
        #expect(items.allSatisfy { ExerciseCatalog.find($0.exerciseID)?.family != .push })
        #expect(items.allSatisfy { ExerciseCatalog.find($0.exerciseID)?.level == 1 })
        _ = try ConfigurableSession(plan: #require(day.plan), availableSupport: [])
    }
}

@Test func programmeRecoveryOmitsAdvancedOnlyFamiliesEvenWithExperiencedPlacement() throws {
    let excluded = Set(ExerciseCatalog.all.filter { [.mobility, .balance, .conditioning].contains($0.family) }.map(\.id))
        .union(["standingBicepsCurl", "kneePushup"])
    let profile = try programmeProfile(days: Set(1...7), starting: .experienced, excluded: excluded, comfortable: ["pushup"])
    let week = try ProgrammePlanner.makeWeek(profile: profile, history: [], start: programmeStart, calendar: programmeCalendar)
    #expect(week.days.filter { $0.kind == .workout }.compactMap(\.plan).flatMap(\.items).contains { $0.exerciseID == "pushup" })
    let recoveries = week.days.filter { $0.kind == .recovery }
    #expect(!recoveries.isEmpty)
    for day in recoveries {
        let items = try #require(day.plan?.items)
        #expect(Set(items.compactMap { ExerciseCatalog.find($0.exerciseID)?.family }) == [.legs, .core])
        #expect(items.allSatisfy { ExerciseCatalog.find($0.exerciseID)?.level == 1 })
    }
}

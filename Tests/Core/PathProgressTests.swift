import Foundation
import Testing
@testable import SpottrCore

private let monday = Date(timeIntervalSince1970: 1_792_368_000)   // Monday 19 October 2026, 00:00 UTC
private func londonCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/London")!
    calendar.firstWeekday = 2
    return calendar
}
private func logged(_ id: String, count: Int, sets: Int, day: Int, source: InputSource = .manual) throws -> SessionRecord {
    let record = try LoggedWorkout.make(exerciseID: id, count: count, sets: sets, date: monday.addingTimeInterval(Double(day) * 86_400 + 36_000))
    guard source != .manual else { return record }
    let sets = record.loggedSets.map { LoggedSet(id: $0.id, exerciseID: $0.exerciseID, reps: $0.reps, seconds: $0.seconds, source: source, reason: $0.reason) }
    return SessionRecord(id: record.id, date: record.date, sets: [], loggedSets: sets)
}

@Test func pathStatusUsesTheEarnedRuleWithThePathsOwnStart() throws {
    let calendar = londonCalendar()
    let path = TrainingPathRules.fallback(survey: PathSurvey(goal: .squat, abilityKey: "control"))
    let fresh = PathStatus.evaluate(path: path, skill: SkillProgress.evaluate(history: [], calendar: calendar), calendar: calendar)
    #expect(fresh.current == "squat")
    #expect(fresh.step("gluteBridge")?.state == .notRequired && fresh.step("gluteBridge")?.isPassed == true)
    #expect(fresh.step("reverseLunge")?.state == .locked)
    #expect(fresh.step("singleLegBalance")?.state == .available)       // the optional branch is open from the outset

    // Three goal sets on one day do not earn the step; the same three across two days do.
    let oneDay = try logged("squat", count: 12, sets: 3, day: 0)
    let stillCurrent = PathStatus.evaluate(path: path, skill: SkillProgress.evaluate(history: [oneDay], calendar: calendar), calendar: calendar)
    #expect(stillCurrent.step("squat")?.state == .current && stillCurrent.step("squat")?.qualifyingSets == 3)
    let history = [try logged("squat", count: 12, sets: 2, day: 0), try logged("squat", count: 12, sets: 1, day: 1)]
    let skill = SkillProgress.evaluate(history: history, calendar: calendar)
    let earned = PathStatus.evaluate(path: path, skill: skill, calendar: calendar)
    #expect(earned.step("squat")?.state == .earned && earned.current == "reverseLunge")
    #expect(skill.node(exerciseID: "squat")?.isComplete == false)      // the full catalogue tree still wants glute bridges first
    // Sets below the catalogue goal never count, whatever the practice target says.
    let light = [try logged("squat", count: 7, sets: 2, day: 0), try logged("squat", count: 7, sets: 2, day: 1)]
    #expect(PathStatus.evaluate(path: path, skill: SkillProgress.evaluate(history: light, calendar: calendar), calendar: calendar).step("squat")?.state == .current)
}

@Test func cameraVerificationIsAMarkThatNeverUnlocksByItself() throws {
    let calendar = londonCalendar()
    let path = TrainingPathRules.fallback(survey: PathSurvey(goal: .squat, abilityKey: "control"))
    let attempt = completedAttempt(baseline: [0.9, 1.0, 0.8], retry: [1.45, 1.5, 1.6], at: monday.addingTimeInterval(36_000))
    let status = PathStatus.evaluate(path: path, skill: SkillProgress.evaluate(history: [], calendar: calendar), attempts: [attempt], calendar: calendar)
    #expect(status.step("squat")?.verification == .firstCompletion && status.step("squat")?.state == .current)
    #expect(status.step("reverseLunge")?.state == .locked)
    let history = [try logged("squat", count: 12, sets: 2, day: 0), try logged("squat", count: 12, sets: 1, day: 1)]
    let both = PathStatus.evaluate(path: path, skill: SkillProgress.evaluate(history: history, calendar: calendar), attempts: [attempt], calendar: calendar)
    #expect(both.step("squat")?.title == "Earned · AI-verified")
}

@Test func aNewVersionShowsWhatChangesAndLosesNoProgress() throws {
    let calendar = londonCalendar()
    let old = TrainingPathRules.fallback(survey: PathSurvey(goal: .squat, abilityKey: "new"))
    let new = TrainingPathRules.fallback(survey: PathSurvey(goal: .squat, abilityKey: "comfortable", avoid: ["gluteBridge", "singleLegBalance"]))
    let history = [try logged("gluteBridge", count: 12, sets: 3, day: 0), try logged("squat", count: 12, sets: 1, day: 1)]
    let skill = SkillProgress.evaluate(history: history, calendar: calendar)
    let diff = PathDiff.between(old, new, skill: skill, calendar: calendar)
    #expect(diff.changesStart && diff.startFrom == "gluteBridge" && diff.startTo == "squat")
    #expect(diff.removed.contains("gluteBridge") && diff.keptInHistory == ["gluteBridge"])
    #expect(diff.carried == ["squat"] && diff.added == ["hipFlexorStretch"])
    let first = PathDiff.between(nil, old, skill: skill, calendar: calendar)
    #expect(!first.changesStart && first.added.count == old.nodes.count && first.removed.isEmpty)
}

@Test func pathHistoryOnlySavesValidPathsAndKeepsEveryVersion() throws {
    var history = PathHistory()
    let survey = PathSurvey(goal: .squat, abilityKey: "new")
    let path = TrainingPathRules.fallback(survey: survey)
    let first = try history.save(path, survey: survey, at: monday)
    #expect(first.id == 1)
    var broken = path; broken.route = ["squat"]
    do { try history.save(broken, survey: survey, at: monday); Issue.record("an invalid path was saved") }
    catch PathHistory.Invalid.path(let errors) { #expect(errors == ["recommended route is not a path from the start to the goal"]) }
    let second = TrainingPathRules.fallback(survey: PathSurvey(goal: .squat, abilityKey: "comfortable"))
    try history.save(second, survey: PathSurvey(goal: .squat, abilityKey: "comfortable"), at: monday.addingTimeInterval(60))
    #expect(history.versions.map(\.id) == [1, 2] && history.active?.path == second)
    #expect(try JSONDecoder().decode(PathHistory.self, from: JSONEncoder().encode(history)) == history)
}

@Test func levelIsAGameScoreFromExistingXPAndVerificationBonuses() throws {
    #expect(PathLevel(xp: 0).level == 1 && PathLevel(xp: 99).level == 1)
    let two = PathLevel(xp: 100)
    #expect(two.level == 2 && two.floor == 100 && two.next == 300 && two.fraction == 0)
    #expect(PathLevel(xp: 300).level == 3 && PathLevel(xp: -5).xp == 0)
    let skill = SkillProgress.evaluate(history: [try logged("squat", count: 12, sets: 3, day: 0)], calendar: londonCalendar())
    #expect(PathLevel.xp(skill: skill, verifications: []) == 30)
    #expect(PathLevel.xp(skill: skill, verifications: [.firstCompletion, .consistent, .none]) == 30 + 50 + 150)
}

@Test func measuredAttributesStayUnassessedUntilThereIsEvidence() throws {
    let calendar = londonCalendar(), now = monday.addingTimeInterval(3 * 86_400 + 43_200)
    let empty = MeasuredAttributes.evaluate(attempts: [], history: [], plannedSessions: nil, now: now, calendar: calendar)
    #expect(empty.map(\.value) == [nil, nil, nil])
    #expect(empty[0].detail == "Needs 3 timed squats from a camera assessment (0 so far)")
    #expect(empty[2].detail == "Set sessions per week in your path to track this")

    let attempt = completedAttempt(baseline: [0.9, 1.0, 1.4], retry: [1.4, 1.5, 1.6], at: monday.addingTimeInterval(36_000))
    let history = [try logged("gluteBridge", count: 12, sets: 1, day: 1), try logged("squat", count: 12, sets: 1, day: 1, source: .video),
                   try logged("plank", count: 20, sets: 1, day: -2)]
    let measured = MeasuredAttributes.evaluate(attempts: [attempt], history: history, plannedSessions: 3, now: now, calendar: calendar)
    #expect(measured[0].value == 67 && measured[0].detail == "4 of 6 timed squats were within 0.15 s of the 1.5 s lowering target")
    #expect(measured[1].value == 50 && measured[1].detail.hasSuffix("(1.4 s)"))
    #expect(measured[2].value == 67 && measured[2].detail == "2 of 3 planned sessions this week")   // the video replay and last week's plank do not count
    let old = MeasuredAttributes.evaluate(attempts: [attempt], history: [], plannedSessions: 3, now: now.addingTimeInterval(40 * 86_400), calendar: calendar)
    #expect(old[0].value == nil && old[0].evidence == 0)
}

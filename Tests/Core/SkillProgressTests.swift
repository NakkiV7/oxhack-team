import Foundation
import Testing
@testable import SpottrCore

private func skillCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/London")!
    return calendar
}

@Test func pointsDeduplicateHistoryAndCapEachExercisePerLocalDay() throws {
    let date = Date(timeIntervalSince1970: 1_790_000_000)
    let record = try LoggedWorkout.make(exerciseID: "wallPushup", count: 8, sets: 5, date: date)
    let repeatedSet = SessionRecord(id: UUID(), date: date, sets: [], loggedSets: [record.loggedSets[0]])
    let tomorrow = try LoggedWorkout.make(exerciseID: "wallPushup", count: 8, sets: 1, date: date.addingTimeInterval(86400))
    let progress = SkillProgress.evaluate(history: [record, record, repeatedSet, tomorrow], calendar: skillCalendar())
    #expect(progress.points(for: .strength) == 40)
    #expect(progress.node(exerciseID: "wallPushup")?.qualifyingSets == 6)
    #expect(progress.node(exerciseID: "wallPushup")?.isComplete == true)
}

@Test func manualGoalSetsEarnAttributePointsWithoutCompletingOneDayChallenge() throws {
    let record = try LoggedWorkout.make(exerciseID: "wallPushup", count: 8, sets: 3)
    let progress = SkillProgress.evaluate(history: [record], calendar: skillCalendar())
    #expect(progress.points(for: .strength) == 30)
    #expect(progress.points(for: .stamina) == 0)
    #expect(progress.node(exerciseID: "wallPushup")?.qualifyingSets == 3)
    #expect(progress.node(exerciseID: "wallPushup")?.trainingDays == 1)
    #expect(progress.node(exerciseID: "wallPushup")?.manualSets == 3)
    #expect(progress.node(exerciseID: "wallPushup")?.isComplete == false)
}

@Test func qualifyingEvidenceIncludesCameraAndTimedManualButExcludesReplayDiscomfortAndPreparation() throws {
    let date = Date()
    let tracked: [SetRecord] = [
        .init(id: UUID(), exercise: .pushup, number: 1, reps: 10, target: 10, activeSeconds: 25, source: .camera, reason: .target),
        .init(id: UUID(), exercise: .pushup, number: 2, reps: 20, target: 10, activeSeconds: 25, source: .video, reason: .target),
        .init(id: UUID(), exercise: .squat, number: 1, reps: 12, target: 12, activeSeconds: 25, source: .camera, reason: .discomfort),
        .init(id: UUID(), exercise: .squat, number: 2, reps: 0, target: 12, activeSeconds: 90, source: .camera, reason: .voluntary)
    ]
    let wall = try LoggedWorkout.make(exerciseID: "wallPushup", count: 8, sets: 1, date: date)
    let hold = try LoggedWorkout.make(exerciseID: "plank", count: 20, sets: 1, date: date)
    let incomplete = try LoggedWorkout.make(exerciseID: "wallPushup", count: 7, sets: 1, date: date)
    let discomfort = try LoggedWorkout.make(exerciseID: "wallPushup", count: 10, sets: 1, date: date, reason: .discomfort)
    let preparation = LoggedSet(id: UUID(), exerciseID: "plank", reps: 0, seconds: 0, source: .manual, reason: .voluntary)
    let progress = SkillProgress.evaluate(history: [wall, hold, incomplete, discomfort, .init(id: UUID(), date: date, sets: tracked, loggedSets: [preparation])])
    #expect(progress.points(for: .strength) == 20)
    #expect(progress.points(for: .stamina) == 10)
    #expect(progress.node(exerciseID: "pushup")?.cameraSets == 1)
    #expect(progress.node(exerciseID: "wallPushup")?.manualSets == 1)
    #expect(progress.node(exerciseID: "plank")?.qualifyingSets == 1)
}

@Test func laterChallengesRequirePreviousMilestoneButStillKeepTheirPracticeEvidence() throws {
    let date = Date(timeIntervalSince1970: 1_790_000_000)
    let later = try LoggedWorkout.make(exerciseID: "inclinePushup", count: 8, sets: 2, date: date)
    let laterTomorrow = try LoggedWorkout.make(exerciseID: "inclinePushup", count: 8, sets: 1, date: date.addingTimeInterval(86400))
    let before = SkillProgress.evaluate(history: [later, laterTomorrow])
    #expect(before.node(exerciseID: "inclinePushup")?.qualifyingSets == 3)
    #expect(before.node(exerciseID: "inclinePushup")?.isComplete == false)
    #expect(before.node(exerciseID: "inclinePushup")?.isAvailable == false)
    let first = try LoggedWorkout.make(exerciseID: "wallPushup", count: 8, sets: 2, date: date)
    let firstTomorrow = try LoggedWorkout.make(exerciseID: "wallPushup", count: 8, sets: 1, date: date.addingTimeInterval(86400))
    let after = SkillProgress.evaluate(history: [later, laterTomorrow, first, firstTomorrow])
    #expect(after.node(exerciseID: "wallPushup")?.isComplete == true)
    #expect(after.node(exerciseID: "inclinePushup")?.isComplete == true)
    #expect(after.node(exerciseID: "kneePushup")?.isAvailable == true)
    #expect(after.points(for: .strength) == 60)
}

@Test func challengeDaysAndDailyCapUseThePersonsCalendarAcrossUTCMidnight() throws {
    let formatter = ISO8601DateFormatter()
    let first = try LoggedWorkout.make(exerciseID: "wallPushup", count: 8, sets: 2,
                                       date: formatter.date(from: "2026-06-30T23:30:00Z")!)
    let sameLocalDay = try LoggedWorkout.make(exerciseID: "wallPushup", count: 8, sets: 2,
                                              date: formatter.date(from: "2026-07-01T00:30:00Z")!)
    let sameDay = SkillProgress.evaluate(history: [first, sameLocalDay], calendar: skillCalendar())
    #expect(sameDay.points(for: .strength) == 30)
    #expect(sameDay.node(exerciseID: "wallPushup")?.trainingDays == 1)
    #expect(sameDay.node(exerciseID: "wallPushup")?.isComplete == false)
    let nextLocalDay = try LoggedWorkout.make(exerciseID: "wallPushup", count: 8, sets: 1,
                                              date: formatter.date(from: "2026-07-01T23:30:00Z")!)
    let twoDays = SkillProgress.evaluate(history: [nextLocalDay, sameLocalDay, first], calendar: skillCalendar())
    #expect(twoDays.points(for: .strength) == 40)
    #expect(twoDays.node(exerciseID: "wallPushup")?.isComplete == true)
}

@Test func manualHoldClockCountsOnlyStartedActiveTimeAndPausesBetweenIntervals() {
    var clock = ManualHoldClock()
    #expect(clock.elapsed(at: 10) == 0)
    clock.start(at: 10)
    #expect(clock.elapsed(at: 20) == 10)
    clock.pause(at: 20)
    #expect(clock.elapsed(at: 50) == 10)
    clock.start(at: 50)
    clock.pause(at: 55)
    #expect(clock.elapsed(at: 80) == 15)
    #expect(clock.isRunning == false)
}

@Test func previewAccessNeverCreatesEarnedSetsDaysOrAttributePoints() throws {
    let progress = SkillProgress.evaluate(history: [])
    #expect(progress.access(exerciseID: "pushup", previewUnlock: false) == .locked)
    #expect(progress.access(exerciseID: "pushup", previewUnlock: true) == .preview)
    #expect(progress.access(exerciseID: "wallPushup", previewUnlock: true) == .available)
    #expect(progress.nodes.allSatisfy { !$0.isComplete && $0.qualifyingSets == 0 && $0.trainingDays == 0 })
    #expect(TrainingAttribute.allCases.allSatisfy { progress.points(for: $0) == 0 })
    #expect(progress.access(exerciseID: "missing", previewUnlock: true) == nil)
    let date = Date(timeIntervalSince1970: 1_790_000_000)
    let first = try LoggedWorkout.make(exerciseID: "wallPushup", count: 8, sets: 2, date: date)
    let second = try LoggedWorkout.make(exerciseID: "wallPushup", count: 8, sets: 1, date: date.addingTimeInterval(86400))
    let earned = SkillProgress.evaluate(history: [first, second])
    #expect(earned.access(exerciseID: "wallPushup", previewUnlock: true) == .earned)
    #expect(earned.access(exerciseID: "inclinePushup", previewUnlock: false) == .available)
}

@Test func baselineAnswersSuggestPracticeWithoutCreatingCompletionEvidence() throws {
    let progress = SkillProgress.evaluate(history: [])
    let starting = try LocalProfile(goals: [.strength], baselineAbility: .startingOut)
    let familiar = try LocalProfile(goals: [.strength], baselineAbility: .somePractice)
    let regular = try LocalProfile(goals: [.strength], baselineAbility: .regularPractice)
    #expect(progress.suggestedChallengeIDs(profile: starting) == ["wallPushup", "gluteBridge"])
    #expect(progress.suggestedChallengeIDs(profile: familiar) == ["inclinePushup", "squat"])
    #expect(progress.suggestedChallengeIDs(profile: regular) == ["kneePushup", "squat"])
    #expect(progress.suggestedChallengeIDs(profile: try LocalProfile()) == [])
    #expect(progress.nodes.allSatisfy { !$0.isComplete && $0.qualifyingSets == 0 && $0.trainingDays == 0 })
    #expect(progress.points(for: .strength) == 0)
    #expect(progress.access(exerciseID: "inclinePushup", previewUnlock: false) == .locked)
}

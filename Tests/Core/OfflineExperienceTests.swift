import Foundation
import Testing
@testable import SpottrCore

@Test func onboardingPlacementUnlocksPracticeWithoutInventingWorkouts() throws {
    let profile = try LocalProfile(comfortableExercises: ["kneePushup", "halfSquat"])
    let path = LocalSkillPath.make(family: .push, profile: profile, history: [])
    #expect(path.filter { $0.state == .startingSkill }.map(\.id) == ["wallPushup", "inclinePushup", "kneePushup"])
    #expect(path.first { $0.state == .current }?.id == "pushup")
    #expect(SkillProgress.evaluate(history: []).nodes.allSatisfy { !$0.isComplete })
    #expect(QuantitativeInsights(history: []).reps == 0)
}

@Test func pathHidesDistantChallengesAndOnlyRevealsTwoLocks() throws {
    let path = LocalSkillPath.make(family: .push, profile: try LocalProfile(), history: [])
    #expect(path.count == 3)
    #expect(path[0].state == .current)
    #expect(path.filter { $0.state == .locked }.count == 2)
}

@Test func insightsExcludeReplaysAndDeduplicateSessions() throws {
    let real = try LoggedWorkout.make(exerciseID: "wallPushup", count: 8, sets: 2, reason: .voluntary)
    let replay = SessionRecord(id: UUID(), date: Date(), sets: [.init(id: UUID(), exercise: .squat, number: 1, reps: 99, target: 12, activeSeconds: 9, source: .video, reason: .target)])
    let summary = QuantitativeInsights(history: [real, real, replay])
    #expect(summary.reps == 16)
    #expect(summary.sets == 2)
    #expect(summary.sessions == 1)
    #expect(summary.cameraReps == 0)
    #expect(summary.averageRepSeconds == nil)
}

@Test func spokenCountRequiresMonotonicDistinctNumbersAndNeverJumps() {
    var counter = SpokenRepCounter(initialCount: 3)
    let first = counter.consume("four")
    #expect(first == 4)
    let repeated = counter.consume("four")
    #expect(repeated == nil)
    let second = counter.consume("four five")
    #expect(second == 5)
    let jumped = counter.consume("four five fifteen")
    #expect(jumped == nil)
    let third = counter.consume("four five six")
    #expect(third == 6)
    let reset = counter.consume("reset zero")
    #expect(reset == nil)
}

@Test func originalCoachCuesCoverEveryToneAndRotate() {
    for tone in TrainerTone.allCases {
        var library = TrainerCueLibrary()
        let lines = (0..<8).map { _ in library.next(reason: .steadyRhythm, tone: tone) }
        #expect(Set(lines).count >= 6)
        let safety = library.next(reason: .discomfort, tone: tone)
        #expect(!safety.isEmpty)
    }
}

@Test func startingPlacementsAllowEarningTheNextStepWithoutRedoingEarlierSkills() throws {
    let profile = try LocalProfile(comfortableExercises: ["kneePushup"])
    let first = try LoggedWorkout.make(exerciseID: "pushup", count: 10, sets: 2, date: Date(timeIntervalSince1970: 100000))
    let second = try LoggedWorkout.make(exerciseID: "pushup", count: 10, sets: 1, date: Date(timeIntervalSince1970: 300000))
    let path = LocalSkillPath.make(family: .push, profile: profile, history: [first, second])
    #expect(path.first { $0.id == "pushup" }?.state == .earned)
    #expect(path.first { $0.state == .current }?.id == "closeGripPushup")
}

@Test func batchedSpeechCountsSequentialNumbersWithoutRecountingOldHypotheses() {
    var counter = SpokenRepCounter()
    let first = counter.consume("one two")
    #expect(first == 2)
    let cumulative = counter.consume("one two three four")
    #expect(cumulative == 4)
    let repeated = counter.consume("one two three four")
    #expect(repeated == nil)
    let jump = counter.consume("one two three four six seven")
    #expect(jump == nil)
    let recovered = counter.consume("one two three four five six")
    #expect(recovered == 6)
}

@Test func genericTrackingAndAlignmentRecordingsSuitAllMovementViewsAndQuantities() {
    for tone in TrainerTone.allCases {
        #expect(TrainerCueLibrary.lines(reason: .tracking, tone: tone) == ["I lost sight of the movement. Your progress is saved. Move back into view when you are ready.", "Your progress is safe. Give the camera a clear view of the movement so we can continue."])
        #expect(TrainerCueLibrary.lines(reason: .alignment, tone: tone).first == "Check your starting position. Keep the movement comfortable and controlled.")
    }
}

@Test func genericEncouragementKeepsOriginalRecordingIdentityForTimedAndRaisingFamilies() {
    for tone in TrainerTone.allCases {
        var bank = TrainerCueLibrary()
        for _ in 0..<16 {
            let text = bank.next(reason: .steadyRhythm, tone: tone, exercise: .plank)
            #expect(!text.lowercased().contains("rep"))
            #expect(!text.lowercased().contains("lowering"))
            #expect(!text.lowercased().contains("press"))
            #expect(TrainerCueLibrary.lines(reason: .steadyRhythm, tone: tone).contains(text))
        }
    }
}

@Test func startingSpokenEntryNeverClampsAnExistingCameraQuantity() {
    var counter = SpokenRepCounter(initialCount: 317)
    #expect(counter.count == 317)
    #expect(counter.consume("one") == nil)
    #expect(counter.count == 317)
}

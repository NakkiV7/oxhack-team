import Foundation
import Testing
@testable import SpottrCore

@Test func curriculumCoversExactChaptersAndExistingCatalogueLevels() {
    let expected = [
        "seatedMarch,seatedKneeExtension,frontArmRaise,wallPushup,supportedSquat,standingKneeRaise,calfRaise,wallPlank,quarterSquat,sitToStand",
        "halfSquat,gluteBridge,deadBug,birdDog,kneePlank,singleLegBalance,stepJack,standingBicepsCurl,catCow,wallSit",
        "inclinePushup,squat,tempoHalfSquat,pausedHalfSquat,supportedSplitSquat,standingHipAbduction,standingHipExtension,lateralArmRaise,wallSlide,tandemBalance,kneeSidePlank,hipFlexorStretch,plank,highKnees",
        "kneePushup,wideSquat,narrowSquat,reverseLunge,forwardLunge,lateralLunge,highPlank,sidePlank,tempoSquat,pausedSquat,mountainClimber",
        "pushup,widePushup,splitSquat",
        "closeGripPushup,tempoPushup,pausedPushup,diamondPushup,assistedSquat"
    ]
    #expect(SkillCurriculum.chapters.map(\.id) == ["foundations", "rhythm", "control", "strength", "flow", "challenge"])
    #expect(SkillCurriculum.chapters.map { $0.exerciseIDs.joined(separator: ",") } == expected)
    #expect(Set(SkillCurriculum.exerciseIDs) == Set(ExerciseCatalog.all.map(\.id)))
    #expect(SkillCurriculum.exerciseIDs.count == 53)
    #expect(ExerciseCatalog.find("standingBicepsCurl")?.level == 2)
}

@Test func curriculumUnlocksFromOwnFamilyAlternativesAndPreservesIndependentEarnedEvidence() throws {
    let start = Date(timeIntervalSince1970: 1793577600)
    let records = try [LoggedWorkout.make(exerciseID: "quarterSquat", count: 10, sets: 2, date: start),
                       LoggedWorkout.make(exerciseID: "quarterSquat", count: 10, sets: 1, date: start.addingTimeInterval(86400)),
                       LoggedWorkout.make(exerciseID: "pushup", count: 10, sets: 2, date: start),
                       LoggedWorkout.make(exerciseID: "pushup", count: 10, sets: 1, date: start.addingTimeInterval(86400))]
    let prefs = try ProgrammePreferences(goals: [.strength], weekdays: [1], availableSupport: [], excludedExerciseIDs: ["quarterSquat"])
    let profile = try LocalProfile(programmePreferences: prefs)
    let map = SkillCurriculum.evaluate(profile: profile, history: records)
    #expect(map.node("quarterSquat")?.state == .earned)
    #expect(map.node("squat")?.state == .available)
    #expect(map.node("pushup")?.state == .earned)
    #expect(map.node("closeGripPushup")?.state == .available)
    #expect(map.node("singleLegBalance")?.state == .available)
    #expect(map.node("wallPushup")?.isUsable == false)
    #expect(map.node("standingBicepsCurl")?.state == .available)
    #expect(map.node("pushup")?.manualSets == 3)
    #expect(map.node("pushup")?.cameraSets == 0)
}

@Test func curriculumPlacementUnlocksWithoutEarningXPAndCannotFabricateCameraEvidence() throws {
    let profile = try LocalProfile(comfortableExercises: ["pushup"])
    let placed = SkillCurriculum.evaluate(profile: profile, history: [])
    #expect(placed.node("pushup")?.state == .placed)
    #expect(placed.node("closeGripPushup")?.state == .available)
    #expect(placed.node("pushup")?.qualifyingSets == 0)
    #expect(placed.node("pushup")?.cameraSets == 0)
    #expect(placed.points == 0)
    #expect(placed.node("squat")?.state == .locked)
    let manual = try LoggedWorkout.make(exerciseID: "singleLegBalance", count: 20, sets: 3)
    let sameDay = SkillCurriculum.evaluate(profile: profile, history: [manual, manual])
    #expect(sameDay.node("singleLegBalance")?.state == .available)
    #expect(sameDay.node("singleLegBalance")?.qualifyingSets == 3)
    #expect(sameDay.node("singleLegBalance")?.trainingDays == 1)
    #expect(sameDay.points == SkillProgress.evaluate(history: [manual]).points(for: .balance))
}

@Test func curriculumChildUsabilityPreventsAdultPracticeWithoutErasingEarnedHistory() throws {
    let date = Date(timeIntervalSince1970: 1793577600)
    let records = try [LoggedWorkout.make(exerciseID: "pushup", count: 10, sets: 2, date: date),
                       LoggedWorkout.make(exerciseID: "pushup", count: 10, sets: 1, date: date.addingTimeInterval(86400))]
    for age in [0, 4, 5, 12, 13, 17] {
        let prefs = try ProgrammePreferences(goals: [.strength], weekdays: [1],
            ageContext: TrainingAgeContext(ageYears: age, guardianManaged: true))
        let map = try SkillCurriculum.evaluate(profile: LocalProfile(programmePreferences: prefs), history: records)
        #expect(map.node("pushup")?.state == .earned)
        #expect(map.node("pushup")?.isUsable == false)
        #expect(map.node("closeGripPushup")?.isUsable == false)
        #expect(map.node("frontArmRaise")?.isUsable == (age >= 5))
        #expect(map.points == SkillProgress.evaluate(history: records).points(for: .strength))
    }
}

import Foundation
import Testing
@testable import SpottrCore

@Test func legacySetupRequiresReviewEvenWithAdultMeasurements() throws {
    let prefs = try ProgrammePreferences(goals: [.weightManagement], weekdays: [1, 3], ageContext: .init(ageYears: 30, guardianManaged: false))
    let old = try LocalProfile(bodyMeasurements: .init(heightCM: 170, weightKG: 70), onboardingRevision: 2, programmePreferences: prefs)
    #expect(!AccountPolicy.setupComplete(profile: old))
    #expect(old.trainingGoals == [.weightManagement])
}

@Test func newJuniorProfileStillNeedsPreferencesReviewWithoutBodyRequirement() throws {
    let prefs = try ProgrammePreferences(goals: [.balance], weekdays: [1], ageContext: .init(ageYears: 12, guardianManaged: true))
    #expect(!AccountPolicy.setupComplete(profile: try LocalProfile(programmePreferences: prefs)))
}

@Test func explicitUnsureIsAnAnswerForEveryFamilyAndWeightOnlyIsARealGoal() throws {
    var answers: [ExerciseFamily: TrainingSetup.Comfort] = [:]
    for family in ExerciseFamily.allCases {
        #expect(TrainingSetup.nextUnanswered(answers) == family)
        answers[family] = .unsure
    }
    #expect(TrainingSetup.nextUnanswered(answers) == nil)
    let preferences = try ProgrammePreferences(goals: [.weightManagement], weekdays: [1, 4], startingPoint: .experienced,
        ageContext: .init(ageYears: 28, guardianManaged: false), comfortAnswers: answers)
    let profile = try LocalProfile(bodyMeasurements: .init(heightCM: 170, weightKG: 70), onboardingRevision: TrainingSetup.revision, programmePreferences: preferences)
    #expect(AccountPolicy.setupComplete(profile: profile))
    #expect(profile.trainingGoals == [.weightManagement])
    #expect(!AccountPolicy.setupComplete(profile: try LocalProfile(onboardingRevision: TrainingSetup.revision, programmePreferences: preferences)))
}

@Test func measurementInputConvertsUnitsAndRejectsAmbiguousOrInvalidNumbers() throws {
    let imperial = try MeasurementUnits.imperial.measurements(height: "70", weight: "154", bmiEligible: true, thresholds: .standard)
    #expect(abs(imperial.heightCM - 177.8) < 0.001)
    #expect(abs(imperial.weightKG - 69.85322498) < 0.001)
    let metric = try MeasurementUnits.metric.measurements(height: "170,5", weight: "70,2", locale: Locale(identifier: "fr_FR"), bmiEligible: false, thresholds: nil)
    #expect(metric.heightCM == 170.5)
    #expect(metric.bmi == nil)
    for value in ["", "nan", "1e2", "70,2.4", "-70"] {
        #expect(throws: LocalBodyMeasurements.Invalid.self) {
            try MeasurementUnits.metric.measurements(height: "170", weight: value, bmiEligible: true, thresholds: .standard)
        }
    }
}

@Test func juniorReviewHasNoAdultWeightGoalAndOnlyPermittedComfort() throws {
    let adult = try ProgrammePreferences(goals: [.weightManagement], weekdays: [1], ageContext: .init(ageYears: 30, guardianManaged: false))
    let junior = try adult.changingAge(to: .init(ageYears: 10, guardianManaged: true))
    #expect(junior.goals == [.balance])
    #expect(junior.comfortAnswers.isEmpty)
    #expect(TrainingSetup.Stage.allCases.map(\.rawValue) == [1, 2, 3, 4, 5, 6])
    #expect(TrainingSetup.Stage.allCases.filter(\.canSkip) == [.permissions, .coach])
}

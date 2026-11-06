import Foundation
import Testing
@testable import SpottrCore

@Test func profileKeepsGoalsAndTrimsAnOptionalGuestName() throws {
    let profile = try LocalProfile(name: "  Omar  ", weeklyTarget: 3, goals: [.strength, .balance])
    #expect(profile.name == "Omar")
    #expect(profile.goals == [.strength, .balance])
    #expect(profile.weeklyTarget == 3)
    #expect(try LocalProfile(name: "  ", weeklyTarget: 2, goals: [.mobility]).name.isEmpty)
}

@Test func profileRejectsInvalidTargetsEmptyGoalsAndUnusableNames() {
    for target in [-1, 0, 8] {
        #expect(throws: Error.self) { try LocalProfile(weeklyTarget: target) }
    }
    #expect(throws: Error.self) { try LocalProfile(goals: []) }
    #expect(throws: Error.self) { try LocalProfile(name: String(repeating: "x", count: 41)) }
    #expect(throws: Error.self) { try LocalProfile(name: "Omar\nGuest") }
}

@Test func savedProfilesRoundTripAndCannotBypassValidationWhenDecoded() throws {
    let profile = try LocalProfile(name: "Omar", weeklyTarget: 4, goals: [.strength, .stamina])
    let data = try JSONEncoder().encode(profile)
    #expect(try JSONDecoder().decode(LocalProfile.self, from: data) == profile)
    let invalid = Data(#"{"name":"Omar","weeklyTarget":99,"goals":["strength"]}"#.utf8)
    #expect(throws: Error.self) { try JSONDecoder().decode(LocalProfile.self, from: invalid) }
}

@Test func profilesSavedBeforeBaselineQuestionsStillDecodeWithoutInventingAbility() throws {
    let data = Data(#"{"name":"Guest","weeklyTarget":3,"goals":["strength"]}"#.utf8)
    let profile = try JSONDecoder().decode(LocalProfile.self, from: data)
    #expect(profile.baselineAbility == nil)
    #expect(profile.name == "Guest")
    #expect(profile.goals == [.strength])
}

@Test func optionalBaselineRoundTripsAsSelfReportAndRejectsUnknownAnswers() throws {
    let profile = try LocalProfile(goals: [.balance], baselineAbility: .somePractice)
    #expect(try JSONDecoder().decode(LocalProfile.self, from: JSONEncoder().encode(profile)) == profile)
    let invalid = Data(#"{"name":"","weeklyTarget":3,"goals":["strength"],"baselineAbility":"verifiedAthlete"}"#.utf8)
    #expect(throws: Error.self) { try JSONDecoder().decode(LocalProfile.self, from: invalid) }
}

@Test func optionalBodyMeasurementsRoundTripWithoutChangingProfileGoalsOrAbility() throws {
    let measurements = try LocalBodyMeasurements(heightCM: 170, weightKG: 70, bmiEligible: true)
    let profile = try LocalProfile(goals: [.mobility], baselineAbility: .somePractice, bodyMeasurements: measurements)
    let restored = try JSONDecoder().decode(LocalProfile.self, from: JSONEncoder().encode(profile))
    #expect(restored == profile)
    #expect(abs(try #require(restored.bodyMeasurements?.bmi) - 24.221453) < 0.00001)
    #expect(restored.bodyMeasurements?.category == nil)
    #expect(restored.goals == [.mobility])
    #expect(restored.baselineAbility == .somePractice)
    let legacy = Data(#"{"name":"","weeklyTarget":3,"goals":["strength"]}"#.utf8)
    #expect(try JSONDecoder().decode(LocalProfile.self, from: legacy).bodyMeasurements == nil)
}

@Test func bodyMeasurementsRejectInvalidMetricValuesIncludingDecodedValues() throws {
    for height in [0, 49.9, 275.1, -170, Double.nan, .infinity] {
        #expect(throws: Error.self) { try LocalBodyMeasurements(heightCM: height, weightKG: 70) }
    }
    for weight in [0, 9.9, 500.1, -70, Double.nan, .infinity] {
        #expect(throws: Error.self) { try LocalBodyMeasurements(heightCM: 170, weightKG: weight) }
    }
    let invalid = Data(#"{"heightCM":170,"weightKG":0,"bmiEligible":true}"#.utf8)
    #expect(throws: Error.self) { try JSONDecoder().decode(LocalBodyMeasurements.self, from: invalid) }
    #expect(try LocalBodyMeasurements(heightCM: 50, weightKG: 10).bmi == nil)
    #expect(try LocalBodyMeasurements(heightCM: 275, weightKG: 500).bmi == nil)
}

@Test func bmiRequiresExplicitEligibilityRegardlessOfThresholdChoice() throws {
    let unconfirmed = try LocalBodyMeasurements(heightCM: 170, weightKG: 70, thresholds: .lower)
    #expect(unconfirmed.bmi == nil)
    #expect(unconfirmed.category == nil)
    let restored = try JSONDecoder().decode(LocalBodyMeasurements.self, from: JSONEncoder().encode(unconfirmed))
    #expect(restored == unconfirmed)
    #expect(!restored.bmiEligible)
}

@Test func bmiCategoriesUseUnroundedValuesAndOptionalBackgroundThresholds() throws {
    let cases: [(Double, LocalBodyMeasurements.Category, LocalBodyMeasurements.Category)] = [
        (18.49, .underweight, .underweight),
        (18.5, .healthyWeight, .healthyWeight),
        (22.99, .healthyWeight, .healthyWeight),
        (23, .healthyWeight, .overweight),
        (24.99, .healthyWeight, .overweight),
        (25, .overweight, .overweight),
        (27.49, .overweight, .overweight),
        (27.5, .overweight, .obesity),
        (29.99, .overweight, .obesity),
        (30, .obesity, .obesity)
    ]
    for (bmi, standard, lower) in cases {
        #expect(try LocalBodyMeasurements(heightCM: 200, weightKG: bmi * 4, bmiEligible: true, thresholds: .standard).category == standard)
        #expect(try LocalBodyMeasurements(heightCM: 200, weightKG: bmi * 4, bmiEligible: true, thresholds: .lower).category == lower)
    }
}

@Test func optionalBodyMeasurementsAreExcludedFromCoachGrounding() throws {
    let goalsOnly = try LocalProfile(goals: [.mobility])
    let measurements = try LocalBodyMeasurements(heightCM: 170, weightKG: 70, bmiEligible: true, thresholds: .lower)
    let localMeasurements = try LocalProfile(goals: [.mobility], bodyMeasurements: measurements)
    let expected = CoachGrounding.facts(history: [], profile: goalsOnly)
    let actual = CoachGrounding.facts(history: [], profile: localMeasurements)
    #expect(actual.map(\.id) == expected.map(\.id))
    #expect(actual.map(\.text) == expected.map(\.text))
}

@Test func sixBandBMIReferenceKeepsActualExtremeValuesAndExplicitApplicability() throws {
    for thresholds in LocalBodyMeasurements.Thresholds.allCases {
        let bounds: [Double] = thresholds == .standard ? [18.5, 25, 30, 35, 40] : [18.5, 23, 27.5, 32.5, 37.5]
        for (index, boundary) in bounds.enumerated() {
            let at = try LocalBodyMeasurements(heightCM: 200, weightKG: boundary * 4, bmiEligible: true, thresholds: thresholds)
            let below = try LocalBodyMeasurements(heightCM: 200, weightKG: (boundary - 0.01) * 4, bmiEligible: true, thresholds: thresholds)
            #expect(at.reference?.band == BMIReference.Band.allCases[index + 1])
            #expect(below.reference?.band == BMIReference.Band.allCases[index])
            #expect(at.reference?.boundaries == bounds)
            #expect(at.reference?.referenceWeightKG == (18.5 * 4)..<(bounds[1] * 4))
        }
    }
    let low = try #require(LocalBodyMeasurements(heightCM: 275, weightKG: 10, bmiEligible: true, thresholds: .standard).reference)
    let high = try #require(LocalBodyMeasurements(heightCM: 50, weightKG: 500, bmiEligible: true, thresholds: .lower).reference)
    #expect(low.markerPosition < 0)
    #expect(low.visualMarkerPosition == 0)
    #expect(low.edge == .below)
    #expect(high.markerPosition > 1)
    #expect(high.visualMarkerPosition == 1)
    #expect(high.edge == .above)
    #expect(high.value == 2000)
    #expect(try LocalBodyMeasurements(heightCM: 170, weightKG: 70).reference == nil)
    #expect(try LocalBodyMeasurements(heightCM: 170, weightKG: 70, bmiEligible: true).reference == nil)
}

@Test func trainingAgeContextValidatesGuardianBoundariesAndNeverInfersLegacyAge() throws {
    for age in [0, 4, 5, 12, 13, 17, 18, 120] {
        let context = try TrainingAgeContext(ageYears: age, guardianManaged: age < 18)
        #expect(context.allowsAnalytics == (age >= 18))
        #expect(context.allowsCloudPlanSync == (age >= 18))
        #expect(context.allowsHealthIntegration == (age >= 18))
        #expect(context.allowsTimePressureRewards == (age >= 18))
        #expect(try JSONDecoder().decode(TrainingAgeContext.self, from: JSONEncoder().encode(context)) == context)
    }
    for age in [-1, 121] { #expect(throws: Error.self) { try TrainingAgeContext(ageYears: age, guardianManaged: true) } }
    for age in [0, 5, 13, 17] { #expect(throws: Error.self) { try TrainingAgeContext(ageYears: age, guardianManaged: false) } }
    #expect(throws: Error.self) { try JSONDecoder().decode(TrainingAgeContext.self, from: Data(#"{"ageYears":12,"guardianManaged":false}"#.utf8)) }
    let old = try JSONDecoder().decode(LocalProfile.self, from: Data(#"{"name":"","weeklyTarget":3,"goals":["strength"]}"#.utf8))
    #expect(old.effectiveProgrammePreferences.ageContext == nil)
    #expect(old.bmiAssessment.value == nil)
    #expect(old.bmiAssessment.adultReference == nil)
    #expect(throws: ProgrammePlanner.Invalid.ageRequired) { try ProgrammePlanner.makeWeek(profile: old, history: [], start: Date()) }
}

@Test func ageAwareBMIUsesNoAdultClassificationsForChildrenOrUnknownAge() throws {
    let measurements = try LocalBodyMeasurements(heightCM: 120, weightKG: 30, bmiEligible: true, thresholds: .standard)
    for age in [0, 1, 2, 4, 5, 12, 13, 17, 18, 120] {
        let ageContext = try TrainingAgeContext(ageYears: age, guardianManaged: age < 18)
        let prefs = try ProgrammePreferences(goals: [.weightManagement], weekdays: [1], ageContext: ageContext)
        let profile = try LocalProfile(bodyMeasurements: measurements, programmePreferences: prefs)
        #expect(profile.bmiAssessment.value == (age >= 2 ? measurements.bmi : nil))
        #expect(profile.bmiAssessment.adultCategory == (age >= 18 ? measurements.category : nil))
        #expect(profile.bmiAssessment.adultReference == (age >= 18 ? measurements.reference : nil))
        #expect(profile.bmiAssessment.needsChildGrowthReference == (2..<18).contains(age))
        #expect(try LocalProfile(programmePreferences: prefs).bmiAssessment.value == nil)
    }
    #expect(try LocalProfile(bodyMeasurements: measurements).bmiAssessment.adultReference == nil)
    let nonapplicable = try LocalBodyMeasurements(heightCM: 170, weightKG: 70, bmiEligible: false, thresholds: .standard)
    let adult = try ProgrammePreferences(goals: [.strength], weekdays: [1], ageContext: TrainingAgeContext(ageYears: 30, guardianManaged: false))
    #expect(try LocalProfile(bodyMeasurements: nonapplicable, programmePreferences: adult).bmiAssessment.value == nil)
}

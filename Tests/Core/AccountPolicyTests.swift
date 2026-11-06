import Foundation
import Testing
@testable import SpottrCore

@Test func accountCheckpointNeverAllowsChildIdentityCollection() throws {
    #expect(throws: AccountPolicy.Invalid.self) { try AccountPolicy.checkpoint(ageYears: 12, role: .adultSelf) }
    let child = try AccountPolicy.checkpoint(ageYears: 12, role: .guardian)
    #expect(child.guardianManaged)
    #expect(!AccountPolicy.setupComplete(profile: try LocalProfile()))
    let preferences = try ProgrammePreferences(goals: [.balance], weekdays: [1], startingPoint: .startingOut, ageContext: child, comfortAnswers: Dictionary(uniqueKeysWithValues: ExerciseFamily.allCases.map { ($0, TrainingSetup.Comfort.unsure) }))
    #expect(AccountPolicy.setupComplete(profile: try LocalProfile(onboardingRevision: TrainingSetup.revision, programmePreferences: preferences)))
    #expect(!AccountPolicy.allowsHealth(profile: try LocalProfile(onboardingRevision: TrainingSetup.revision, programmePreferences: preferences)))
}

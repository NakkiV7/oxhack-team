import XCTest
@testable import SpottrCore

final class WorkoutAccessPolicyTests: XCTestCase {
    func testEveryOriginRequiresTrustedOwnerBeforeSetupOrMembership() throws {
        let plan = try CoachSavedPlan.catalogue(exerciseID: "frontArmRaise", sets: 1, target: 6, restSeconds: 30)
        for origin in WorkoutLaunchOrigin.allCases {
            XCTAssertEqual(WorkoutAccessPolicy.decide(trustedOwner: nil, activeOwner: nil, profile: nil, membership: false, plan: plan, origin: origin), .requiresAccount)
        }
    }
    func testAllOriginsShareSetupMembershipResumeAndJuniorSafety() throws {
        let owner = WorkoutOwner(accountID: UUID(), profileID: UUID())
        let other = WorkoutOwner(accountID: owner.accountID, profileID: UUID())
        let plan = try CoachSavedPlan.catalogue(exerciseID: "frontArmRaise", sets: 1, target: 6, restSeconds: 30)
        let adult = try profile(age: 30)
        for origin in WorkoutLaunchOrigin.allCases {
            func decide(_ p: LocalProfile?, _ member: Bool, _ active: WorkoutOwner? = nil, _ chosen: CoachSavedPlan? = nil) -> WorkoutAccessPolicy.Decision {
                WorkoutAccessPolicy.decide(trustedOwner: owner, activeOwner: active, profile: p, membership: member, plan: chosen ?? plan, origin: origin)
            }
            XCTAssertEqual(decide(nil, true), .requiresSetup)
            XCTAssertEqual(decide(adult, false), .requiresMembership)
            XCTAssertEqual(decide(adult, true), .start)
            XCTAssertEqual(decide(nil, false, owner), .resumeExisting)
            XCTAssertEqual(decide(adult, true, other), .unavailable)
            XCTAssertEqual(decide(try profile(age: 4), true), .unavailable)
            XCTAssertEqual(decide(try profile(age: 12), true), .start)
            XCTAssertEqual(decide(try profile(age: 12), true, nil, try .catalogue(exerciseID: "frontArmRaise", sets: 2, target: 6, restSeconds: 30)), .unavailable)
            XCTAssertEqual(decide(try profile(age: 16), true, nil, try .catalogue(exerciseID: "pushup", sets: 1, target: 6, restSeconds: 30)), .unavailable)
        }
    }
    private func profile(age: Int) throws -> LocalProfile {
        try LocalProfile(bodyMeasurements: .init(heightCM: 170, weightKG: 70), onboardingRevision: TrainingSetup.revision, programmePreferences: .init(goals: [.balance], weekdays: [1], startingPoint: .startingOut, ageContext: .init(ageYears: age, guardianManaged: age < 18), comfortAnswers: Dictionary(uniqueKeysWithValues: ExerciseFamily.allCases.map { ($0, TrainingSetup.Comfort.unsure) })))
    }
}

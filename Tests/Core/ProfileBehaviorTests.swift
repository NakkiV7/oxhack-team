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

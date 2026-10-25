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

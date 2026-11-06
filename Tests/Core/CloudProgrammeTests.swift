import Foundation
import Testing
@testable import SpottrCore

@Test func cloudProgrammeDTOWhitelistsAndUsesExplicitNullWithoutPrivateContext() throws {
    let preferences = try ProgrammePreferences(goals: [.balance], weekdays: [1, 3], ageContext: .init(ageYears: 30, guardianManaged: false), comfortAnswers: [.legs: .unsure])
    let dto = CloudProgrammePreferences(preferences)
    let data = try JSONEncoder().encode(dto)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(Set(object.keys) == ["goals", "weekdays", "minutesPerSession", "preferredLocalHour", "availableSupport", "allowsFloorWork", "excludedExerciseIDs", "startingPoint"])
    #expect(object["startingPoint"] is NSNull)
    let restored = try dto.restoringLocalPolicy(preferences)
    #expect(restored.ageContext == preferences.ageContext)
    #expect(restored.comfortAnswers == preferences.comfortAnswers)
    let profile = try LocalProfile(programmePreferences: preferences)
    let week = try ProgrammePlanner.makeWeek(profile: profile, history: [], start: .now)
    let plan = CloudProgramme(week)
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    let text = String(decoding: try encoder.encode(plan), as: UTF8.self)
    #expect(!text.contains("rationale"))
    #expect(!text.contains("ageContext"))
    #expect(text.contains("T"))
    #expect(try plan.restoring(profile: profile).days.map { $0.plan?.items } == week.days.map { $0.plan?.items })
}

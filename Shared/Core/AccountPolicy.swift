import Foundation

public enum AccountPolicy {
    public enum Role: String, CaseIterable, Codable, Sendable { case adultSelf, guardian }
    public enum Invalid: Error { case adultOwnerRequired }
    public static func checkpoint(ageYears: Int, role: Role) throws -> TrainingAgeContext {
        guard role == .guardian || ageYears >= 18 else { throw Invalid.adultOwnerRequired }
        return try TrainingAgeContext(ageYears: ageYears, guardianManaged: role == .guardian)
    }
    public static func setupComplete(profile: LocalProfile?) -> Bool {
        guard let profile, let age = profile.programmePreferences?.ageContext else { return false }
        return age.ageYears < 18 ? age.guardianManaged : profile.bodyMeasurements != nil
    }
    public static func allowsHealth(profile: LocalProfile?) -> Bool {
        profile?.programmePreferences?.ageContext?.allowsHealthIntegration == true
    }
}

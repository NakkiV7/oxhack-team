import Foundation

public enum WorkoutLaunchOrigin: String, CaseIterable, Sendable {
    case today, skills, coach, library, quest, watch, url
}

public struct WorkoutOwner: Equatable, Sendable {
    public let accountID: UUID
    public let profileID: UUID
    public init(accountID: UUID, profileID: UUID) { self.accountID = accountID; self.profileID = profileID }
}

public enum WorkoutAccessPolicy {
    public enum Decision: Equatable, Sendable {
        case requiresAccount, requiresSetup, requiresMembership, resumeExisting, start, unavailable
    }
    public static func decide(trustedOwner: WorkoutOwner?, activeOwner: WorkoutOwner?, profile: LocalProfile?,
                              membership: Bool, plan: CoachSavedPlan, origin: WorkoutLaunchOrigin) -> Decision {
        guard let trustedOwner else { return .requiresAccount }
        if let activeOwner { return activeOwner == trustedOwner ? .resumeExisting : .unavailable }
        guard AccountPolicy.setupComplete(profile: profile), let profile,
              let age = profile.programmePreferences?.ageContext else { return .requiresSetup }
        guard age.ageYears >= 5 else { return .unavailable }
        let preferences = profile.effectiveProgrammePreferences
        guard (try? ConfigurableSession(plan: plan, availableSupport: preferences.availableSupport)) != nil,
              plan.items.allSatisfy({ item in
                  guard let entry = ExerciseCatalog.find(item.exerciseID), preferences.canUse(entry) else { return false }
                  guard age.ageYears < 18 else { return true }
                  let maximumSets = age.ageYears < 13 ? 1 : 2
                  let maximumTarget = item.unit == .reps ? (age.ageYears < 13 ? 6 : 10) : (age.ageYears < 13 ? 10 : 20)
                  return item.sets <= maximumSets && item.target <= maximumTarget
              }) else { return .unavailable }
        return membership ? .start : .requiresMembership
    }
}

import Foundation
import Observation

@MainActor @Observable
final class NativeProfileStore {
    private(set) var profile: LocalProfile?
    private(set) var loadError: String?
    private let url: URL
    private let fixedAge: TrainingAgeContext?
    let preferencesDefaults: UserDefaults
    private var policyValid = true

    init(url: URL? = nil, fixedAge: TrainingAgeContext? = nil, preferencesDefaults: UserDefaults = .standard) {
        self.fixedAge = fixedAge
        self.preferencesDefaults = preferencesDefaults
        let root = URL.applicationSupportDirectory.appendingPathComponent("Spottr")
        let namespace = ProcessInfo.processInfo.environment["SPOTTR_DATA_NAMESPACE"].flatMap(UUID.init(uuidString:))
        let folder = namespace.map { root.appendingPathComponent($0.uuidString) } ?? root
        self.url = url ?? folder.appendingPathComponent("profile.json")
        guard FileManager.default.fileExists(atPath: self.url.path) else { return }
        do { profile = try JSONDecoder().decode(LocalProfile.self, from: Data(contentsOf: self.url)) }
        catch { loadError = "Your saved profile couldn’t be read. It hasn’t been changed. Save a profile to replace it." }
    }

    var permitsPolicyCallbacks: Bool { policyValid }
    func invalidatePolicy() { policyValid = false }

    func save(_ profile: LocalProfile) throws {
        guard policyValid, fixedAge == nil || profile.programmePreferences?.ageContext == fixedAge else { throw AccountFailure.checkpointRequired }
        if loadError != nil, FileManager.default.fileExists(atPath: url.path) {
            let archive = url.deletingLastPathComponent().appendingPathComponent("unreadable-profile-" + UUID().uuidString + ".json")
            let original = try Data(contentsOf: url)
            try ProtectedLocalStorage.write(original, to: archive)
            guard try Data(contentsOf: archive) == original else { throw CocoaError(.fileWriteUnknown) }
        }
        try ProtectedLocalStorage.write(JSONEncoder().encode(profile), to: url)
        self.profile = profile
        loadError = nil
    }

    func assessment(for measurements: LocalBodyMeasurements?) throws -> AgeAwareBMI {
        try LocalProfile(bodyMeasurements: measurements, programmePreferences: profile?.programmePreferences).bmiAssessment
    }

    func saveMeasurements(_ measurements: LocalBodyMeasurements?) throws {
        guard loadError == nil else {
            throw NSError(domain: "Spottr.LocalProfile", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Save or reset the unreadable profile before changing measurements."])
        }
        if measurements == nil && profile == nil { return }
        let current = try profile ?? LocalProfile()
        try save(LocalProfile(name: current.name, weeklyTarget: current.weeklyTarget, goals: current.goals,
                              baselineAbility: current.baselineAbility, bodyMeasurements: measurements, comfortableExercises: current.comfortableExercises,
                              weightManagementGoal: current.weightManagementGoal, onboardingRevision: current.onboardingRevision, programmePreferences: current.programmePreferences))
    }

    func shouldShowIntroduction(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        if environment["SPOTTR_FORCE_ONBOARDING"] == "1" { return true }
        if environment["SPOTTR_DATA_NAMESPACE"].flatMap(UUID.init(uuidString:)) != nil { return false }
        return !AccountPolicy.setupComplete(profile: profile)
    }

    func resetProfile() throws {
        guard policyValid else { throw AccountFailure.checkpointRequired }
        if let fixedAge {
            try save(LocalProfile(name: profile?.name ?? "Your profile", onboardingRevision: 0,
                programmePreferences: .init(goals: [.balance], weekdays: [1, 3, 5], ageContext: fixedAge)))
            return
        }
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        profile = nil
        loadError = nil
    }
}

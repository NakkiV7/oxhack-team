import Foundation
import Observation

@MainActor @Observable
final class NativeProfileStore {
    private(set) var profile: LocalProfile?
    private(set) var loadError: String?
    private let url: URL

    init(url: URL? = nil) {
        let root = URL.applicationSupportDirectory.appendingPathComponent("Spottr")
        let namespace = ProcessInfo.processInfo.environment["SPOTTR_DATA_NAMESPACE"].flatMap(UUID.init(uuidString:))
        let folder = namespace.map { root.appendingPathComponent($0.uuidString) } ?? root
        self.url = url ?? folder.appendingPathComponent("profile.json")
        guard FileManager.default.fileExists(atPath: self.url.path) else { return }
        do { profile = try JSONDecoder().decode(LocalProfile.self, from: Data(contentsOf: self.url)) }
        catch { loadError = "Your saved profile couldn’t be read. It hasn’t been changed. Save a profile to replace it." }
    }

    func save(_ profile: LocalProfile) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(profile).write(to: url, options: .atomic)
        self.profile = profile
        loadError = nil
    }

    func saveMeasurements(_ measurements: LocalBodyMeasurements?) throws {
        guard loadError == nil else {
            throw NSError(domain: "Spottr.LocalProfile", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Save or reset the unreadable profile before changing measurements."])
        }
        if measurements == nil && profile == nil { return }
        let current = try profile ?? LocalProfile()
        try save(LocalProfile(name: current.name, weeklyTarget: current.weeklyTarget, goals: current.goals,
                              baselineAbility: current.baselineAbility, bodyMeasurements: measurements))
    }

    func shouldShowIntroduction(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        if environment["SPOTTR_FORCE_ONBOARDING"] == "1" { return true }
        if environment["SPOTTR_DATA_NAMESPACE"].flatMap(UUID.init(uuidString:)) != nil { return false }
        return profile == nil
    }

    func resetProfile() throws {
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        profile = nil
        loadError = nil
    }
}

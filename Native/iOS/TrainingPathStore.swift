import Foundation
import Observation

/// The person's training path on this device: survey answers as they are given, every saved path version, and camera
/// coaching attempts. Kept in its own file beside the profile, so the workout history is never rewritten by it.
@MainActor @Observable
final class TrainingPathStore {
    struct Saved: Codable {
        var survey: PathSurvey?
        var history = PathHistory()
        var attempts: [CoachAttemptRecord] = []
    }
    private(set) var survey: PathSurvey?
    private(set) var history = PathHistory()
    private(set) var attempts: [CoachAttemptRecord] = []
    private(set) var loadError: String?
    private let url: URL

    init(url: URL? = nil, preview: Bool = false) {
        let root = URL.applicationSupportDirectory.appendingPathComponent("Spottr")
        let namespace = ProcessInfo.processInfo.environment["SPOTTR_DATA_NAMESPACE"].flatMap(UUID.init(uuidString:))
        let base = namespace.map { root.appendingPathComponent($0.uuidString) } ?? root
        let folder = preview ? base.appendingPathComponent("Preview") : base   // same folder the preview workspace uses
        self.url = url ?? folder.appendingPathComponent("training-path.json")
        guard FileManager.default.fileExists(atPath: self.url.path) else { return }
        do {
            let saved = try JSONDecoder().decode(Saved.self, from: Data(contentsOf: self.url))
            survey = saved.survey; history = saved.history; attempts = saved.attempts
        } catch { loadError = "Your saved training path couldn’t be read. It hasn’t been changed. Building a new path replaces it." }
    }

    var active: PathHistory.Version? { history.active }

    /// Answers are saved as they are given, so closing the survey keeps them.
    func saveSurvey(_ answers: PathSurvey) {
        survey = answers
        try? write()
    }

    /// Validates again and keeps every earlier version.
    @discardableResult func accept(_ path: TrainingPath, survey answers: PathSurvey, at date: Date = .now) throws -> PathHistory.Version {
        var candidate = history
        let version = try candidate.save(path, survey: answers, at: date)
        history = candidate; survey = answers; loadError = nil
        try write()
        return version
    }

    func record(_ attempt: CoachAttemptRecord) {
        attempts.removeAll { $0.id == attempt.id }
        attempts.append(attempt)
        try? write()
    }

    private func write() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(Saved(survey: survey, history: history, attempts: attempts)).write(to: url, options: .atomic)
    }
}

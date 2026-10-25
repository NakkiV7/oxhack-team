import Foundation
import Observation

@MainActor @Observable
final class PreviewWorkspace {
    private(set) var isPreview: Bool
    private(set) var store: TrainingStore
    private(set) var profileStore: NativeProfileStore
    private(set) var error: String?
    private let defaults: UserDefaults
    private let realFolder: URL
    private let flagKey: String
    private let now: () -> Date

    init(defaults: UserDefaults = .standard, rootURL: URL? = nil, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults; self.now = now
        let root = rootURL ?? URL.applicationSupportDirectory.appendingPathComponent("Spottr")
        let namespace = ProcessInfo.processInfo.environment["SPOTTR_DATA_NAMESPACE"].flatMap(UUID.init(uuidString:))
        realFolder = namespace.map { root.appendingPathComponent($0.uuidString) } ?? root
        flagKey = "preview.enabled" + (namespace.map { ".\($0.uuidString)" } ?? "")
        var preview = false
        var issue: String?
        if defaults.bool(forKey: flagKey) {
            do {
                try Self.prepare(realFolder.appendingPathComponent("Preview"), seed: true, referenceDate: now())
                preview = true
            } catch { issue = "Preview data couldn’t be opened. Your normal workspace is shown; no unreadable file was replaced." }
        }
        let folder = preview ? realFolder.appendingPathComponent("Preview") : realFolder
        isPreview = preview
        profileStore = NativeProfileStore(url: folder.appendingPathComponent("profile.json"))
        store = TrainingStore(historyURL: folder.appendingPathComponent("history.json"), defaults: defaults, previewMode: preview)
        error = issue ?? profileStore.loadError ?? store.error ?? store.rewards.loadError
    }

    func setPreview(_ enabled: Bool) throws {
        guard enabled != isPreview || defaults.bool(forKey: flagKey) != enabled else { return }
        do {
            guard !store.presented, store.sessionPhase == .idle || store.sessionPhase == .finished else {
                throw Failure.workoutInProgress
            }
            let folder = enabled ? realFolder.appendingPathComponent("Preview") : realFolder
            try Self.prepare(folder, seed: enabled, referenceDate: now())
            let nextProfile = NativeProfileStore(url: folder.appendingPathComponent("profile.json"))
            store.setVoiceFeedback(false); store.cancelCoaching()
            store.vision.stop(); store.secondaryVision.stop()
            store.companion.onCommand = nil; store.companion.onTelemetry = nil
            store.companion.onRequest = nil; store.companion.onReachability = nil; store.companion.onSnapshot = nil
            store = TrainingStore(historyURL: folder.appendingPathComponent("history.json"), defaults: defaults, previewMode: enabled)
            profileStore = nextProfile
            isPreview = enabled
            defaults.set(enabled, forKey: flagKey)
            error = nil
        } catch {
            self.error = (error as? Failure)?.errorDescription ?? "The workspace couldn’t be opened. Your current mode and saved data are unchanged."
            throw error
        }
    }

    private static func validate(_ folder: URL) throws {
        guard (try? FileManager.default.destinationOfSymbolicLink(atPath: folder.path)) == nil else { throw Failure.unreadable }
        var directory: ObjCBool = false
        if FileManager.default.fileExists(atPath: folder.path, isDirectory: &directory), !directory.boolValue {
            throw Failure.unreadable
        }
        _ = try HistoryStore(url: folder.appendingPathComponent("history.json")).load()
        let decoders: [(String, (Data) throws -> Void)] = [
            ("profile.json", { (data: Data) in _ = try JSONDecoder().decode(LocalProfile.self, from: data) }),
            ("rewards.json", { (data: Data) in _ = try JSONDecoder().decode(GamificationLedger.self, from: data) })
        ]
        for (name, decode) in decoders {
            let url = folder.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) { try decode(Data(contentsOf: url)) }
        }
    }

    private static func prepare(_ folder: URL, seed: Bool, referenceDate: Date) throws {
        try validate(folder)
        guard seed else { return }
        let manager = FileManager.default
        let missing = ["history.json", "profile.json"].filter { !manager.fileExists(atPath: folder.appendingPathComponent($0).path) }
        guard !missing.isEmpty else { return }
        let records = DemoPreviewData.sessions(referenceDate: referenceDate)
        guard !records.isEmpty else { throw Failure.unreadable }
        let staging = folder.deletingLastPathComponent().appendingPathComponent(".preview-seed-\(UUID().uuidString)")
        defer { try? manager.removeItem(at: staging) }
        if missing.contains("history.json") {
            let history = HistoryStore(url: staging.appendingPathComponent("history.json"))
            for record in records { try history.save(record) }
        }
        if missing.contains("profile.json") {
            try NativeProfileStore(url: staging.appendingPathComponent("profile.json")).save(DemoPreviewData.profile)
        }
        let createdFolder = !manager.fileExists(atPath: folder.path)
        var installed: [URL] = []
        do {
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            for name in missing {
                let destination = folder.appendingPathComponent(name)
                try manager.moveItem(at: staging.appendingPathComponent(name), to: destination)
                installed.append(destination)
            }
            try validate(folder)
        } catch {
            for url in installed { try? manager.removeItem(at: url) }
            if createdFolder, (try? manager.contentsOfDirectory(atPath: folder.path).isEmpty) == true {
                try? manager.removeItem(at: folder)
            }
            throw error
        }
    }

    private enum Failure: LocalizedError {
        case workoutInProgress, unreadable
        var errorDescription: String? {
            switch self {
            case .workoutInProgress: return "Finish and close your current workout before switching preview mode."
            case .unreadable: return "The saved workspace couldn’t be read. No unreadable files were replaced."
            }
        }
    }
}

import Foundation
import Observation
import AVFoundation

private struct LocalDemonstrationMovie: Codable {
    let exerciseID: String
    let filename: String
    let byteCount: Int
    let duration: Double
    let importedAt: Date
}

@MainActor @Observable
final class DemonstrationVideoLibrary {
    nonisolated static let maximumFileBytes = 100 * 1024 * 1024
    nonisolated static let maximumLibraryBytes = 500 * 1024 * 1024
    private(set) var recordedIDs: Set<String> = []
    private(set) var isImporting = false
    private(set) var loadError: String?
    private var movies: [String: LocalDemonstrationMovie] = [:]
    private let directory: URL
    private struct Index: Codable { let recordedIDs: Set<String>; let movies: [String: LocalDemonstrationMovie] }
    private struct PreparedMovie: Sendable { let url: URL; let byteCount: Int; let duration: Double }
    enum Failure: LocalizedError {
        case exercise, file, size, budget, video, busy, index
        var errorDescription: String? {
            switch self {
            case .exercise: return "Choose an exercise from the recording checklist."
            case .file: return "Choose a local MOV, MP4 or M4V video file."
            case .size: return "Keep each lesson video under 100 MB."
            case .budget: return "Lesson videos can use up to 500 MB. Remove a video before adding another."
            case .video: return "Choose a playable video no longer than two minutes."
            case .busy: return "Wait for the current video import to finish."
            case .index: return "Your saved lesson video index couldn’t be read. Changes are paused to keep your original video files safe."
            }
        }
    }

    init(directory: URL? = nil) {
        let root = URL.applicationSupportDirectory.appendingPathComponent("Spottr")
        let namespace = ProcessInfo.processInfo.environment["SPOTTR_DATA_NAMESPACE"].flatMap(UUID.init(uuidString:))
        self.directory = directory ?? (namespace.map { root.appendingPathComponent($0.uuidString) } ?? root)
            .appendingPathComponent("Demonstrations")
        reload()
    }
    var importedCount: Int { ExerciseCatalog.all.filter { url(for: $0.id) != nil }.count }
    func reload() {
        let indexURL = directory.appendingPathComponent("index.json")
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return }
        do {
            let index = try JSONDecoder().decode(Index.self, from: Data(contentsOf: indexURL))
            guard index.recordedIDs.allSatisfy({ ExerciseCatalog.find($0) != nil }),
                  index.movies.allSatisfy({ ExerciseCatalog.find($0.key) != nil && $0.value.exerciseID == $0.key && safeURL(filename: $0.value.filename) != nil })
            else { throw Failure.index }
            recordedIDs = index.recordedIDs
            movies = index.movies
            loadError = nil
        } catch { loadError = "Your saved lesson video index couldn’t be read. The original video files have been kept." }
    }
    func url(for exerciseID: String) -> URL? {
        guard let movie = movies[exerciseID], movie.exerciseID == exerciseID,
              let url = safeURL(filename: movie.filename),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }
    func markRecorded(_ exerciseID: String, recorded: Bool) throws {
        guard ExerciseCatalog.find(exerciseID) != nil else { throw Failure.exercise }
        var next = recordedIDs
        if recorded { next.insert(exerciseID) } else { next.remove(exerciseID) }
        try save(recorded: next, movies: movies); recordedIDs = next
    }
    func importMovie(from source: URL, exerciseID: String) async throws {
        guard ExerciseCatalog.find(exerciseID) != nil else { throw Failure.exercise }
        guard loadError == nil else { throw Failure.index }
        guard source.isFileURL, ["mov", "mp4", "m4v"].contains(source.pathExtension.lowercased()) else { throw Failure.file }
        guard !isImporting else { throw Failure.busy }
        isImporting = true
        defer { isImporting = false }
        try makeDirectory()
        let previousURL = url(for: exerciseID)
        let prepared = try await Self.prepare(source: source, directory: directory, replacing: previousURL)
        var committed = false
        defer { if !committed { try? FileManager.default.removeItem(at: prepared.url) } }
        try Task.checkCancellation()
        let movie = LocalDemonstrationMovie(exerciseID: exerciseID, filename: prepared.url.lastPathComponent,
            byteCount: prepared.byteCount, duration: prepared.duration, importedAt: Date())
        var next = movies; next[exerciseID] = movie
        try save(recorded: recordedIDs, movies: next)
        movies = next; committed = true
        if let previousURL { try? FileManager.default.removeItem(at: previousURL) }
    }
    func removeMovie(for exerciseID: String) throws {
        guard !isImporting else { throw Failure.busy }
        guard ExerciseCatalog.find(exerciseID) != nil else { throw Failure.exercise }
        let previousURL = url(for: exerciseID)
        var next = movies; next.removeValue(forKey: exerciseID)
        try save(recorded: recordedIDs, movies: next); movies = next
        if let previousURL { try FileManager.default.removeItem(at: previousURL) }
    }
    private func safeURL(filename: String) -> URL? {
        let component = URL(fileURLWithPath: filename)
        guard filename == component.lastPathComponent,
              ["mov", "mp4", "m4v"].contains(component.pathExtension.lowercased()) else { return nil }
        let url = directory.appendingPathComponent(filename)
        return url.resolvingSymlinksInPath().path.hasPrefix(directory.resolvingSymlinksInPath().path + "/") ? url : nil
    }
    private func makeDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var folder = directory
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
    }
    private func save(recorded: Set<String>, movies: [String: LocalDemonstrationMovie]) throws {
        guard loadError == nil else { throw Failure.index }
        try makeDirectory()
        let data = try JSONEncoder().encode(Index(recordedIDs: recorded, movies: movies))
        try data.write(to: directory.appendingPathComponent("index.json"), options: .atomic)
    }
    private nonisolated static func prepare(source: URL, directory: URL, replacing: URL?) async throws -> PreparedMovie {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let sourceValues = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard sourceValues.isRegularFile == true, let sourceSize = sourceValues.fileSize, sourceSize > 0 else { throw Failure.file }
        guard sourceSize <= maximumFileBytes else { throw Failure.size }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
        let used = try files.reduce(0) { try $0 + ($1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
        let replaced = try replacing?.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let available = maximumLibraryBytes - used + replaced
        guard sourceSize <= available else { throw Failure.budget }
        let destination = directory.appendingPathComponent(UUID().uuidString + "." + source.pathExtension.lowercased())
        var keep = false
        defer { if !keep { try? FileManager.default.removeItem(at: destination) } }
        let bytes = try copyBounded(source: source, destination: destination, available: available)
        let asset = AVURLAsset(url: destination)
        let duration: Double
        do {
            duration = try await asset.load(.duration).seconds
            let playable = try await asset.load(.isPlayable)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard playable, !tracks.isEmpty, duration.isFinite, duration > 0, duration <= 120 else { throw Failure.video }
        } catch { throw Failure.video }
        try Task.checkCancellation()
        keep = true
        return PreparedMovie(url: destination, byteCount: bytes, duration: duration)
    }
    private nonisolated static func copyBounded(source: URL, destination: URL, available: Int) throws -> Int {
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else { throw Failure.file }
        let input = try FileHandle(forReadingFrom: source), output = try FileHandle(forWritingTo: destination)
        defer { try? input.close(); try? output.close() }
        var bytes = 0
        while let data = try input.read(upToCount: 1_048_576), !data.isEmpty {
            try Task.checkCancellation()
            bytes += data.count
            guard bytes <= maximumFileBytes else { throw Failure.size }
            guard bytes <= available else { throw Failure.budget }
            try output.write(contentsOf: data)
        }
        return bytes
    }
}

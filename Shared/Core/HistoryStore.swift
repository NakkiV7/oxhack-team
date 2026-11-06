import Foundation

public struct HistoryStore {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> [SessionRecord] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([SessionRecord].self, from: Data(contentsOf: url))
    }
    @discardableResult
    public func save(_ record: SessionRecord) throws -> [SessionRecord] {
        let records = try load().filter { $0.id != record.id } + [record]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try ProtectedLocalStorage.write(JSONEncoder().encode(records), to: url)
        return records
    }
    public func export(to destination: URL) throws {
        guard destination.standardizedFileURL != url.standardizedFileURL else { throw CocoaError(.fileWriteInvalidFileName) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(load())
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destination, options: .atomic)
    }
    /// Remove only a previously captured deletion set; newer saved work survives recovery.
    @discardableResult
    public func remove(ids: Set<UUID>) throws -> [SessionRecord] {
        let records = try load(), retained = records.filter { !ids.contains($0.id) }
        guard retained.count != records.count else { return records }
        if retained.isEmpty { try clear() }
        else { try ProtectedLocalStorage.write(JSONEncoder().encode(retained), to: url) }
        return retained
    }
    public func clear() throws {
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}

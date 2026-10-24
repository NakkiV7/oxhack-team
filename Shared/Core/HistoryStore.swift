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
        try JSONEncoder().encode(records).write(to: url, options: .atomic)
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
    public func clear() throws {
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}

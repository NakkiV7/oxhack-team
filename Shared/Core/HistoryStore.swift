import Foundation

public struct HistoryStore {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> [SessionRecord] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([SessionRecord].self, from: Data(contentsOf: url))
    }
    public func save(_ record: SessionRecord) throws {
        let records = try load().filter { $0.id != record.id } + [record]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(records).write(to: url, options: .atomic)
    }
}

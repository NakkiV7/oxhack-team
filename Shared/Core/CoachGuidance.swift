import Foundation

public struct CoachGuidanceSource: Codable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let url: String
    public let summary: String
    public let audience: String
}

public struct CoachGuidanceRegistry: Sendable {
    public let sources: [CoachGuidanceSource]
    public init(data: Data) throws {
        struct Registry: Decodable { let version: Int; let sources: [CoachGuidanceSource] }
        guard let registry = try? JSONDecoder().decode(Registry.self, from: data), registry.version == 1,
              !registry.sources.isEmpty, registry.sources.count <= 16,
              Set(registry.sources.map(\.id)).count == registry.sources.count,
              registry.sources.allSatisfy({ !$0.id.isEmpty && !$0.title.isEmpty && !$0.summary.isEmpty && !$0.audience.isEmpty && URL(string: $0.url)?.scheme == "https" }) else { throw CoachContractError.malformed }
        sources = registry.sources
    }
    public static func bundled() throws -> CoachGuidanceRegistry {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: "coach-guidance", withExtension: "json") else { throw CoachContractError.malformed }
        return try CoachGuidanceRegistry(data: Data(contentsOf: url))
    }
    public func sources(for ids: [String]) throws -> [CoachGuidanceSource] {
        guard (1...5).contains(ids.count), Set(ids).count == ids.count,
              Set(ids).isSubset(of: Set(sources.map(\.id))) else { throw CoachContractError.invalidEvidence }
        return ids.compactMap { id in sources.first { $0.id == id } }
    }
}

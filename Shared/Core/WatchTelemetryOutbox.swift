import Foundation

public final class WatchTelemetryOutbox {
    public struct Batch: Codable, Equatable, Sendable {
        public let id: UUID
        public let samples: [WatchTelemetry]
        var sealed: Bool
    }
    private struct Contents: Codable {
        var batches: [Batch] = []
        var droppedSamples = 0
    }
    private let url: URL
    private let capacity: Int
    private var contents: Contents
    public var pendingSampleCount: Int { contents.batches.reduce(0) { $0 + $1.samples.count } }
    public var pendingBatchIDs: Set<UUID> { Set(contents.batches.map(\.id)) }
    public var droppedSampleCount: Int { contents.droppedSamples }
    public var unsealedSampleCount: Int { contents.batches.filter { !$0.sealed }.reduce(0) { $0 + $1.samples.count } }

    public init(url: URL, capacity: Int = 7200) throws {
        self.url = url; self.capacity = max(1, min(7200, capacity))
        guard FileManager.default.fileExists(atPath: url.path) else { contents = Contents(); return }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) <= 16 * 1024 * 1024 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let loaded = try JSONDecoder().decode(Contents.self, from: Data(contentsOf: url))
        guard loaded.droppedSamples >= 0, loaded.batches.count <= 7200,
              Set(loaded.batches.map(\.id)).count == loaded.batches.count,
              loaded.batches.allSatisfy({ !$0.samples.isEmpty && $0.samples.count <= 30 }),
              loaded.batches.reduce(0, { $0 + $1.samples.count }) <= self.capacity else {
            throw CocoaError(.fileReadCorruptFile)
        }
        contents = loaded
    }

    public func append(_ samples: [WatchTelemetry]) throws {
        guard !samples.isEmpty else { return }
        var next = contents
        var offset = 0
        while offset < samples.count {
            let last = next.batches.last
            let canExtend = last.map { !$0.sealed && $0.samples.count < 30 } ?? false
            let available = canExtend ? 30 - (last?.samples.count ?? 0) : 30
            let end = min(samples.count, offset + available)
            let added = Array(samples[offset..<end])
            if canExtend, let last {
                next.batches[next.batches.count - 1] = Batch(id: last.id, samples: last.samples + added, sealed: false)
            } else {
                next.batches.append(Batch(id: UUID(), samples: added, sealed: false))
            }
            offset = end
        }
        var overflow = next.batches.reduce(0, { $0 + $1.samples.count }) - capacity
        while overflow > 0, let first = next.batches.first {
            let removed = first.sealed ? first.samples.count : min(overflow, first.samples.count)
            if removed == first.samples.count { next.batches.removeFirst() }
            else { next.batches[0] = Batch(id: first.id, samples: Array(first.samples.dropFirst(removed)), sealed: false) }
            next.droppedSamples += removed; overflow -= removed
        }
        try persist(next)
    }

    public func nextBatch(excluding: Set<UUID> = [], includeUnsealed: Bool = true) throws -> Batch? {
        guard let index = contents.batches.firstIndex(where: { !excluding.contains($0.id) && ($0.sealed || includeUnsealed) }) else { return nil }
        if !contents.batches[index].sealed {
            var next = contents
            next.batches[index].sealed = true
            try persist(next)
        }
        return contents.batches[index]
    }

    public func acknowledge(_ id: UUID) throws {
        guard contents.batches.contains(where: { $0.id == id && $0.sealed }) else { return }
        var next = contents
        next.batches.removeAll { $0.id == id }
        try persist(next)
    }

    private func persist(_ next: Contents) throws {
        let data = try JSONEncoder().encode(next)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        contents = next
    }
}

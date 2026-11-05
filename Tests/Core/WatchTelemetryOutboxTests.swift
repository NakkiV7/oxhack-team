import Foundation
import Testing
@testable import SpottrCore

@Test func queuedWatchBatchesSurviveRestartAndOnlyMatchingAcknowledgementRemovesThem() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("outbox.json")
    let owner = UUID()
    let samples = (0..<35).map { queuedSample(owner, Double($0)) }
    let outbox = try WatchTelemetryOutbox(url: url)
    try outbox.append(samples)
    #expect(outbox.pendingSampleCount == 35)
    let first = try #require(try outbox.nextBatch())
    #expect(first.samples == Array(samples.prefix(30)))
    let restarted = try WatchTelemetryOutbox(url: url)
    #expect(try restarted.nextBatch()?.id == first.id)
    try restarted.acknowledge(UUID())
    #expect(restarted.pendingSampleCount == 35)
    try restarted.acknowledge(first.id)
    #expect(restarted.pendingSampleCount == 5)
    try restarted.acknowledge(first.id)
    #expect(restarted.pendingSampleCount == 5)
    let last = try #require(try restarted.nextBatch())
    #expect(last.samples == Array(samples.suffix(5)))
    try restarted.acknowledge(last.id)
    #expect(try WatchTelemetryOutbox(url: url).pendingSampleCount == 0)
}

@Test func sealedWatchBatchesStayImmutableAndOverflowIsExplicit() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let outbox = try WatchTelemetryOutbox(url: directory.appendingPathComponent("outbox.json"), capacity: 5)
    let owner = UUID()
    try outbox.append([queuedSample(owner, 0), queuedSample(owner, 1)])
    let sealed = try #require(try outbox.nextBatch())
    try outbox.append([queuedSample(owner, 2), queuedSample(owner, 3)])
    #expect(try outbox.nextBatch()?.samples == sealed.samples)
    try outbox.append([queuedSample(owner, 4), queuedSample(owner, 5)])
    #expect(outbox.pendingSampleCount <= 5)
    #expect(outbox.droppedSampleCount == 2)
    #expect(try outbox.nextBatch()?.id != sealed.id)
}

@Test func failedWatchPersistenceDoesNotForgetPreviouslyDurableSamples() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("outbox.json")
    let outbox = try WatchTelemetryOutbox(url: url)
    let owner = UUID()
    try outbox.append([queuedSample(owner, 0)])
    #expect(throws: (any Error).self) { try outbox.append([queuedSample(owner, .nan)]) }
    #expect(outbox.pendingSampleCount == 1)
    #expect(try WatchTelemetryOutbox(url: url).pendingSampleCount == 1)
    let sealed = try #require(try outbox.nextBatch())
    try FileManager.default.moveItem(at: url, to: directory.appendingPathComponent("preserved.json"))
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    #expect(throws: (any Error).self) { try outbox.acknowledge(sealed.id) }
    #expect(outbox.pendingSampleCount == 1)
}

private func queuedSample(_ owner: UUID, _ offset: Double) -> WatchTelemetry {
    .init(sessionID: owner, sentAt: Date(timeIntervalSince1970: offset), heartRate: nil,
          accelerationG: nil, rotationRadiansPerSecond: nil)
}

@Test func watchQueueBoundsTheDefaultTwoHourBacklogAndPersistsItsOverflowCount() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("outbox.json"), owner = UUID()
    let outbox = try WatchTelemetryOutbox(url: url)
    try outbox.append((0..<7201).map { queuedSample(owner, Double($0)) })
    #expect(outbox.pendingSampleCount == 7200 && outbox.droppedSampleCount == 1)
    let restored = try WatchTelemetryOutbox(url: url)
    #expect(restored.pendingSampleCount == 7200 && restored.droppedSampleCount == 1)
    let earliest = try restored.nextBatch()
    #expect(earliest?.samples.first?.sentAt == Date(timeIntervalSince1970: 1))
}

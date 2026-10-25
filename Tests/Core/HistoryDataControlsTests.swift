import Foundation
import Testing
@testable import SpottrCore

@Test func historyExportProducesAReadableSnapshotWithoutChangingSavedTraining() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = HistoryStore(url: folder.appendingPathComponent("history.json"))
    let record = try LoggedWorkout.make(exerciseID: "plank", count: 20, sets: 1)
    try store.save(record)
    let original = try Data(contentsOf: store.url)
    let destination = folder.appendingPathComponent("exports/training.json")
    try store.export(to: destination)
    #expect(try JSONDecoder().decode([SessionRecord].self, from: Data(contentsOf: destination)) == [record])
    #expect(try Data(contentsOf: store.url) == original)
    #expect(throws: Error.self) { try store.export(to: store.url) }
    #expect(try Data(contentsOf: store.url) == original)
}

@Test func historyClearRemovesOnlyHistoryAndCanBeRepeated() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = HistoryStore(url: folder.appendingPathComponent("history.json"))
    try store.save(LoggedWorkout.make(exerciseID: "wallPushup", count: 4, sets: 1))
    let profile = folder.appendingPathComponent("profile.json"), original = Data("keep profile".utf8)
    try original.write(to: profile)
    try store.clear()
    #expect(try store.load().isEmpty)
    #expect(try Data(contentsOf: profile) == original)
    try store.clear()
}

@Test func unreadableHistoryDoesNotBecomeAnEmptyExport() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let store = HistoryStore(url: folder.appendingPathComponent("history.json"))
    let original = Data("unreadable training".utf8), destination = folder.appendingPathComponent("export.json")
    try original.write(to: store.url)
    #expect(throws: Error.self) { try store.export(to: destination) }
    #expect(!FileManager.default.fileExists(atPath: destination.path))
    #expect(try Data(contentsOf: store.url) == original)
}

@Test func historySaveReturnsTheRecordsItSuccessfullyCommitted() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = HistoryStore(url: folder.appendingPathComponent("history.json"))
    let record = try LoggedWorkout.make(exerciseID: "wallPushup", count: 4, sets: 1)

    let committed: [SessionRecord] = try store.save(record)

    #expect(committed == [record])
    #expect(try store.load() == committed)
}

@Test func historySaveReturnsReplacementOrderWithoutDuplicatingTheSession() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = HistoryStore(url: folder.appendingPathComponent("history.json"))
    let first = try LoggedWorkout.make(exerciseID: "wallPushup", count: 4, sets: 1)
    let second = try LoggedWorkout.make(exerciseID: "plank", count: 20, sets: 1)
    let replacement = SessionRecord(id: first.id, date: first.date, sets: [], loggedSets: second.loggedSets)
    try store.save(first)
    #expect(try store.save(second) == [first, second])

    let committed = try store.save(replacement)

    #expect(committed == [second, replacement])
    #expect(try store.save(replacement) == committed)
    #expect(try HistoryStore(url: store.url).load() == committed)
}

@Test func failedHistorySaveDoesNotReturnCommittedRecordsOrReplaceTheFile() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = HistoryStore(url: folder.appendingPathComponent("history.json"))
    let original = try LoggedWorkout.make(exerciseID: "wallPushup", count: 4, sets: 1)
    try store.save(original)
    let originalData = try Data(contentsOf: store.url)
    let sample = WatchTelemetry(sessionID: original.id, heartRate: SensorReading(value: .nan),
                                accelerationG: nil, rotationRadiansPerSecond: nil)
    let invalid = SessionRecord(id: original.id, date: original.date, sets: [], telemetry: [sample])
    var committed: [SessionRecord]?

    #expect(throws: Error.self) { committed = try store.save(invalid) }

    #expect(committed == nil)
    #expect(try Data(contentsOf: store.url) == originalData)
    #expect(try store.load() == [original])
}

@Test func historyFilesystemFailureDoesNotReturnCommittedRecords() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let blocker = folder.appendingPathComponent("blocked-parent"), original = Data("keep file".utf8)
    try original.write(to: blocker)
    let store = HistoryStore(url: blocker.appendingPathComponent("history.json"))
    let record = try LoggedWorkout.make(exerciseID: "wallPushup", count: 4, sets: 1)
    var committed: [SessionRecord]?

    #expect(throws: Error.self) { committed = try store.save(record) }

    #expect(committed == nil)
    #expect(try Data(contentsOf: blocker) == original)
}

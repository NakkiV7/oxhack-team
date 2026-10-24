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

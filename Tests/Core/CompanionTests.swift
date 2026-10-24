import Foundation
import Testing
@testable import SpottrCore

@Test func companionCommandsCannotAffectAnotherSet() {
    var session = TrainingSession()
    session.start(at: 0)
    let pause = CompanionCommand(sessionID: session.id, generation: session.generation, action: .pause)
    session.apply(pause, at: 1)
    #expect(session.phase == .paused)
    session.resume(at: 2)
    session.apply(pause, at: 3)
    #expect(session.phase == .active)
    let end = CompanionCommand(sessionID: UUID(), generation: session.generation, action: .endSet)
    session.apply(end, at: 4)
    #expect(session.sets.isEmpty)
}

@Test func snapshotRoundTripsAndExpiresInsteadOfShowingOldLiveCounts() throws {
    var session = TrainingSession()
    session.start(at: 0)
    let now = Date(timeIntervalSince1970: 1000)
    let snapshot = CompanionSnapshot(session: session, sentAt: now)
    let decoded = try JSONDecoder().decode(CompanionSnapshot.self, from: JSONEncoder().encode(snapshot))
    #expect(decoded.sessionID == session.id)
    #expect(decoded.isFresh(at: now.addingTimeInterval(3)))
    #expect(!decoded.isFresh(at: now.addingTimeInterval(20)))
    #expect(!decoded.isFresh(at: now.addingTimeInterval(-30)))
}

@Test func localHistorySurvivesReopeningWithoutDuplicatingSession() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = HistoryStore(url: folder.appendingPathComponent("history.json"))
    var session = TrainingSession()
    session.start(at: 0); session.endSet(at: 1); session.finish(at: 1)
    try store.save(session.record)
    try store.save(session.record)
    let reopened = HistoryStore(url: folder.appendingPathComponent("history.json"))
    #expect(try reopened.load() == [session.record])
}

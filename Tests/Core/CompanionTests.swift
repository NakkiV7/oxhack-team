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

@Test func watchWaitsForFreshStateBeforeAllowingControls() {
    var session = TrainingSession()
    session.start(at: 0)
    let now = Date()
    var state = CompanionState()
    let first = CompanionSnapshot(session: session, sentAt: now)
    state.receive(first, now: now)
    #expect(state.snapshot?.phase == .active)
    #expect(state.command(.pause, now: now)?.generation == session.generation)
    #expect(state.command(.resume, now: now) == nil)
    session.pause(at: 1)
    state.receive(.init(session: session, sentAt: now.addingTimeInterval(2)), now: now.addingTimeInterval(2))
    state.receive(first, now: now.addingTimeInterval(3))
    #expect(state.snapshot?.phase == .paused)
    #expect(state.command(.resume, now: now.addingTimeInterval(20)) == nil)
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

@Test func legacyManualCompanionCountUsesOnlyExplicitlyEnteredReps() {
    var session = TrainingSession()
    session.start(at: 0)
    session.restartSet(source: .manual, at: 1)
    #expect(CompanionSnapshot(session: session).reps == 0)
    session.setManualReps(7)
    #expect(CompanionSnapshot(session: session).reps == 7)
}

@Test func manualLegacyWatchPromptIdentifiesSelfReportAcrossActivePausedAndRest() throws {
    var session = TrainingSession()
    session.start(at: 0)
    session.restartSet(source: .manual, at: 1)
    let active = CompanionSnapshot(session: session)
    let decoded = try JSONDecoder().decode(CompanionSnapshot.self, from: JSONEncoder().encode(active))
    #expect(decoded.source == .manual)
    #expect(decoded.manualRepInstruction == "Manual · iPhone")
    session.pause(at: 2)
    #expect(CompanionSnapshot(session: session).manualRepInstruction == "Manual · Paused")
    session.setManualReps(3)
    session.endSet(at: 3)
    #expect(CompanionSnapshot(session: session).manualRepInstruction == "Manual · Rest")
    session.nextSet(at: 4)
    #expect(CompanionSnapshot(session: session).source == .camera)
    #expect(CompanionSnapshot(session: session).manualRepInstruction == nil)
}

@Test func snapshotsWithoutLegacySourceMetadataStillDecodeAndKeepExistingGuidance() throws {
    let data = Data("""
    {"sessionID":"00000000-0000-0000-0000-000000000001",
     "generation":"00000000-0000-0000-0000-000000000002",
     "exercise":"squat","phase":"active","reps":2,"target":12,
     "setNumber":1,"cue":"lower","sentAt":1000}
    """.utf8)
    let decoded = try JSONDecoder().decode(CompanionSnapshot.self, from: data)
    #expect(decoded.source == nil)
    #expect(decoded.manualRepInstruction == nil)
    #expect(decoded.reps == 2)
    #expect(decoded.cue == .lower)
}

@Test func skippedConfiguredStepRequiresPhoneCheckInWithoutChangingLegacySnapshotDecoding() throws {
    let plan = try CoachSavedPlan.catalogue(exerciseID: "squat", sets: 2, target: 8, restSeconds: 30)
    var run = try ConfigurableSession(plan: plan, availableSupport: [])
    run.start(at: 0); run.beginSet(at: 1)
    let skipped = run.skipSet(at: 2)
    #expect(skipped)
    let now = Date()
    let snapshot = CompanionSnapshot(session: run, at: 3, sentAt: now)
    #expect(snapshot.configured?.currentWasSkipped == true)
    #expect(snapshot.isFresh(at: now))
    let encoded = try JSONEncoder().encode(snapshot)
    let reopened = try JSONDecoder().decode(CompanionSnapshot.self, from: encoded)
    #expect(reopened.configured?.currentWasSkipped == true)
    var state = CompanionState(); state.receive(reopened, now: now)
    #expect(state.command(.nextSet, now: now) == nil)
    #expect(state.command(.finish, now: now) != nil)
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    var configured = try #require(object["configured"] as? [String: Any])
    configured.removeValue(forKey: "currentWasSkipped"); object["configured"] = configured
    let legacy = try JSONDecoder().decode(CompanionSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(legacy.configured?.currentWasSkipped == nil)
    #expect(legacy.isFresh(at: now))
    var oldState = CompanionState(); oldState.receive(legacy, now: now)
    #expect(oldState.command(.nextSet, now: now) != nil)
    object["phase"] = "active"; configured["currentWasSkipped"] = true; object["configured"] = configured
    let invalid = try JSONDecoder().decode(CompanionSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(!invalid.isFresh(at: now))
    run.nextSet(at: 5)
    #expect(CompanionSnapshot(session: run, at: 5).configured?.currentWasSkipped == false)
}

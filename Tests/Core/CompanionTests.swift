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
    #expect(decoded.manualRepInstruction == "Enter reps on iPhone")
    session.pause(at: 2)
    #expect(CompanionSnapshot(session: session).manualRepInstruction == "Manual entry is paused")
    session.setManualReps(3)
    session.endSet(at: 3)
    #expect(CompanionSnapshot(session: session).manualRepInstruction == "Rest after manual entry")
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

@Test func cameraAmbiguityNeedsIntentionalResumeWithoutPausingWorkoutAndRejectsOldGeneration() throws {
    var session = TrainingSession()
    session.start(at: 0)
    let original = session.generation
    session.consume(.init(time: 1, angle: .nan, confidence: 0, observation: .multiplePeople), generation: original)
    #expect(session.phase == .active)
    var state = CompanionState()
    let now = Date()
    state.receive(.init(session: session, sentAt: now), now: now)
    let resume = try #require(state.command(.resume, now: now))
    session.apply(resume, at: 2)
    #expect(session.generation != original)
    #expect(session.elapsed(at: 3) == 3)
    session.consume(.init(time: 3, angle: .nan, confidence: 0, observation: .multiplePeople), generation: original)
    #expect(!session.counter.requiresIdentityAcknowledgement)
    session.pause(at: 4)
    session.resume(at: 5)
    #expect(session.elapsed(at: 6) == 5)
}

@Test func cameraRecoverySnapshotIsOptionalForOlderMessagesAndCannotEnableManualControls() throws {
    var session = TrainingSession(); session.start(at:0)
    session.consume(.init(time:0,angle:.nan,confidence:0,observation:.multiplePeople),generation:session.generation)
    let now=Date()
    let data=try JSONEncoder().encode(CompanionSnapshot(session:session,sentAt:now))
    var object=try #require(JSONSerialization.jsonObject(with:data) as? [String:Any])
    object.removeValue(forKey:"cameraRecoveryState")
    let older=try JSONDecoder().decode(CompanionSnapshot.self,from:JSONSerialization.data(withJSONObject:object))
    #expect(older.cameraRecoveryState == nil)
    #expect(older.isFresh(at:now))
    object["cameraRecoveryState"]="needsResume"
    object["source"]="manual"
    let manual=try JSONDecoder().decode(CompanionSnapshot.self,from:JSONSerialization.data(withJSONObject:object))
    #expect(!manual.isFresh(at:now))
    session.switchInput(source:.manual,at:1); session.setManualReps(4)
    session.switchInput(source:.camera,at:2)
    #expect(session.cameraRecoveryState == .needsResume)
    #expect(session.actualReps == 4)
}

@Test func watchRecoveryControlNamesTheResumeActionItActuallySends() {
    var run=TrainingSession(); run.start(at:0)
    #expect(CompanionSnapshot(session:run).pauseResumeTitle == "Pause")
    run.consume(.init(time:1,angle:.nan,confidence:0,observation:.multiplePeople),generation:run.generation)
    #expect(CompanionSnapshot(session:run).pauseResumeTitle == "Resume camera")
    run.resume(at:2)
    #expect(CompanionSnapshot(session:run).pauseResumeTitle == "Pause")
    run.pause(at:3)
    #expect(CompanionSnapshot(session:run).pauseResumeTitle == "Resume")
}

@Test func quickManualPauseResumeCannotAcknowledgeCameraIdentityRecovery() {
    var run = TrainingSession(); run.start(at: 0)
    run.consume(.init(time: 0, angle: .nan, confidence: 0, observation: .multiplePeople), generation: run.generation)
    run.switchInput(source: .manual, at: 1); run.setManualReps(4)
    run.pause(at: 2); run.resume(at: 5)
    #expect(run.actualReps == 4)
    #expect(run.elapsed(at: 6) == 3)
    run.switchInput(source: .camera, at: 6)
    #expect(run.cameraRecoveryState == .needsResume)
    #expect(CompanionSnapshot(session: run).pauseResumeTitle == "Resume camera")
    for time in stride(from: 6.0, through: 9.0, by: 0.1) {
        run.consume(.init(time: time, angle: 170), generation: run.generation)
    }
    for (time, angle) in [(9.2,90.0),(9.4,90),(9.8,170),(10.0,170)] {
        run.consume(.init(time: time, angle: angle), generation: run.generation)
    }
    #expect(run.cameraRecoveryState == .needsResume)
    #expect(run.actualReps == 4)
    run.resume(at: 11)
    #expect(run.cameraRecoveryState == .waitingForClear)
    for time in stride(from: 11.0, through: 13.3, by: 0.1) {
        run.consume(.init(time: time, angle: 170), generation: run.generation)
    }
    #expect(run.cameraRecoveryState == .ready)
    for (time, angle) in [(13.5,90.0),(13.7,90),(14.1,170),(14.3,170)] {
        run.consume(.init(time: time, angle: angle), generation: run.generation)
    }
    #expect(run.actualReps == 5)
}

@Test func importedVideoRecoveryStillRequiresAndAcceptsExplicitVisualResume() throws {
    var run = TrainingSession(); run.start(at: 0); run.restartSet(source: .video, at: 0)
    run.consume(.init(time: 1, angle: .nan, confidence: 0, observation: .multiplePeople), generation: run.generation)
    #expect(run.cameraRecoveryState == .needsResume)
    let now = Date(), snapshot = CompanionSnapshot(session: run)
    #expect(snapshot.isFresh(at: now))
    var companion = CompanionState(); companion.receive(snapshot, now: now)
    let command = try #require(companion.command(.resume, now: now))
    run.apply(command, at: 2)
    #expect(run.cameraRecoveryState == .waitingForClear)
    for time in stride(from: 2.0, through: 4.1, by: 0.1) {
        run.consume(.init(time: time, angle: 170), generation: run.generation)
    }
    #expect(run.cameraRecoveryState == .ready)
}


@Test func configuredCompanionTransportsEarnedOriginIndependentlyOfSelectedCamera() throws {
    var run = try ConfigurableSession(plan: CoachSavedPlan.catalogue(exerciseID: "plank", sets: 1, target: 10, restSeconds: 30), availableSupport: [])
    run.start(at: 0); run.beginSet(at: 0)
    run.switchInput(source: .camera, at: 2)
    let snapshot = CompanionSnapshot(session: run, at: 2)
    let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
    let configured = try #require(json["configured"] as? [String: Any])
    #expect(configured["source"] as? String == "camera")
    #expect(configured["quantityOrigin"] as? String == "activeTimer")
    #expect(configured["measuredSeconds"] as? Double == 2)
    let restored = try JSONDecoder().decode(CompanionSnapshot.self, from: JSONEncoder().encode(snapshot))
    #expect(restored.configured?.quantityOrigin == .activeTimer)
    #expect(restored.quantityAccessibilityValue == "2 of 10 seconds. Manual hold, active timer.")
}

private func originRun(_ id: String = "plank") throws -> ConfigurableSession {
    try ConfigurableSession(plan: CoachSavedPlan.catalogue(exerciseID: id, sets: 1, target: 10, restSeconds: 30), availableSupport: [])
}
private func observeHold(_ run: inout ConfigurableSession, at time: Double) {
    run.consume(.init(time: time, angle: 170, confidence: 1, provenance: .posture, holdQualification: .staticHold), generation: run.generation)
}
private func observeRep(_ run: inout ConfigurableSession, at start: Double) {
    for (time, angle) in [(0.0,170.0),(0.2,170),(0.6,90),(0.8,90),(1.2,170),(1.4,170)] {
        run.consume(.init(time: start + time, angle: angle), generation: run.generation)
    }
}

@Test func configuredCompanionManualToCameraLabelsOnlyEarnedIntervalsAndKeepsControls() throws {
    var run = try originRun(); run.start(at: 0); run.beginSet(at: 0)
    run.switchInput(source: .camera, at: 2)
    let now = Date()
    for time in [2.0, 2.2] {
        observeHold(&run, at: time)
        let snapshot = CompanionSnapshot(session: run, at: time, sentAt: now)
        let expected = time == 2 ? "Manual hold, active timer" : "Camera + manual quantity"
        #expect(snapshot.configured?.quantityOrigin == (time == 2 ? .activeTimer : .mixed))
        #expect(snapshot.quantityOriginLabel == expected)
        #expect(snapshot.quantityAccessibilityValue == "2 of 10 seconds. \(expected).")
        #expect(snapshot.configured?.source == .camera)
        #expect(abs((snapshot.configured?.displaySeconds ?? -1) - time) < 0.000001)
        #expect(snapshot.isFresh(at: now)); #expect(!snapshot.isFresh(at: now.addingTimeInterval(11)))
        var state = CompanionState(); state.receive(snapshot, now: now)
        #expect(state.command(.pause, now: now) != nil)
        #expect(state.command(.endSet, now: now) != nil)
        #expect(state.command(.endSet, now: now.addingTimeInterval(11)) == nil)
    }
    run.endSet(at: 4)
    for time in [10.0, 20.0] {
        if time == 20 { run.nextSet(at: time) }
        let snapshot = CompanionSnapshot(session: run, at: time, sentAt: now)
        #expect(snapshot.configured?.quantityOrigin == .mixed)
        #expect(snapshot.quantityOriginLabel == "Camera + manual quantity")
        #expect(abs((snapshot.configured?.displaySeconds ?? -1) - 2.2) < 0.000001)
        #expect(snapshot.configured?.activeSeconds == 4)
        #expect(snapshot.isFresh(at: now))
    }
}

@Test func configuredCompanionCameraToManualDoesNotRelabelUntilManualAccrues() throws {
    var run = try originRun(); run.start(at: 0); run.resetSet(source: .camera, at: 0); run.beginSet(at: 0)
    for time in [0.0, 0.2, 0.4] { observeHold(&run, at: time) }
    run.switchInput(source: .manual, at: 1)
    let before = CompanionSnapshot(session: run, at: 1)
    #expect(before.configured?.source == .manual)
    #expect(before.configured?.quantityOrigin == .cameraObserved)
    #expect(before.quantityOriginLabel == "Camera observation")
    #expect(before.quantityAccessibilityValue == "0 of 10 seconds. Camera observation.")
    let after = CompanionSnapshot(session: run, at: 2)
    #expect(after.configured?.quantityOrigin == .mixed)
    #expect(after.quantityOriginLabel == "Camera + manual quantity")
    #expect(abs((after.configured?.displaySeconds ?? -1) - 1.4) < 0.000001)
    run.endSet(at: 2)
    #expect(CompanionSnapshot(session: run, at: 10).configured?.quantityOrigin == .mixed)
    run.finish(at: 11)
    #expect(CompanionSnapshot(session: run, at: 20).configured?.quantityOrigin == .mixed)
}

@Test func configuredCompanionRepOriginsSurviveInputSwitchesAndEndedStates() throws {
    var manual = try originRun("squat"); manual.start(at: 0); manual.beginSet(at: 0); manual.setReps(3)
    manual.switchInput(source: .camera, at: 1)
    #expect(CompanionSnapshot(session: manual, at: 1).quantityOriginLabel == "Manual self-report")
    observeRep(&manual, at: 2)
    let mixed = CompanionSnapshot(session: manual, at: 4)
    #expect(mixed.reps == 4)
    #expect(mixed.configured?.quantityOrigin == .mixed)
    #expect(mixed.quantityAccessibilityValue == "4 of 10 reps. Camera + manual quantity.")
    manual.endSet(at: 4)
    #expect(CompanionSnapshot(session: manual, at: 5).configured?.quantityOrigin == .mixed)
    manual.finish(at: 6)
    #expect(CompanionSnapshot(session: manual, at: 7).configured?.quantityOrigin == .mixed)

    var camera = try originRun("squat"); camera.start(at: 0); camera.resetSet(source: .camera, at: 0); camera.beginSet(at: 0)
    observeRep(&camera, at: 0)
    camera.switchInput(source: .manual, at: 2)
    let unchanged = CompanionSnapshot(session: camera, at: 2)
    #expect(unchanged.configured?.source == .manual)
    #expect(unchanged.quantityOriginLabel == "Camera observation")
    #expect(unchanged.configured?.quantityOrigin == .cameraObserved)
    camera.setReps(2)
    #expect(CompanionSnapshot(session: camera, at: 2).configured?.quantityOrigin == .mixed)

    var pureCamera = try originRun("squat"); pureCamera.start(at: 0); pureCamera.resetSet(source: .camera, at: 0); pureCamera.beginSet(at: 0)
    observeRep(&pureCamera, at: 0); pureCamera.switchInput(source: .manual, at: 2); pureCamera.endSet(at: 3)
    #expect(pureCamera.completed.last?.quantityOrigin == nil) // Saved legacy representation is unchanged.
    #expect(CompanionSnapshot(session: pureCamera, at: 4).configured?.quantityOrigin == .cameraObserved)
}

@Test func configuredCompanionEndedManualTimerUsesEndedOriginInsteadOfClearedLiveClock() throws {
    var run = try originRun(); run.start(at: 0); run.beginSet(at: 0); run.endSet(at: 3)
    for time in [4.0, 10.0] {
        if time == 10 { run.finish(at: time) }
        let snapshot = CompanionSnapshot(session: run, at: time)
        #expect(snapshot.configured?.quantityOrigin == .activeTimer)
        #expect(snapshot.quantityOriginLabel == "Manual hold, active timer")
        #expect(snapshot.configured?.displaySeconds == 3)
    }
}

@Test func configuredCompanionLegacyOriginIsUnknownRegardlessOfSelectedSource() throws {
    var run = try originRun(); run.start(at: 0); run.beginSet(at: 0); run.switchInput(source: .camera, at: 2)
    let now = Date()
    var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(CompanionSnapshot(session: run, at: 2, sentAt: now))) as? [String: Any])
    var configured = try #require(object["configured"] as? [String: Any])
    configured.removeValue(forKey: "quantityOrigin")
    for source in ["manual", "camera"] {
        configured["source"] = source; object["configured"] = configured
        let legacy = try JSONDecoder().decode(CompanionSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(legacy.configured?.quantityOrigin == nil)
        #expect(legacy.quantityOriginLabel == "Quantity origin unavailable")
        #expect(legacy.quantityAccessibilityValue == "2 of 10 seconds. Quantity origin unavailable.")
        #expect(legacy.isFresh(at: now))
    }
    configured.removeValue(forKey: "source"); configured.removeValue(forKey: "measuredSeconds"); object["configured"] = configured
    let oldest = try JSONDecoder().decode(CompanionSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(oldest.configured?.displaySeconds == 2)
    #expect(oldest.quantityOriginLabel == "Quantity origin unavailable")
    #expect(oldest.isFresh(at: now))
}

@Test func configuredCompanionOriginRejectsKnownUnitContradictionsWithoutTyingOriginToInput() throws {
    let now = Date()
    for (id, impossible) in [("plank", "selfReport"), ("squat", "activeTimer")] {
        var run = try originRun(id); run.start(at: 0); run.beginSet(at: 0); run.setReps(2)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(CompanionSnapshot(session: run, at: 2, sentAt: now))) as? [String: Any])
        var configured = try #require(object["configured"] as? [String: Any])
        configured["quantityOrigin"] = impossible; object["configured"] = configured
        let invalid = try JSONDecoder().decode(CompanionSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(!invalid.isFresh(at: now))
    }
}

@Test func configuredCompanionCameraOriginCannotTurnLegacyElapsedIntoObservedSeconds() throws {
    var run = try originRun(); run.start(at: 0); run.resetSet(source: .camera, at: 0); run.beginSet(at: 0)
    observeHold(&run, at: 0); observeHold(&run, at: 0.2); run.switchInput(source: .manual, at: 1)
    let now = Date()
    var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(CompanionSnapshot(session: run, at: 1, sentAt: now))) as? [String: Any])
    var configured = try #require(object["configured"] as? [String: Any])
    configured.removeValue(forKey: "measuredSeconds")
    for origin in ["cameraObserved", "mixed"] {
        configured["quantityOrigin"] = origin; object["configured"] = configured
        let invalid = try JSONDecoder().decode(CompanionSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(!invalid.isFresh(at: now))
    }
}

@Test func configuredCompanionEmptyQuantityHasClearAccessibleTextWithoutClaimingSelectedCameraWork() throws {
    var run = try originRun("squat"); run.start(at: 0)
    #expect(CompanionSnapshot(session: run, at: 0).quantityAccessibilityValue == "No quantity entered. Target 10 reps. No quantity recorded.")
    run.resetSet(source: .camera, at: 0)
    let camera = CompanionSnapshot(session: run, at: 0)
    #expect(camera.configured?.quantityOrigin == nil)
    #expect(camera.quantityOriginLabel == "No quantity recorded")
    #expect(camera.quantityAccessibilityValue == "0 of 10 reps. No quantity recorded.")
}

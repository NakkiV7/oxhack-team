import Foundation
import Testing
@testable import SpottrCore

private func customPlan(_ items: String = """
{"exerciseID":"wallPushup","sets":2,"target":8,"unit":"reps","restSeconds":30},
{"exerciseID":"plank","sets":1,"target":20,"unit":"seconds","restSeconds":45}
""") throws -> CoachSavedPlan {
    try JSONDecoder().decode(CoachSavedPlan.self, from: Data("""
    {"items":[\(items)],"approvedAt":0,"rationale":"Offline test fixture"}
    """.utf8))
}

@Test func configuredSessionRetainsValidEnergyAndRejectsInvalidFutureOrPriorRunTiming() throws {
    var session = try ConfigurableSession(plan: customPlan(), availableSupport: ["Wall"])
    session.start(at: 0)
    let now = session.date.addingTimeInterval(10), run = UUID()
    func message(_ energy: ActiveEnergy) -> WatchTelemetry {
        .init(sessionID: session.id, sentAt: now, heartRate: nil, accelerationG: nil,
              rotationRadiansPerSecond: nil, activeEnergy: energy)
    }
    for energy in [ActiveEnergy(recordingID: run, kilocalories: -.infinity, asOf: now),
                   .init(recordingID: run, kilocalories: 2, asOf: now.addingTimeInterval(3)),
                   .init(recordingID: run, kilocalories: 2, asOf: session.date.addingTimeInterval(-3))] {
        session.receiveTelemetry(message(energy), now: now)
    }
    #expect(session.record.telemetry.isEmpty)
    let accepted = message(.init(recordingID: run, kilocalories: 2, asOf: session.date))
    session.receiveTelemetry(accepted, now: now)
    #expect(session.record.telemetry == [accepted])
    session.finish(at: 1)
    session.receiveTelemetry(.init(sessionID: session.id, sentAt: now.addingTimeInterval(1), heartRate: nil,
                                   accelerationG: nil, rotationRadiansPerSecond: nil,
                                   activeEnergy: .init(recordingID: run, kilocalories: 3, asOf: now)), now: now.addingTimeInterval(1))
    #expect(session.record.telemetry == [accepted])
}

@Test func configuredQueuePreservesApprovedOrderQuantitiesAndUnitsWithoutCompletedWork() throws {
    let run = try ConfigurableSession(plan: customPlan(), availableSupport: ["Wall"])
    #expect(run.steps.map(\.exerciseID) == ["wallPushup", "wallPushup", "plank"])
    #expect(run.steps.map(\.target) == [8, 8, 20])
    #expect(run.steps.map(\.unit) == [.reps, .reps, .seconds])
    #expect(run.record.setCount == 0)
    #expect(run.phase == .idle)
}

@Test func mixedRunRecordsOnlyExplicitRepsAndActiveHoldSecondsWithActualRest() throws {
    var run = try ConfigurableSession(plan: customPlan(), availableSupport: ["Wall"])
    run.start(at: 0)
    #expect(run.elapsed(at: 10) == 0)
    let unstarted = run.endSet(at: 10)
    #expect(!unstarted)
    run.beginSet(at: 10)
    let missingReps = run.endSet(at: 11)
    #expect(!missingReps)
    run.setReps(5)
    let first = run.endSet(at: 14)
    #expect(first)
    #expect(run.record.loggedSets.first?.reps == 5)
    #expect(run.record.loggedSets.first?.target == 8)
    #expect(run.record.loggedSets.first?.activeSeconds == 4)
    #expect(run.record.loggedSets.first?.restSecondsBefore == nil)
    run.nextSet(at: 25)
    #expect(run.current.number == 2)
    #expect(run.record.setCount == 1)
    run.beginSet(at: 30)
    run.setReps(8)
    let second = run.endSet(at: 34)
    #expect(second)
    run.nextSet(at: 50)
    #expect(run.current.exerciseID == "plank")
    run.beginSet(at: 60)
    run.pause(at: 65)
    run.resume(at: 100)
    let hold = run.endSet(at: 110)
    #expect(hold)
    #expect(run.record.loggedSets.map(\.reps) == [5, 8, 0])
    #expect(run.record.loggedSets.map(\.restSecondsBefore) == [nil, 16, 26])
    #expect(run.record.loggedSets.last?.seconds == 15)
    #expect(run.record.loggedSets.last?.quantityOrigin == .activeTimer)
    #expect(WorkoutReport(record: run.record).sets.last?.sourceLabel == "Manual hold timer")
    #expect(CoachGrounding.facts(history: [run.record]).contains { $0.text.contains("Manual hold timer") })
    #expect(run.record.activeSeconds == 23)
    run.nextSet(at: 120)
    #expect(run.phase == .finished)
    #expect(run.record.setCount == 3)
}

@Test func configuredDiscomfortLatchesAndFinishNeverInventsRemainingSets() throws {
    var run = try ConfigurableSession(plan: customPlan(), availableSupport: ["Wall"])
    run.start(at: 0); run.beginSet(at: 1); run.setReps(3); run.endSet(at: 4)
    run.feedback(reserve: 1, reason: .discomfort)
    run.feedback(reserve: 2, reason: .target)
    run.nextSet(at: 10)
    #expect(run.phase == .rest)
    #expect(run.stoppedForDiscomfort)
    #expect(run.completed.first?.reason == .discomfort)
    #expect(run.completed.first?.reserve == 2)
    run.finish(at: 20)
    #expect(run.record.setCount == 1)
    #expect(run.phase == .finished)
    let data = try JSONEncoder().encode(run.record)
    #expect(try JSONDecoder().decode(SessionRecord.self, from: data) == run.record)
}

@Test func configuredReportsKeepActualActiveTimeRestAndManualSource() throws {
    var run = try ConfigurableSession(plan: customPlan(), availableSupport: ["Wall"])
    run.start(at: 0); run.beginSet(at: 10); run.setReps(4); run.endSet(at: 14)
    run.nextSet(at: 24); run.beginSet(at: 30); run.setReps(7); run.endSet(at: 33)
    run.finish(at: 34)
    let report = WorkoutReport(record: run.record)
    #expect(report.activeSeconds == 7)
    #expect(report.recordedRestSeconds == 16)
    #expect(report.sets.map(\.exerciseID) == ["wallPushup", "wallPushup"])
    #expect(report.sets.allSatisfy { $0.source == .manual })
    #expect(report.sets.last?.reserve == nil)
}

@Test func configuredTelemetryRejectsOtherSessionsAndPreservesOnlyReceivedObservations() throws {
    var run = try ConfigurableSession(plan: customPlan(), availableSupport: ["Wall"])
    run.start(at: 0)
    let date = Date(timeIntervalSince1970: 100)
    let observed = WatchTelemetry(sessionID: run.id, sentAt: date,
        heartRate: .init(value: 85, date: date), accelerationG: nil, rotationRadiansPerSecond: nil)
    run.receiveTelemetry(observed, now: date)
    run.receiveTelemetry(observed, now: date)
    run.receiveTelemetry(.init(sessionID: UUID(), sentAt: date.addingTimeInterval(1),
        heartRate: .init(value: 86, date: date), accelerationG: nil, rotationRadiansPerSecond: nil), now: date)
    #expect(run.record.telemetry == [observed])
}

@Test func configuredWatchUsesGenericIdentityAndCannotSubmitAnUnenteredRepTarget() throws {
    var run = try ConfigurableSession(plan: customPlan(), availableSupport: ["Wall"])
    var watch = CompanionState()
    let date = Date(timeIntervalSince1970: 100)
    run.start(at: 0)
    let ready = CompanionSnapshot(session: run, at: 0, sentAt: date)
    #expect(ready.exercise == nil)
    #expect(ready.configured?.exerciseID == "wallPushup")
    watch.receive(ready, now: date)
    #expect(watch.command(.startSet, now: date) != nil)
    #expect(watch.command(.endSet, now: date) == nil)
    run.beginSet(at: 1)
    watch.receive(.init(session: run, at: 1, sentAt: date.addingTimeInterval(1)), now: date.addingTimeInterval(1))
    #expect(watch.command(.endSet, now: date.addingTimeInterval(1)) == nil)
    run.setReps(4)
    watch.receive(.init(session: run, at: 2, sentAt: date.addingTimeInterval(2)), now: date.addingTimeInterval(2))
    #expect(watch.command(.endSet, now: date.addingTimeInterval(2)) != nil)
    run.endSet(at: 3); run.feedback(reserve: nil, reason: .discomfort)
    watch.receive(.init(session: run, at: 3, sentAt: date.addingTimeInterval(3)), now: date.addingTimeInterval(3))
    #expect(watch.command(.nextSet, now: date.addingTimeInterval(3)) == nil)
    #expect(watch.command(.finish, now: date.addingTimeInterval(3)) != nil)
    let data = try JSONEncoder().encode(ready)
    #expect(try JSONDecoder().decode(CompanionSnapshot.self, from: data).configured?.exerciseID == "wallPushup")
}

@Test func discomfortBeforeAnyCompletedSetStopsWithoutCreatingWorkOrRest() throws {
    var run = try ConfigurableSession(plan: customPlan(), availableSupport: ["Wall"])
    run.start(at: 0); run.beginSet(at: 1)
    run.stopForDiscomfort(at: 5)
    run.nextSet(at: 20)
    #expect(run.stoppedForDiscomfort)
    #expect(run.phase == .rest)
    #expect(run.record.setCount == 0)
    #expect(run.restElapsed(at: 20) == nil)
    run.finish(at: 25)
    #expect(run.phase == .finished)
    #expect(run.record.setCount == 0)
}

@Test(arguments: [true, false])
func explicitDiscomfortStopRetainsAnEnteredActualCountAndBlocksFurtherSets(useStopAction: Bool) throws {
    var run = try ConfigurableSession(plan: customPlan(), availableSupport: ["Wall"])
    run.start(at: 0); run.beginSet(at: 1); run.setReps(3)
    if useStopAction { run.stopForDiscomfort(at: 5) }
    else { run.endSet(at: 5, reason: .discomfort) }
    run.nextSet(at: 20)
    #expect(run.phase == .rest)
    #expect(run.stoppedForDiscomfort)
    #expect(run.record.loggedSets.first?.reps == 3)
    #expect(run.record.loggedSets.first?.reason == .discomfort)
}

@Test func configuredPlanRejectsOversizedCountsWithoutIntegerOverflow() throws {
    let plan = try customPlan("""
    {"exerciseID":"wallPushup","sets":\(Int.max),"target":8,"unit":"reps","restSeconds":30},
    {"exerciseID":"plank","sets":1,"target":20,"unit":"seconds","restSeconds":30}
    """)
    #expect(throws: ConfigurableSession.Invalid.self) {
        try ConfigurableSession(plan: plan, availableSupport: ["Wall"])
    }
}

@Test(arguments: [
    "{\"exerciseID\":\"unknown\",\"sets\":1,\"target\":8,\"unit\":\"reps\",\"restSeconds\":30}",
    "{\"exerciseID\":\"plank\",\"sets\":1,\"target\":8,\"unit\":\"reps\",\"restSeconds\":30}",
    "{\"exerciseID\":\"squat\",\"sets\":0,\"target\":8,\"unit\":\"reps\",\"restSeconds\":30}",
    "{\"exerciseID\":\"squat\",\"sets\":11,\"target\":8,\"unit\":\"reps\",\"restSeconds\":30}",
    "{\"exerciseID\":\"squat\",\"sets\":1,\"target\":201,\"unit\":\"reps\",\"restSeconds\":30}",
    "{\"exerciseID\":\"plank\",\"sets\":1,\"target\":601,\"unit\":\"seconds\",\"restSeconds\":30}",
    "{\"exerciseID\":\"squat\",\"sets\":1,\"target\":8,\"unit\":\"reps\",\"restSeconds\":-1}",
    "{\"exerciseID\":\"squat\",\"sets\":1,\"target\":8,\"unit\":\"reps\",\"restSeconds\":601}"
])
func configuredPlanRevalidatesSavedCatalogueAndBoundedQuantities(items: String) throws {
    let plan = try customPlan(items)
    #expect(throws: ConfigurableSession.Invalid.self) { try ConfigurableSession(plan: plan, availableSupport: ["Wall"]) }
}

@Test func configuredPlanRequiresCurrentSupportAndPreservesItsOriginalSelection() throws {
    let plan = try customPlan()
    #expect(throws: ConfigurableSession.Invalid.self) { try ConfigurableSession(plan: plan, availableSupport: []) }
    let run = try ConfigurableSession(plan: plan, availableSupport: ["Wall"])
    #expect(plan.items.map(\.exerciseID) == ["wallPushup", "plank"])
    #expect(run.steps.count == 3)
}

@Test(arguments: [0, -1, 201])
func configuredManualTargetsNeverFillMissingOrInvalidActualReps(reps: Int) throws {
    var run = try ConfigurableSession(plan: customPlan(), availableSupport: ["Wall"])
    run.start(at: 0); run.beginSet(at: 1); run.setReps(reps)
    let result = run.endSet(at: 30)
    #expect(!result)
    #expect(run.manualReps == nil)
    #expect(run.record.setCount == 0)
    #expect(run.phase == .active)
}

@Test func configuredHoldKeepsObservedTimePastItsTargetAndDoesNotCompleteItself() throws {
    var run = try ConfigurableSession(plan: customPlan("""
    {"exerciseID":"plank","sets":1,"target":20,"unit":"seconds","restSeconds":0}
    """), availableSupport: [])
    run.start(at: 0); run.beginSet(at: 10)
    #expect(run.elapsed(at: 30) == 20)
    #expect(run.record.setCount == 0)
    #expect(run.phase == .active)
    run.pause(at: 40); run.resume(at: 100); run.endSet(at: 800)
    #expect(run.record.loggedSets.first?.seconds == 730)
    #expect(run.record.loggedSets.first?.target == 20)
    #expect(run.record.loggedSets.first?.activeSeconds == 730)
}

@Test func finishDropsAnUnendedSetAndRepeatedFinishKeepsCompletedIdentities() throws {
    var run = try ConfigurableSession(plan: customPlan(), availableSupport: ["Wall"])
    run.start(at: 0); run.beginSet(at: 1); run.setReps(3); run.endSet(at: 5)
    let firstID = run.completed.first?.id
    run.nextSet(at: 10); run.beginSet(at: 20); run.setReps(8); run.finish(at: 30)
    let generation = run.generation
    run.finish(at: 40)
    #expect(run.generation == generation)
    #expect(run.completed.map(\.id) == [firstID])
    #expect(run.record.reps == 3)
    #expect(run.record.setCount == 1)
}

@Test func legacyManualSetWithoutExecutionMetadataStillDecodes() throws {
    let data = Data("""
    {"id":"00000000-0000-0000-0000-000000000001","exerciseID":"squat","reps":12,
    "seconds":0,"source":"manual","reason":"voluntary"}
    """.utf8)
    let set = try JSONDecoder().decode(LoggedSet.self, from: data)
    #expect(set.number == nil)
    #expect(set.activeSeconds == nil)
    #expect(set.restSecondsBefore == nil)
    #expect(set.quantityOrigin == nil)
    #expect(set.reps == 12)
}

@Test func configuredWatchKeepsPausedAndEndedHoldTimesInsteadOfShowingZeroDuringRest() throws {
    var run = try ConfigurableSession(plan: customPlan("""
    {"exerciseID":"plank","sets":1,"target":20,"unit":"seconds","restSeconds":45}
    """), availableSupport: [])
    run.start(at: 0); run.beginSet(at: 1); run.pause(at: 11)
    #expect(CompanionSnapshot(session: run, at: 100).configured?.activeSeconds == 10)
    run.resume(at: 101); run.endSet(at: 106)
    let resting = CompanionSnapshot(session: run, at: 110)
    #expect(resting.configured?.activeSeconds == 15)
    #expect(resting.configured?.restElapsed == 4)
    #expect(resting.configured?.unit == .seconds)
}

@Test(arguments: ["activeSeconds", "restElapsed"])
func configuredWatchRejectsUnrenderableOrNegativeClockValues(field: String) throws {
    var run = try ConfigurableSession(plan: customPlan(), availableSupport: ["Wall"])
    run.start(at: 0)
    let now = Date()
    let snapshot = CompanionSnapshot(session: run, at: 1, sentAt: now)
    for invalid in [-1.0, 1e100] {
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        var configured = try #require(json["configured"] as? [String: Any])
        configured[field] = invalid
        json["configured"] = configured
        let decoded = try JSONDecoder().decode(CompanionSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.isFresh(at: now) == false)
    }
}

@Test(arguments: ["squat", "pushup"])
func configuredCameraCountsObservedCyclesAndNeverEndsAtItsTarget(exerciseID: String) throws {
    var run = try ConfigurableSession(plan: customPlan("""
    {"exerciseID":"\(exerciseID)","sets":1,"target":1,"unit":"reps","restSeconds":30}
    """), availableSupport: [])
    run.start(at: 0)
    let mutationResult1 = run.resetSet(source: .camera, at: 0)
    #expect(mutationResult1)
    let preparing = run.generation
    configuredCycle(&run, from: 0, generation: preparing)
    #expect(run.actualReps == 0)
    run.beginSet(at: 10)
    configuredCycle(&run, from: 0)
    configuredCycle(&run, from: 2)
    #expect(run.actualReps == 2)
    #expect(run.phase == .active)
    #expect(run.record.setCount == 0)
    let mutationResult2 = run.endSet(at: 15)
    #expect(mutationResult2)
    let saved = try #require(run.completed.first)
    #expect(saved.source == .camera)
    #expect(saved.quantityOrigin == nil)
    #expect(saved.reps == 2)
    #expect(saved.repDurations?.count == 2)
    #expect(WorkoutReport(record: run.record).timedRepCount == 2)
}

@Test func configuredMixedCameraManualAndHoldSaveInQueueOrderWithOriginalRest() throws {
    var run = try ConfigurableSession(plan: customPlan("""
    {"exerciseID":"squat","sets":1,"target":1,"unit":"reps","restSeconds":30},
    {"exerciseID":"deadBug","sets":1,"target":8,"unit":"reps","restSeconds":30},
    {"exerciseID":"plank","sets":1,"target":20,"unit":"seconds","restSeconds":30}
    """), availableSupport: [])
    run.start(at: 0); run.resetSet(source: .camera, at: 0); run.beginSet(at: 10)
    configuredCycle(&run, from: 0)
    run.endSet(at: 15); run.nextSet(at: 20)
    #expect(run.source == .manual)
    let mutationResult3 = run.resetSet(source: .camera, at: 20)
    #expect(mutationResult3)
    run.switchInput(source: .manual, at: 20)
    run.beginSet(at: 25); run.setReps(4); run.endSet(at: 30); run.nextSet(at: 35)
    let mutationResult4 = run.resetSet(source: .camera, at: 35)
    #expect(mutationResult4)
    run.switchInput(source: .manual, at: 35)
    run.beginSet(at: 40); run.pause(at: 45); run.resume(at: 50); run.endSet(at: 55); run.finish(at: 56)
    let reopened = try JSONDecoder().decode(SessionRecord.self, from: JSONEncoder().encode(run.record))
    let report = WorkoutReport(record: reopened)
    #expect(report.sets.map(\.exerciseID) == ["squat", "deadBug", "plank"])
    #expect(report.sets.map(\.source) == [.camera, .manual, .manual])
    #expect(report.sets.map(\.restSecondsBefore) == [nil, 10, 10])
    #expect(report.sets.map(\.activeSeconds) == [5, 5, 10])
    #expect(report.sets.map { $0.repDurations.count } == [1, 0, 0])
    #expect(report.sets.last?.holdSeconds == 10)
}

@Test func configuredCameraPauseAndConfirmedModeResetRejectOldCyclesAndKeepCompletedSets() throws {
    var run = try ConfigurableSession(plan: customPlan("""
    {"exerciseID":"squat","sets":2,"target":2,"unit":"reps","restSeconds":30}
    """), availableSupport: [])
    run.start(at: 0); run.resetSet(source: .camera, at: 0); run.beginSet(at: 1)
    configuredCycle(&run, from: 0)
    let active = run.generation
    run.pause(at: 4)
    configuredCycle(&run, from: 2, generation: active)
    #expect(run.actualReps == 1)
    run.resume(at: 10)
    configuredCycle(&run, from: 4, generation: active)
    #expect(run.actualReps == 1)
    run.endSet(at: 12); run.nextSet(at: 15); run.resetSet(source: .camera, at: 15); run.beginSet(at: 20)
    configuredCycle(&run, from: 0)
    let discarded = run.generation
    let mutationResult5 = run.resetSet(source: .manual, at: 25)
    #expect(mutationResult5)
    #expect(!run.hasStarted)
    #expect(run.actualReps == nil)
    #expect(run.elapsed(at: 30) == 0)
    configuredCycle(&run, from: 2, generation: discarded)
    run.beginSet(at: 35); run.setReps(3); run.endSet(at: 40)
    #expect(run.completed.map(\.reps) == [1, 3])
    #expect(run.completed.map(\.source) == [.camera, .manual])
    #expect(run.completed.last?.activeSeconds == 5)
    #expect(run.completed.last?.restSecondsBefore == 8)
    #expect(run.completed.last?.repDurations == nil)
}

private func configuredCycle(_ run: inout ConfigurableSession, from offset: Double, generation: UUID? = nil) {
    let generation = generation ?? run.generation
    for (time, angle) in [(0.0, 170.0), (0.2, 170), (0.6, 130), (1.0, 90), (1.2, 90), (1.8, 170), (2.0, 170)] {
        run.consume(.init(time: offset + time, angle: angle), generation: generation)
    }
}

@Test func configuredWatchShowsObservedCameraCountWithoutClaimingManualEntry() throws {
    var run = try ConfigurableSession(plan: customPlan("""
    {"exerciseID":"squat","sets":1,"target":2,"unit":"reps","restSeconds":30}
    """), availableSupport: [])
    run.start(at: 0); run.resetSet(source: .camera, at: 0); run.beginSet(at: 1)
    configuredCycle(&run, from: 0)
    let now = Date()
    let snapshot = CompanionSnapshot(session: run, at: 4, sentAt: now)
    #expect(snapshot.reps == 1)
    #expect(snapshot.configured?.source == .camera)
    #expect(snapshot.configured?.enteredReps == nil)
    #expect(snapshot.configured?.canEndSet == true)
    run.consume(.init(time: 2.2, angle: 170, bodyAngle: 160), generation: run.generation)
    let alignment = CompanionSnapshot(session: run, at: 4, sentAt: now)
    #expect(alignment.cue == .alignment)
    #expect(alignment.reps == 1)
    let decoded = try JSONDecoder().decode(CompanionSnapshot.self, from: JSONEncoder().encode(snapshot))
    #expect(decoded.isFresh(at: now))
    #expect(decoded.configured?.source == .camera)
    var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
    var configured = try #require(json["configured"] as? [String: Any])
    configured.removeValue(forKey: "source"); json["configured"] = configured
    let legacy = try JSONDecoder().decode(CompanionSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(legacy.configured?.source == nil)
}

@Test(arguments: ["catCow", "plank"])
func configuredWatchRejectsUnsupportedCameraSourceClaims(exerciseID: String) throws {
    let unit = exerciseID == "plank" ? "seconds" : "reps"
    var run = try ConfigurableSession(plan: customPlan("""
    {"exerciseID":"\(exerciseID)","sets":1,"target":8,"unit":"\(unit)","restSeconds":30}
    """), availableSupport: ["Wall"])
    run.start(at: 0)
    let now = Date()
    let snapshot = CompanionSnapshot(session: run, at: 0, sentAt: now)
    var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
    var configured = try #require(json["configured"] as? [String: Any])
    configured["source"] = "camera"; configured.removeValue(forKey: "measuredSeconds"); json["configured"] = configured
    let decoded = try JSONDecoder().decode(CompanionSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(!decoded.isFresh(at: now))
}

@Test func configuredZeroCameraObservationsCannotBeSavedAsACompletedSet() throws {
    var run = try ConfigurableSession(plan: customPlan("""
    {"exerciseID":"squat","sets":2,"target":8,"unit":"reps","restSeconds":30}
    """), availableSupport: [])
    run.start(at: 0); run.resetSet(source: .camera, at: 0); run.beginSet(at: 1)
    #expect(run.actualReps == 0)
    #expect(!run.canEndSet(at: 5))
    let ended = run.endSet(at: 5)
    #expect(!ended)
    #expect(run.completed.isEmpty)
    #expect(run.record.setCount == 0)
    #expect(run.phase == .active)
}

@Test func explicitSkipPersistsIntentWithoutCompletedWorkOrInferredZeroExercise() throws {
    var run = try ConfigurableSession(plan: customPlan(), availableSupport: ["Wall"])
    run.start(at: 0); run.beginSet(at: 1)
    let before = run.generation
    let mutationCheck1 = run.skipSet(at: 5)
    #expect(mutationCheck1)
    #expect(run.generation != before)
    #expect(run.currentWasSkipped)
    #expect(run.phase == .rest)
    #expect(run.completed.isEmpty)
    #expect(run.record.setCount == 0 && run.record.reps == 0 && run.record.activeSeconds == 0)
    #expect(run.skippedSets.count == 1)
    #expect(run.skippedSets.first?.exerciseID == "wallPushup")
    #expect(run.skippedSets.first?.number == 1)
    #expect(run.skippedSets.first?.target == 8)
    #expect(run.skippedSets.first?.unit == .reps)
    #expect(run.skippedSets.first?.source == .manual)
    #expect(run.skippedSets.first?.reason == .userChoice)
    let mutationCheck2 = run.skipSet(at: 6)
    #expect(!mutationCheck2)
    #expect(!run.canReduceRemainingRepTargets)
    run.finish(at: 7)
    let reopened = try JSONDecoder().decode(SessionRecord.self, from: JSONEncoder().encode(run.record))
    #expect(reopened == run.record)
    #expect(reopened.skippedSets.count == 1)
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let history = HistoryStore(url: folder.appendingPathComponent("history.json"))
    try history.save(reopened)
    let destination = folder.appendingPathComponent("export.json")
    try history.export(to: destination)
    let exported = try JSONDecoder().decode([SessionRecord].self, from: Data(contentsOf: destination))
    #expect(exported.first?.skippedSets == reopened.skippedSets)
    #expect(exported.first?.setCount == 0)
    #expect(WorkoutReport(record: reopened).setCount == 0)
    #expect(SkillProgress.evaluate(history: [reopened]).points(for: .strength) == 0)
    let legacy = Data("{\"id\":\"00000000-0000-0000-0000-000000000001\",\"date\":0,\"sets\":[]}".utf8)
    #expect(try JSONDecoder().decode(SessionRecord.self, from: legacy).skippedSets.isEmpty)
}

@Test func skipCannotDiscardEnteredWorkAndPreservesTheActualRestBetweenCompletedSets() throws {
    var run = try ConfigurableSession(plan: customPlan("""
    {"exerciseID":"squat","sets":3,"target":8,"unit":"reps","restSeconds":30}
    """), availableSupport: [])
    run.start(at: 0); run.beginSet(at: 1); run.setReps(2)
    let mutationCheck3 = run.skipSet(at: 5)
    #expect(!mutationCheck3)
    let mutationCheck4 = run.endSet(at: 5)
    #expect(mutationCheck4)
    run.nextSet(at: 10)
    let mutationCheck5 = run.skipSet(at: 15)
    #expect(mutationCheck5)
    run.nextSet(at: 20); run.beginSet(at: 30); run.setReps(1); run.endSet(at: 35)
    #expect(run.completed.map(\.number) == [1, 3])
    #expect(run.completed.last?.restSecondsBefore == 25)
    #expect(run.skippedSets.map(\.number) == [2])
    #expect(run.record.setCount == 2)
}

@Test func oneRecordedRepOnlyChangesRemainingSameExerciseTargetsAfterExplicitApproval() throws {
    let plan = try customPlan()
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    let original = try encoder.encode(plan)
    var run = try ConfigurableSession(plan: plan, availableSupport: ["Wall"])
    run.start(at: 0); run.beginSet(at: 1); run.setReps(1); run.endSet(at: 5)
    #expect(run.canReduceRemainingRepTargets)
    #expect(run.steps.map(\.target) == [8, 8, 20])
    let ids = run.steps.map(\.id), generation = run.generation
    let mutationCheck6 = run.reduceRemainingRepTargetsToOne()
    #expect(mutationCheck6)
    #expect(run.steps.map(\.target) == [8, 1, 20])
    #expect(run.steps.map(\.id) == ids)
    #expect(run.generation != generation)
    #expect(!run.canReduceRemainingRepTargets)
    let mutationCheck7 = run.reduceRemainingRepTargetsToOne()
    #expect(!mutationCheck7)
    #expect(run.phase == .rest && run.index == 0 && run.completed.count == 1)
    #expect(run.completed.first?.reps == 1 && run.completed.first?.target == 8)
    #expect(try encoder.encode(plan) == original)
    run.nextSet(at: 10)
    #expect(!run.hasStarted && run.actualReps == nil)
    #expect(run.steps.count == 3)
}

@Test func discomfortNeverOffersOrAppliesOneRepContinuation() throws {
    var run = try ConfigurableSession(plan: customPlan(), availableSupport: ["Wall"])
    run.start(at: 0); run.beginSet(at: 1); run.setReps(1); run.endSet(at: 5, reason: .discomfort)
    #expect(!run.canReduceRemainingRepTargets)
    let mutationCheck8 = run.reduceRemainingRepTargetsToOne()
    #expect(!mutationCheck8)
    let mutationCheck9 = run.skipSet(at: 7)
    #expect(!mutationCheck9)
    #expect(run.steps.map(\.target) == [8, 8, 20])
}

@Test func restAfterAStartedSkippedAttemptBeginsAtTheExplicitSkipRatherThanInventingContinuousRest() throws {
    var run = try ConfigurableSession(plan: customPlan("""
    {"exerciseID":"squat","sets":3,"target":8,"unit":"reps","restSeconds":30}
    """), availableSupport: [])
    run.start(at: 0); run.beginSet(at: 1); run.setReps(2); run.endSet(at: 5)
    run.nextSet(at: 8); run.beginSet(at: 10)
    let skipped = run.skipSet(at: 15)
    #expect(skipped)
    run.nextSet(at: 20); run.beginSet(at: 30); run.setReps(1); run.endSet(at: 35)
    #expect(run.completed.last?.restSecondsBefore == 15)
    #expect(run.record.activeSeconds == 9)
}

@Test func cameraHoldSavesOnlyAdjacentObservedSecondsAndNeverElapsedLoss() throws {
    var run = try ConfigurableSession(plan: customPlan("""
    {"exerciseID":"plank","sets":1,"target":20,"unit":"seconds","restSeconds":30}
    """), availableSupport: [])
    run.start(at: 0); run.resetSet(source: .camera, at: 0); run.beginSet(at: 0)
    #expect(!run.canEndSet(at: 30))
    let generation = run.generation
    for i in 0...6 {
        run.consume(.init(time: Double(i) * 0.2, angle: 170, confidence: 1, provenance: .posture, holdQualification: .staticHold), generation: generation)
    }
    run.consume(.init(time: 1.3, angle: .nan, confidence: 0), generation: generation)
    run.consume(.init(time: 20, angle: 170, confidence: 1, provenance: .posture, holdQualification: .staticHold), generation: generation)
    let endedHold = run.endSet(at: 30)
    #expect(endedHold)
    #expect(abs((run.completed.first?.seconds ?? 0) - 1.2) < 0.00001)
    #expect(run.completed.first?.activeSeconds == 30)
    #expect(run.completed.first?.reps == 0)
    #expect(run.completed.first?.repDurations == nil)
}

@Test func fractionalCameraManualPauseBoundariesPreserveQuantityAndHonestOrigin() throws {
    var run = try ConfigurableSession(plan: customPlan("""
    {"exerciseID":"plank","sets":1,"target":20,"unit":"seconds","restSeconds":30}
    """), availableSupport: [])
    run.start(at: 0); run.resetSet(source: .camera, at: 0); run.beginSet(at: 0)
    for time in [0.0, 0.2, 0.4] { run.consume(.init(time: time, angle: 170, confidence: 1, provenance: .posture, holdQualification: .staticHold), generation: run.generation) }
    run.switchInput(source: .manual, at: 10)
    run.pause(at: 10.35); run.resume(at: 20)
    run.switchInput(source: .camera, at: 20.35)
    for time in [30.0, 30.2, 30.4] { run.consume(.init(time: time, angle: 170, confidence: 1, provenance: .posture, holdQualification: .staticHold), generation: run.generation) }
    let ended = run.endSet(at: 40)
    #expect(ended)
    #expect(abs((run.completed.first?.seconds ?? 0) - 1.5) < 0.00001)
    #expect(run.completed.first?.source == .manual)
    #expect(run.completed.first?.quantityOrigin?.rawValue == "mixed")
    let restored = try JSONDecoder().decode(SessionRecord.self, from: JSONEncoder().encode(run.record))
    #expect(WorkoutReport(record: restored).sets.first?.sourceLabel == "Camera + manual")
}

@Test func watchCameraSecondsAreObservedWhileActiveTimeAndControlRemainSeparate() throws {
    var run = try ConfigurableSession(plan: customPlan("""
    {"exerciseID":"plank","sets":1,"target":20,"unit":"seconds","restSeconds":30}
    """), availableSupport: [])
    run.start(at: 0); run.resetSet(source: .camera, at: 0); run.beginSet(at: 0)
    for i in 0...6 { run.consume(.init(time: Double(i) * 0.2, angle: 170, confidence: 1, provenance: .posture, holdQualification: .staticHold), generation: run.generation) }
    let now = Date()
    let snapshot = CompanionSnapshot(session: run, at: 30, sentAt: now)
    #expect(snapshot.isFresh(at: now))
    var state = CompanionState(); state.receive(snapshot, now: now)
    #expect(state.command(.endSet, now: now) != nil)
    #expect(state.command(.pause, now: now) != nil)
    let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
    let payload = try #require(json["configured"] as? [String: Any])
    #expect(abs((payload["measuredSeconds"] as? Double ?? -1) - 1.2) < 0.00001)
    #expect(payload["activeSeconds"] as? Double == 30)
}

@Test func cameraOnlyWorkKeepsOriginAfterInputSwitchAndPreservesLargeCounts() throws {
    var run = try ConfigurableSession(plan: customPlan("""
    {"exerciseID":"squat","sets":1,"target":8,"unit":"reps","restSeconds":30}
    """), availableSupport: [])
    run.start(at: 0); run.resetSet(source: .camera, at: 0); run.beginSet(at: 0)
    for i in 0..<205 { configuredCycle(&run, from: Double(i)*2) }
    #expect(run.actualReps == 205)
    run.switchInput(source: .manual, at: 411); run.setReps(205)
    #expect(run.actualReps == 205)
    let ended = run.endSet(at: 412)
    #expect(ended)
    #expect(run.completed.first?.source == .camera)
    #expect(run.completed.first?.quantityOrigin == nil)
}

@Test func watchTimedPayloadRejectsCorruptQuantityAndRetainsOldManualTimer() throws {
    var run = try ConfigurableSession(plan: customPlan("""
    {"exerciseID":"plank","sets":1,"target":20,"unit":"seconds","restSeconds":30}
    """), availableSupport: [])
    run.start(at: 0); run.beginSet(at: 0)
    let now = Date()
    let original = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(CompanionSnapshot(session: run, at: 30, sentAt: now))) as? [String: Any])
    for corrupt in [-1.0, 31, 86401] {
        var json = original
        var payload = try #require(json["configured"] as? [String: Any])
        payload["measuredSeconds"] = corrupt; json["configured"] = payload
        let value = try JSONDecoder().decode(CompanionSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(!value.isFresh(at: now))
    }
    var old = original
    var payload = try #require(old["configured"] as? [String: Any]); payload.removeValue(forKey: "measuredSeconds"); old["configured"] = payload
    let legacy = try JSONDecoder().decode(CompanionSnapshot.self, from: JSONSerialization.data(withJSONObject: old))
    #expect(legacy.isFresh(at: now))
    #expect(legacy.configured?.displaySeconds == 30)
}

@Test func watchCannotOfferEndForUnobservedTimedCameraQuantity() throws {
    var run = try ConfigurableSession(plan: customPlan("""
    {"exerciseID":"plank","sets":1,"target":20,"unit":"seconds","restSeconds":30}
    """), availableSupport: [])
    run.start(at: 0); run.resetSet(source: .camera, at: 0); run.beginSet(at: 0)
    let now = Date()
    var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(CompanionSnapshot(session: run, at: 30, sentAt: now))) as? [String: Any])
    var payload = try #require(json["configured"] as? [String: Any]); payload["canEndSet"] = true; json["configured"] = payload
    let corrupt = try JSONDecoder().decode(CompanionSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(!corrupt.isFresh(at: now))
}

@Test func timedQuantityLabelFollowsEarnedOriginAcrossInputChanges() throws {
    let plan = try customPlan("""
    {"exerciseID":"plank","sets":1,"target":1,"unit":"seconds","restSeconds":30}
    """)
    var manual = try ConfigurableSession(plan: plan, availableSupport: [])
    manual.start(at: 0); manual.beginSet(at: 0)
    manual.switchInput(source: .camera, at: 2)
    #expect(manual.measuredSeconds(at: 2) == 2)
    #expect(manual.quantitySourcePresentation(at: 2).title == "Manual hold, active timer")
    #expect(manual.quantitySourcePresentation(at: 2).symbol == "hand.tap")
    manual.consume(.init(time: 2, angle: 170, confidence: 1, provenance: .posture, holdQualification: .staticHold), generation: manual.generation)
    #expect(manual.quantitySourcePresentation(at: 2).title == "Manual hold, active timer")
    manual.consume(.init(time: 2.2, angle: 170, confidence: 1, provenance: .posture, holdQualification: .staticHold), generation: manual.generation)
    #expect(manual.quantitySourcePresentation(at: 2.2).title == "Camera + manual quantity")

    var camera = try ConfigurableSession(plan: plan, availableSupport: [])
    camera.start(at: 0); camera.resetSet(source: .camera, at: 0); camera.beginSet(at: 0)
    for time in [0.0, 0.2, 0.4] { camera.consume(.init(time: time, angle: 170, confidence: 1, provenance: .posture, holdQualification: .staticHold), generation: camera.generation) }
    camera.switchInput(source: .manual, at: 1)
    #expect(camera.quantityOrigin(at: 1) == .cameraObserved)
    #expect(camera.quantitySourcePresentation(at: 1).title == "Camera observation")
    #expect(camera.quantitySourcePresentation(at: 1).symbol == "camera")
    #expect(camera.quantitySourcePresentation(at: 1.1).title == "Camera + manual quantity")
    #expect(abs(camera.measuredSeconds(at: 1.1) - 0.5) < 0.00001)
}

@Test func configuredAmbiguityPreservesQuantityAcrossPauseAndManualFallbackWithoutBypassingRecovery() throws {
    for id in ["squat", "plank"] {
        let timed = id == "plank"
        let plan = try CoachSavedPlan.catalogue(exerciseID:id,sets:1,target:10,restSeconds:0)
        var run = try ConfigurableSession(plan:plan,availableSupport:[])
        run.start(at:0); let reset = run.resetSet(source:.camera,at:0); #expect(reset); run.beginSet(at:0)
        let token = run.generation
        run.consume(.init(time:0,angle:90,holdQualification:.staticHold),generation:token)
        run.consume(.init(time:0.1,angle:90,holdQualification:.staticHold),generation:token)
        let earned = run.measuredSeconds(at:0.1)
        run.consume(.init(time:0.2,angle:.nan,confidence:0,observation:.multiplePeople),generation:token)
        #expect(run.cameraRecoveryState == .needsResume)
        #expect(run.phase == .active)
        run.pause(at:1)
        #expect(run.cameraRecoveryState == .needsResume)
        run.resume(at:2)
        #expect(run.cameraRecoveryState == .waitingForClear)
        run.consume(.init(time:3,angle:.nan,confidence:0,observation:.multiplePeople),generation:token)
        #expect(run.cameraRecoveryState == .waitingForClear)
        let manual = run.switchInput(source:.manual,at:3); #expect(manual)
        #expect(run.cameraRecoveryState == .ready)
        if !timed { run.setReps(4) }
        let camera = run.switchInput(source:.camera,at:4); #expect(camera)
        #expect(run.cameraRecoveryState != .ready)
        if !timed { #expect(run.actualReps == 4) }
        else { #expect(run.holdCounter?.observedSeconds == earned) }
    }
}

@Test func configuredManualPauseResumeCannotAcknowledgeCameraIdentityRecovery() throws {
    for id in ["squat", "plank"] {
        let timed = id == "plank"
        var run = try ConfigurableSession(plan: CoachSavedPlan.catalogue(exerciseID: id, sets: 1, target: 10, restSeconds: 0), availableSupport: [])
        run.start(at: 0); _ = run.resetSet(source: .camera, at: 0); run.beginSet(at: 0)
        for time in [0.0, 0.1, 0.2] {
            run.consume(.init(time: time, angle: 170, holdQualification: .staticHold), generation: run.generation)
        }
        run.consume(.init(time: 0.3, angle: .nan, confidence: 0, observation: .multiplePeople), generation: run.generation)
        _ = run.switchInput(source: .manual, at: 1)
        if !timed { run.setReps(4) }
        run.pause(at: 2); run.resume(at: 5)
        #expect(run.elapsed(at: 6) == 3)
        if timed { #expect(abs(run.measuredSeconds(at: 6) - 2.2) < 0.00001) }
        _ = run.switchInput(source: .camera, at: 6)
        let saved = timed ? run.measuredSeconds(at: 6) : Double(run.actualReps ?? 0)
        #expect(run.cameraRecoveryState == .needsResume)
        for time in stride(from: 6.0, through: 9.0, by: 0.1) {
            run.consume(.init(time: time, angle: 170, holdQualification: .staticHold), generation: run.generation)
        }
        for (time, angle) in [(9.2,90.0),(9.4,90),(9.8,170),(10.0,170)] {
            run.consume(.init(time: time, angle: angle, holdQualification: .staticHold), generation: run.generation)
        }
        #expect(run.cameraRecoveryState == .needsResume)
        #expect((timed ? run.measuredSeconds(at: 10) : Double(run.actualReps ?? 0)) == saved)
        run.resume(at: 11)
        #expect(run.cameraRecoveryState == .waitingForClear)
        for time in stride(from: 11.0, through: 13.3, by: 0.1) {
            run.consume(.init(time: time, angle: 170, holdQualification: .staticHold), generation: run.generation)
        }
        #expect(run.cameraRecoveryState == .ready)
        for (time, angle) in [(13.5,90.0),(13.7,90),(14.1,170),(14.3,170)] {
            run.consume(.init(time: time, angle: angle, holdQualification: .staticHold), generation: run.generation)
        }
        #expect((timed ? run.measuredSeconds(at: 14.3) : Double(run.actualReps ?? 0)) > saved)
    }
}

@Test func configuredProgressNamesExerciseAndSetWithoutRepeatingSingleExerciseTotals() throws {
    var single = try ConfigurableSession(plan: CoachSavedPlan.catalogue(exerciseID: "squat", sets: 3, target: 8, restSeconds: 30), availableSupport: [])
    #expect(single.progressDescription == "Set 1 of 3")
    single.start(at: 0); single.beginSet(at: 0); single.setReps(1); single.endSet(at: 1); single.nextSet(at: 2)
    #expect(single.progressDescription == "Set 2 of 3")
    var multiple = try ConfigurableSession(plan: customPlan(), availableSupport: ["Wall"])
    #expect(multiple.progressDescription == "Exercise 1 of 2. Set 1 of 2.")
    multiple.start(at: 0); multiple.beginSet(at: 0); multiple.setReps(1); multiple.endSet(at: 1); multiple.nextSet(at: 2)
    #expect(multiple.progressDescription == "Exercise 1 of 2. Set 2 of 2.")
    multiple.beginSet(at: 2); multiple.setReps(1); multiple.endSet(at: 3); multiple.nextSet(at: 4)
    #expect(multiple.progressDescription == "Exercise 2 of 2. Set 1 of 1.")
}

@Test func plannedSessionRecordsOptionalEffortWithoutChangingQuantityOrDiscomfortAndReadsLegacyRecords() throws {
    #expect(SetEffort.allCases.map(\.rawValue) == [2, 4, 6, 8, 10])
    let plan = try CoachSavedPlan.catalogue(exerciseID: "singleLegBalance", sets: 1, target: 20, restSeconds: 30)
    var run = try ConfigurableSession(plan: plan, availableSupport: [], plannedWorkoutID: "programme:2026-11-02")
    run.start(at: 0)
    run.beginSet(at: 1)
    let saved = run.endSet(at: 5)
    #expect(saved)
    run.feedback(reserve: nil, reason: .discomfort, effort: .veryHard)
    #expect(run.record.loggedSets.first?.effort == .veryHard)
    #expect(run.record.loggedSets.first?.seconds == 4)
    run.feedback(reserve: nil, reason: .target, effort: nil)
    #expect(run.record.loggedSets.first?.effort == nil)
    #expect(run.record.loggedSets.first?.reason == .discomfort)
    #expect(run.record.plannedWorkoutID == "programme:2026-11-02")
    #expect(try JSONDecoder().decode(SessionRecord.self, from: JSONEncoder().encode(run.record)) == run.record)
    let old = try JSONDecoder().decode(SessionRecord.self, from: Data(#"{"id":"00000000-0000-0000-0000-000000000001","date":0,"sets":[],"loggedSets":[{"id":"00000000-0000-0000-0000-000000000002","exerciseID":"squat","reps":4,"seconds":0,"source":"manual","reason":"voluntary"}]}"#.utf8))
    #expect(old.plannedWorkoutID == nil)
    #expect(old.loggedSets[0].effort == nil)
}

@Test func plannedSessionSupportRulesStillRequireActualWallChairAndCounter() throws {
    for id in ["wallPushup", "sitToStand", "inclinePushup"] {
        let entry = try #require(ExerciseCatalog.find(id))
        #expect(throws: Error.self) { try CoachSavedPlan.catalogue(exerciseID: id, sets: 1, target: 5, restSeconds: 30) }
        _ = try CoachSavedPlan.catalogue(exerciseID: id, sets: 1, target: 5, restSeconds: 30, availableSupport: [entry.support!])
    }
}

@Test func plannedSessionTelemetryImportPreservesProgrammeAndEffortEvidence() throws {
    let start = Date(timeIntervalSince1970: 1793577600)
    let end = start.addingTimeInterval(60)
    let set = LoggedSet(id: UUID(), exerciseID: "squat", reps: 7, seconds: 0, source: .manual, reason: .target, effort: .moderate)
    let record = SessionRecord(id: UUID(), date: start, sets: [], loggedSets: [set], endedAt: end, plannedWorkoutID: "programme:Europe/London:2026-11-02")
    let sample = WatchTelemetry(sessionID: record.id, sentAt: end, heartRate: .init(value: 100, date: end), accelerationG: nil, rotationRadiansPerSecond: nil)
    let merged = try WatchTelemetryImporter.merge([sample], into: record, through: end)
    #expect(merged.plannedWorkoutID == record.plannedWorkoutID)
    #expect(merged.loggedSets == record.loggedSets)
    #expect(merged.endedAt == record.endedAt)
}

@Test func plannedSessionLegacyFeedbackKeepsAnExistingEffortChoice() throws {
    var run = try ConfigurableSession(plan: customPlan(), availableSupport: ["Wall"])
    run.start(at: 0)
    run.beginSet(at: 0)
    run.setReps(4)
    let saved = run.endSet(at: 10)
    #expect(saved)
    run.feedback(reserve: nil, reason: .target, effort: .hard)
    run.feedback(reserve: 1, reason: .voluntary)
    #expect(run.record.loggedSets.last?.effort == .hard)
}

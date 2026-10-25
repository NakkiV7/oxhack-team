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
    {"exerciseID":"wallPushup","sets":1,"target":8,"unit":"reps","restSeconds":30},
    {"exerciseID":"plank","sets":1,"target":20,"unit":"seconds","restSeconds":30}
    """), availableSupport: ["Wall"])
    run.start(at: 0); run.resetSet(source: .camera, at: 0); run.beginSet(at: 10)
    configuredCycle(&run, from: 0)
    run.endSet(at: 15); run.nextSet(at: 20)
    #expect(run.source == .manual)
    let mutationResult3 = run.resetSet(source: .camera, at: 20)
    #expect(!mutationResult3)
    run.beginSet(at: 25); run.setReps(4); run.endSet(at: 30); run.nextSet(at: 35)
    let mutationResult4 = run.resetSet(source: .camera, at: 35)
    #expect(!mutationResult4)
    run.beginSet(at: 40); run.pause(at: 45); run.resume(at: 50); run.endSet(at: 55); run.finish(at: 56)
    let reopened = try JSONDecoder().decode(SessionRecord.self, from: JSONEncoder().encode(run.record))
    let report = WorkoutReport(record: reopened)
    #expect(report.sets.map(\.exerciseID) == ["squat", "wallPushup", "plank"])
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

@Test(arguments: ["wallPushup", "plank"])
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
    configured["source"] = "camera"; json["configured"] = configured
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

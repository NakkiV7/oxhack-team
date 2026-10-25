import XCTest
import UIKit
@testable import Spottr

@MainActor
final class ConfiguredWorkoutFlowTests: XCTestCase {
    func testExplicitZeroWorkSkipSavesOnlySkipMetadataAfterFinish() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = TrainingStore(historyURL: folder.appendingPathComponent("history.json"))
        store.startPlan(try cameraPlan(), availableSupport: [])
        store.beginConfiguredSet()
        XCTAssertTrue(store.skipConfiguredSet())
        XCTAssertTrue(store.configured?.currentWasSkipped == true)
        XCTAssertTrue(store.configured?.completed.isEmpty == true)
        XCTAssertTrue(store.history.isEmpty)
        XCTAssertTrue(ConfiguredRecoveryView(store: store).continuationGuidance.contains("Nothing was added as a completed set"))
        store.finish(); store.save()
        XCTAssertEqual(store.history.count, 1)
        XCTAssertEqual(store.history.first?.setCount, 0)
        XCTAssertEqual(store.history.first?.skippedSets.count, 1)
        XCTAssertEqual(try HistoryStore(url: folder.appendingPathComponent("history.json")).load().first?.skippedSets.count, 1)
    }

    func testOneRepAdjustmentNeedsExplicitActionAndDoesNotChangeSavedPlan() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = TrainingStore(historyURL: folder.appendingPathComponent("history.json"))
        let plan = try CoachSavedPlan.catalogue(exerciseID: "squat", sets: 2, target: 2, restSeconds: 30)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(plan)
        store.startPlan(plan, availableSupport: [])
        store.beginConfiguredSet(); store.setConfiguredReps(1); store.endSet()
        XCTAssertEqual(store.configured?.steps.map(\.target), [2, 2])
        XCTAssertTrue(store.useOneRepForRemainingConfiguredSets())
        XCTAssertEqual(store.configured?.steps.map(\.target), [2, 1])
        XCTAssertEqual(try encoder.encode(plan), bytes)
        XCTAssertEqual(store.configured?.completed.first?.reps, 1)
        XCTAssertEqual(store.configured?.phase, .rest)
        XCTAssertTrue(store.history.isEmpty)
        store.next()
        XCTAssertFalse(store.configured?.hasStarted ?? true)
        XCTAssertNil(store.configured?.actualReps)
    }

    func testRecoveryGuidanceDistinguishesIntermediateRestFromFinalReview() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = TrainingStore(historyURL: folder.appendingPathComponent("history.json"))
        let plan = try JSONDecoder().decode(CoachSavedPlan.self, from: Data(#"{"items":[{"exerciseID":"squat","sets":2,"target":2,"unit":"reps","restSeconds":30}],"approvedAt":0,"rationale":"Offline guidance fixture"}"#.utf8))
        store.startPlan(plan, availableSupport: [])
        store.beginConfiguredSet(); store.setConfiguredReps(2); store.endSet()

        XCTAssertEqual(ConfiguredRecoveryView(store: store).continuationGuidance,
                       "The next set starts only when you choose Start. Rest timing never starts a set automatically.")
        store.next()
        store.beginConfiguredSet(); store.setConfiguredReps(1); store.endSet()

        XCTAssertEqual(ConfiguredRecoveryView(store: store).continuationGuidance,
                       "All planned sets are ended. Review your session to save the work you completed.")
        XCTAssertTrue(store.history.isEmpty)
        store.next()
        XCTAssertEqual(store.configured?.phase, .finished)
        XCTAssertEqual(store.history.first?.setCount, 2)
    }

    func testSavedPlanStartsReadyAndOnlyCompletedWorkIsSavedOnceOnFinish() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("history.json")
        let store = TrainingStore(historyURL: url)
        let plan = try JSONDecoder().decode(CoachSavedPlan.self, from: Data("""
        {"items":[{"exerciseID":"wallPushup","sets":2,"target":8,"unit":"reps","restSeconds":30},
        {"exerciseID":"plank","sets":1,"target":20,"unit":"seconds","restSeconds":45}],
        "approvedAt":0,"rationale":"Offline test fixture"}
        """.utf8))

        store.startPlan(plan, availableSupport: ["Wall"])
        XCTAssertTrue(store.presented)
        XCTAssertEqual(store.configured?.current.exerciseID, "wallPushup")
        XCTAssertFalse(store.configured?.hasStarted ?? true)
        store.endSet()
        XCTAssertEqual(store.configured?.phase, .active)
        store.beginConfiguredSet()
        store.setConfiguredReps(4)
        store.endSet()
        XCTAssertTrue(store.history.isEmpty)
        XCTAssertEqual(store.configured?.completed.first?.reps, 4)
        store.feedback(reserve: nil, reason: .discomfort)
        store.next()
        XCTAssertEqual(store.configured?.phase, .rest)
        store.finish()
        XCTAssertEqual(store.history.count, 1)
        XCTAssertEqual(store.history.first?.setCount, 1)
        XCTAssertEqual(store.history.first?.loggedSets.first?.reason, .discomfort)
        store.save()
        XCTAssertEqual(store.history.count, 1)
        XCTAssertEqual(TrainingStore(historyURL: url).history, store.history)
    }
}

extension ConfiguredWorkoutFlowTests {
    func testCatalogueWorkoutStartsLocallyAndSavesActualWorkWithoutReplacingCoachPlan() throws {
        let suiteName = "CatalogueWorkout-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let savedCoachData = try JSONEncoder().encode(cameraPlan(exerciseID: "pushup"))
        defaults.set(savedCoachData, forKey: "coach.approvedPlan")
        var providerRequests = 0
        let coach = CoachModel(configuration: {
            providerRequests += 1
            throw CoachGatewayError.configuration
        }, savedPlanData: savedCoachData, defaults: defaults)
        let store = TrainingStore(historyURL: cameraHistoryURL())
        let plan = try CoachSavedPlan.catalogue(exerciseID: "squat", sets: 2, target: 12, restSeconds: 45)

        store.startPlan(plan, availableSupport: [])
        XCTAssertTrue(store.presented)
        XCTAssertEqual(store.configured?.current.exerciseID, "squat")
        XCTAssertEqual(store.configured?.steps.count, 2)
        XCTAssertEqual(store.configured?.current.target, 12)
        XCTAssertEqual(store.configured?.current.restSeconds, 45)
        XCTAssertEqual(store.configured?.source, .manual)
        XCTAssertFalse(store.configured?.hasStarted ?? true)
        XCTAssertNil(store.configured?.actualReps)
        XCTAssertFalse(store.hasInput)
        XCTAssertFalse(store.voiceFeedbackEnabled)
        store.endSet()
        XCTAssertTrue(store.configured?.completed.isEmpty ?? false)

        store.beginConfiguredSet(); store.setConfiguredReps(4); store.endSet()
        XCTAssertTrue(store.history.isEmpty)
        store.finish()
        let record = try XCTUnwrap(store.history.first)
        XCTAssertEqual(record.setCount, 1)
        XCTAssertEqual(record.loggedSets.first?.reps, 4)
        XCTAssertEqual(record.loggedSets.first?.source, .manual)
        XCTAssertEqual(record.loggedSets.first?.quantityOrigin, .selfReport)
        XCTAssertEqual(WorkoutReport(record: record).sets.first?.exerciseID, "squat")
        XCTAssertEqual(defaults.data(forKey: "coach.approvedPlan"), savedCoachData)
        XCTAssertEqual(coach.approvedPlan?.items.first?.exerciseID, "pushup")
        XCTAssertEqual(providerRequests, 0)
    }

    func testEveryCatalogueExerciseKeepsItsCanonicalUnitAndExistingCameraEligibility() throws {
        let store = TrainingStore(historyURL: cameraHistoryURL())
        for entry in ExerciseCatalog.all {
            let support = Set(entry.support.map { [$0] } ?? [])
            let plan = try CoachSavedPlan.catalogue(exerciseID: entry.id, sets: 2,
                                                   target: entry.goal, restSeconds: 30, availableSupport: support)
            store.startPlan(plan, availableSupport: support)
            XCTAssertEqual(store.configured?.current.unit, entry.unit, entry.id)
            XCTAssertEqual(store.configured?.steps.count, 2, entry.id)
            XCTAssertEqual(store.configured?.source, .manual, entry.id)
            XCTAssertFalse(store.configured?.hasStarted ?? true, entry.id)
            XCTAssertEqual(store.selectConfiguredInput(.phoneCamera), entry.tracking != nil, entry.id)
            XCTAssertFalse(store.hasInput, entry.id)
            XCTAssertTrue(store.history.isEmpty, entry.id)
            store.finish()
        }
    }

    func testCatalogueSetupRejectsUnknownExercisesInvalidBoundsAndUnconfirmedSupport() throws {
        for input in [("missing", 1, 8, 30), ("squat", 0, 8, 30), ("squat", 11, 8, 30),
                      ("squat", 1, 0, 30), ("squat", 1, 201, 30), ("plank", 1, 601, 30),
                      ("squat", 1, 8, -1), ("squat", 1, 8, 601)] {
            XCTAssertThrowsError(try CoachSavedPlan.catalogue(exerciseID: input.0, sets: input.1,
                                                              target: input.2, restSeconds: input.3))
        }
        XCTAssertThrowsError(try CoachSavedPlan.catalogue(exerciseID: "wallPushup", sets: 1,
                                                          target: 8, restSeconds: 30))
        XCTAssertThrowsError(try CoachSavedPlan.catalogue(exerciseID: "squat", sets: 1,
                                                          target: 8, restSeconds: 30,
                                                          createdAt: Date(timeIntervalSince1970: .infinity)))
        let supported = try CoachSavedPlan.catalogue(exerciseID: "wallPushup", sets: 1, target: 8,
                                                     restSeconds: 30, availableSupport: ["Wall"])
        XCTAssertNoThrow(try ConfigurableSession(plan: supported, availableSupport: ["Wall"]))
        XCTAssertNoThrow(try CoachSavedPlan.catalogue(exerciseID: "squat", sets: 10, target: 200, restSeconds: 600))
        XCTAssertNoThrow(try CoachSavedPlan.catalogue(exerciseID: "plank", sets: 10, target: 600, restSeconds: 0))
    }

    func testCatalogueHoldRecordsOnlyActiveSecondsInsteadOfItsPlannedTarget() throws {
        let plan = try CoachSavedPlan.catalogue(exerciseID: "plank", sets: 1, target: 20, restSeconds: 30)
        var run = try ConfigurableSession(plan: plan, availableSupport: [])
        run.start(at: 10)
        XCTAssertEqual(run.elapsed(at: 50), 0)
        run.beginSet(at: 50); run.pause(at: 55); run.resume(at: 100)
        XCTAssertTrue(run.endSet(at: 107))
        run.nextSet(at: 108)
        let report = WorkoutReport(record: run.record)
        XCTAssertEqual(report.holdSeconds, 12)
        XCTAssertEqual(report.reps, 0)
        XCTAssertEqual(report.sets.first?.quantityOrigin, .activeTimer)
        XCTAssertEqual(report.sets.first?.source, .manual)
        XCTAssertFalse(SkillProgress.evaluate(history: [run.record]).node(exerciseID: "plank")?.isComplete ?? true)
    }

    func testConfiguredPhoneCameraStartsOnlyOnBeginAndRejectsOtherOrStaleFrames() async throws {
        let vision = VisionWorker(cameraAvailable: { true }, requestAccess: { _ in })
        let side = SecondaryCameraVisionWorker(infer: { _, time in
            (PoseFrame(time: time, width: 1, height: 1, points: []), UIImage())
        })
        let store = TrainingStore(historyURL: cameraHistoryURL(), secondaryVision: side, vision: vision)
        store.startPlan(try cameraPlan(), availableSupport: [])
        XCTAssertEqual(store.configured?.source, .manual)
        XCTAssertTrue(store.selectConfiguredInput(.phoneCamera))
        XCTAssertFalse(store.configured?.hasStarted ?? true)
        XCTAssertFalse(store.hasInput)
        store.beginConfiguredSet()
        let generation = try XCTUnwrap(store.configured?.generation)
        XCTAssertTrue(store.hasInput)
        side.onFrame?(PoseFrame(time: 0, width: 1, height: 1, points: []), UIImage(), generation)
        XCTAssertNil(store.frame)
        vision.onFrame?(PoseFrame(time: 1, width: 1, height: 1, points: []), UIImage(), generation)
        for _ in 0..<10 where store.frame == nil { await Task.yield() }
        XCTAssertNotNil(store.frame)
        XCTAssertEqual(store.configured?.cue, .tracking)
        store.pause()
        vision.onFrame?(PoseFrame(time: 2, width: 1, height: 1, points: []), UIImage(), generation)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertNil(store.frame)
        XCTAssertEqual(store.configured?.phase, .paused)
        XCTAssertEqual(store.configured?.actualReps, 0)
        store.finish()
    }

    func testConfiguredPiFailureRequiresExplicitManualFallbackAndUnsupportedExercisesNeverCapture() throws {
        var starts = 0
        let store = TrainingStore(historyURL: cameraHistoryURL(), secondaryCameraClient: {
            starts += 1
            throw SecondaryCameraError.staleFrame
        })
        store.startPlan(try cameraPlan(exerciseID: "wallPushup"), availableSupport: ["Wall"])
        XCTAssertFalse(store.selectConfiguredInput(.secondaryCamera))
        store.beginConfiguredSet()
        XCTAssertEqual(starts, 0)
        store.finish()
        store.startPlan(try cameraPlan(), availableSupport: [])
        XCTAssertTrue(store.selectConfiguredInput(.secondaryCamera))
        XCTAssertEqual(starts, 0)
        store.beginConfiguredSet()
        XCTAssertEqual(starts, 1)
        XCTAssertEqual(store.configured?.phase, .paused)
        XCTAssertNil(store.frame)
        XCTAssertTrue(store.selectConfiguredInput(.manual))
        XCTAssertFalse(store.configured?.hasStarted ?? true)
        store.beginConfiguredSet(); store.setConfiguredReps(3); store.endSet()
        XCTAssertEqual(store.configured?.completed.last?.source, .manual)
        XCTAssertEqual(store.configured?.completed.last?.reps, 3)
        store.finish()
    }

    func testConfiguredCameraVoiceUsesConfiguredIdentityAndNewPlanResetsOptIn() async throws {
        let voice = ConfiguredRecordingVoice()
        let vision = VisionWorker(cameraAvailable: { true }, requestAccess: { _ in })
        let store = TrainingStore(historyURL: cameraHistoryURL(), voicePlayback: voice, vision: vision)
        store.startPlan(try cameraPlan(), availableSupport: [])
        store.selectConfiguredInput(.phoneCamera); store.beginConfiguredSet(); store.setVoiceFeedback(true)
        let run = try XCTUnwrap(store.configured)
        vision.onFrame?(PoseFrame(time: 1, width: 1, height: 1, points: []), UIImage(), run.generation)
        for _ in 0..<10 where voice.spoken.isEmpty { await Task.yield() }
        XCTAssertEqual(voice.spoken.first?.sessionID, run.id)
        XCTAssertEqual(voice.spoken.first?.generation, run.generation)
        store.pause()
        XCTAssertEqual(voice.stops, 1)
        XCTAssertNil(store.coachingEvent)
        store.startPlan(try cameraPlan(), availableSupport: [])
        XCTAssertFalse(store.voiceFeedbackEnabled)
        store.finish()
    }

    private func cameraHistoryURL() -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder.appendingPathComponent("history.json")
    }

    private func cameraPlan(exerciseID: String = "squat") throws -> CoachSavedPlan {
        try JSONDecoder().decode(CoachSavedPlan.self, from: Data("""
        {"items":[{"exerciseID":"\(exerciseID)","sets":1,"target":2,"unit":"reps","restSeconds":30}],
        "approvedAt":0,"rationale":"Offline configured camera fixture"}
        """.utf8))
    }
}

@MainActor
private final class ConfiguredRecordingVoice: VoicePlayback {
    var onFinish: ((UUID) -> Void)?
    var spoken: [VoiceCue] = []
    var stops = 0
    func speak(_ cue: VoiceCue) { spoken.append(cue) }
    func stop() { stops += 1 }
}

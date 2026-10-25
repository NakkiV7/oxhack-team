import XCTest
import UIKit
@testable import Spottr

@MainActor
final class ConfiguredWorkoutFlowTests: XCTestCase {
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

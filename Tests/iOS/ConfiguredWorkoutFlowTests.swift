import XCTest
import UIKit
import Observation
import SwiftUI
@testable import Spottr

@MainActor
final class ConfiguredWorkoutFlowTests: XCTestCase {
    func testNativeRecoveryScreensRetainEarnedCountAndExposeBothRecoveryStates() async throws {
        let vision=VisionWorker(cameraAvailable:{true},requestAccess:{_ in})
        let store=TrainingStore(historyURL:cameraHistoryURL(),vision:vision)
        store.repVoice.coach=nil
        store.beginAuthorizedPlan(try CoachSavedPlan.catalogue(exerciseID:"squat",sets:1,target:6,restSeconds:30),availableSupport:[])
        XCTAssertTrue(store.selectConfiguredInput(.phoneCamera)); store.beginConfiguredSet()
        let token=try XCTUnwrap(store.configured?.generation)
        for offset in [0.0,2.0] {
            for (time,angle) in [(0.0,170.0),(0.2,170),(0.6,90),(0.8,90),(1.2,170),(1.4,170)] {
                var points=Array(repeating:PosePoint(x:0,y:0,confidence:0),count:33)
                for side in 0...1 {
                    let x=0.4+Double(side)*0.05
                    points[11+side] = .init(x:x,y:0.05,confidence:1)
                    points[23+side] = .init(x:x,y:0.25,confidence:1)
                    points[25+side] = .init(x:x,y:0.5,confidence:1)
                    points[27+side] = .init(x:x+sin(angle * .pi/180)*0.25,y:0.5-cos(angle * .pi/180)*0.25,confidence:1)
                }
                vision.onFrame?(.init(time:time+offset,width:640,height:640,points:points),UIImage(),token)
                for _ in 0..<50 where store.frame?.time != time+offset { await Task.yield() }
            }
        }
        XCTAssertEqual(store.configured?.actualReps,2)
        vision.onFrame?(.init(time:4,width:640,height:640,points:[],observation:.multiplePeople),UIImage(),token)
        for _ in 0..<50 where store.configured?.cameraRecoveryState != .needsResume { await Task.yield() }
        store.frame=nil; store.image=nil
        let previous=UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first { $0.isKeyWindow }
        let host=UIHostingController(rootView:ConfiguredSessionView(store:store))
        let scene=try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window=UIWindow(windowScene:scene)
        window.frame=CGRect(x:0,y:0,width:390,height:844)
        window.overrideUserInterfaceStyle = .light; window.rootViewController=host; window.makeKeyAndVisible()
        defer { window.isHidden=true; previous?.makeKey(); store.finish(); vision.stop() }
        for state in [CameraRecoveryState.needsResume,.waitingForClear] {
            if state == .waitingForClear { store.resume() }
            XCTAssertEqual(store.configured?.cameraRecoveryState,state)
            XCTAssertEqual(store.configured?.actualReps,2)
            host.view.setNeedsLayout(); host.view.layoutIfNeeded()
            try await Task.sleep(for:.milliseconds(150))
            var drawn=false
            let image=UIGraphicsImageRenderer(bounds:window.bounds).image { _ in drawn=window.drawHierarchy(in:window.bounds,afterScreenUpdates:true) }
            XCTAssertTrue(drawn,"Recovery screenshot must draw the attached native view hierarchy")
            let pixels=try XCTUnwrap(image.cgImage?.dataProvider?.data) as Data
            XCTAssertGreaterThan(Set(pixels).count,8,"A blank bitmap is not rendering acceptance")
            // Inspect the real rendered primary-action colour, not a mirrored presentation flag.
            let cgImage=try XCTUnwrap(image.cgImage), width=cgImage.width, height=cgImage.height
            var rgba=[UInt8](repeating:0,count:width*height*4)
            let context=try XCTUnwrap(CGContext(data:&rgba,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,
                space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cgImage,in:CGRect(x:0,y:0,width:width,height:height))
            var leftBlue=0, rightBlue=0
            for y in 0..<height { for x in 0..<width {
                let i=(y*width+x)*4
                if Int(rgba[i+2]) > Int(rgba[i])+40 && Int(rgba[i+2]) > Int(rgba[i+1])+40 {
                    if x < width/2 { leftBlue += 1 } else { rightBlue += 1 }
                }
            } }
            if state == .needsResume { XCTAssertGreaterThan(leftBlue,rightBlue,"Resume camera must be the primary recovery action") }
            else { XCTAssertGreaterThan(rightBlue,leftBlue,"Normal End set emphasis returns after acknowledgment") }
            let data=try XCTUnwrap(image.pngData())
            XCTAssertGreaterThan(data.count,10_000)
            if let folder=ProcessInfo.processInfo.environment["SPOTTR_RECOVERY_RENDER_DIR"] {
                let url=URL(fileURLWithPath:folder); try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
                try data.write(to:url.appendingPathComponent("camera-\(state.rawValue).png"))
            }
        }
    }

    func testCameraRecoveryPublishesEvenWhenTrackingCueAndQuantityStayUnchanged() async throws {
        let vision = VisionWorker(cameraAvailable: { true }, requestAccess: { _ in })
        let store = TrainingStore(historyURL: cameraHistoryURL(), vision: vision)
        store.beginAuthorizedPlan(try cameraPlan(), availableSupport: [])
        XCTAssertTrue(store.selectConfiguredInput(.phoneCamera)); store.beginConfiguredSet()
        let generation = try XCTUnwrap(store.configured?.generation)
        vision.onFrame?(.init(time: 0, width: 640, height: 480, points: []), UIImage(), generation)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(store.configured?.cue, .tracking)
        let changed = expectation(description: "Camera recovery publishes independently of cue or count")
        withObservationTracking { _ = store.configured?.cameraRecoveryState } onChange: { changed.fulfill() }
        vision.onFrame?(.init(time: 1, width: 640, height: 480, points: [], observation: .multiplePeople), UIImage(), generation)
        await fulfillment(of: [changed], timeout: 1)
        XCTAssertEqual(store.configured?.cameraRecoveryState, .needsResume)
        XCTAssertEqual(store.configured?.phase, .active)
        store.resume()
        XCTAssertEqual(store.configured?.cameraRecoveryState, .waitingForClear)
        XCTAssertNotEqual(store.configured?.generation, generation)
        let resumed = try XCTUnwrap(store.configured?.generation)
        var points = Array(repeating: PosePoint(x:0,y:0,confidence:0),count:33)
        for side in 0...1 {
            let x = 0.4 + Double(side)*0.05
            for (index,y) in [(11,0.1),(23,0.3),(25,0.6),(27,0.9)] { points[index+side] = .init(x:x,y:y,confidence:1) }
        }
        // First valid recovery frame changes ready cue to tracking; isolate the later state-only change.
        vision.onFrame?(.init(time:2,width:640,height:640,points:points),UIImage(),resumed)
        for _ in 0..<20 { await Task.yield() }
        let rearmed = expectation(description: "Rearmed state publishes with zero quantity")
        withObservationTracking { _ = store.configured?.cameraRecoveryState } onChange: { rearmed.fulfill() }
        for time in stride(from:2.1,through:4.1,by:0.1) {
            vision.onFrame?(.init(time:time,width:640,height:640,points:points),UIImage(),resumed)
            for _ in 0..<10 { await Task.yield() }
        }
        await fulfillment(of:[rearmed],timeout:1)
        XCTAssertEqual(store.configured?.cameraRecoveryState,.ready)
        XCTAssertEqual(store.configured?.actualReps,0)
        XCTAssertTrue(store.selectConfiguredInput(.manual))
        XCTAssertEqual(store.configured?.cameraRecoveryState, .ready)
        store.finish(); vision.stop()
    }

    func testWorkoutInputChoicesUseOnlyThisIPhoneOrManualEntry() {
        XCTAssertEqual(TrainingStore.ConfiguredInput.allCases.map(\.title), ["Manual reps", "iPhone camera"])
    }
    func testExplicitZeroWorkSkipSavesOnlySkipMetadataAfterFinish() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = TrainingStore(historyURL: folder.appendingPathComponent("history.json"))
        store.beginAuthorizedPlan(try cameraPlan(), availableSupport: [])
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
        store.beginAuthorizedPlan(plan, availableSupport: [])
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
        store.beginAuthorizedPlan(plan, availableSupport: [])
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

        store.beginAuthorizedPlan(plan, availableSupport: ["Wall"])
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

        store.beginAuthorizedPlan(plan, availableSupport: [])
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
            store.beginAuthorizedPlan(plan, availableSupport: support)
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

    func testConfiguredPhoneCameraStartsOnlyOnBeginAndRejectsStaleFrames() async throws {
        let vision = VisionWorker(cameraAvailable: { true }, requestAccess: { _ in })
        let store = TrainingStore(historyURL: cameraHistoryURL(), vision: vision)
        store.beginAuthorizedPlan(try cameraPlan(), availableSupport: [])
        XCTAssertEqual(store.configured?.source, .manual)
        XCTAssertTrue(store.selectConfiguredInput(.phoneCamera))
        XCTAssertFalse(store.configured?.hasStarted ?? true)
        XCTAssertFalse(store.hasInput)
        store.beginConfiguredSet()
        let generation = try XCTUnwrap(store.configured?.generation)
        XCTAssertTrue(store.hasInput)
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

    func testUnsupportedExerciseCannotCaptureAndPhoneFailureAllowsExplicitManualFallback() async throws {
        let vision = VisionWorker(cameraAvailable: { false }, requestAccess: { _ in XCTFail("Unavailable camera must not request access") })
        let store = TrainingStore(historyURL: cameraHistoryURL(), vision: vision)
        store.beginAuthorizedPlan(try cameraPlan(exerciseID: "catCow"), availableSupport: ["Wall"])
        XCTAssertFalse(store.selectConfiguredInput(.phoneCamera))
        store.finish()
        store.beginAuthorizedPlan(try cameraPlan(), availableSupport: [])
        XCTAssertTrue(store.selectConfiguredInput(.phoneCamera))
        XCTAssertFalse(store.hasInput)
        store.beginConfiguredSet()
        for _ in 0..<100 where store.sessionPhase != .paused { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(store.sessionPhase, .paused)
        XCTAssertNil(store.frame)
        XCTAssertTrue(store.selectConfiguredInput(.manual))
        XCTAssertTrue(store.configured?.hasStarted == true)
        store.resume(); store.setConfiguredReps(3); store.endSet()
        XCTAssertEqual(store.configured?.completed.last?.source, .manual)
        XCTAssertEqual(store.configured?.completed.last?.reps, 3)
        store.finish()
    }

    func testConfiguredCameraVoiceUsesConfiguredIdentityAndNewPlanResetsOptIn() async throws {
        let voice = ConfiguredRecordingVoice()
        let vision = VisionWorker(cameraAvailable: { true }, requestAccess: { _ in })
        let store = TrainingStore(historyURL: cameraHistoryURL(), voicePlayback: voice, vision: vision)
        store.beginAuthorizedPlan(try cameraPlan(), availableSupport: [])
        store.selectConfiguredInput(.phoneCamera); store.beginConfiguredSet(); store.setVoiceFeedback(true)
        let run = try XCTUnwrap(store.configured)
        vision.onFrame?(PoseFrame(time: 1, width: 1, height: 1, points: []), UIImage(), run.generation)
        for _ in 0..<100 where store.configured?.cue != .tracking { try await Task.sleep(for: .milliseconds(1)) }
        store.coachingTick(at: store.now + 1)
        XCTAssertEqual(voice.spoken.first?.sessionID, run.id)
        XCTAssertEqual(voice.spoken.first?.generation, run.generation)
        vision.onFrame?(.init(time:2,width:640,height:480,points:[],observation:.multiplePeople),UIImage(),run.generation)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(store.configured?.cameraRecoveryState,.needsResume)
        store.resume(); store.coachingTick(at:store.now+2)
        XCTAssertEqual(voice.stops,0)
        XCTAssertEqual(voice.spoken.count,1)
        XCTAssertEqual(store.configured?.cameraRecoveryState,.waitingForClear)
        store.pause()
        XCTAssertEqual(voice.stops, 1)
        XCTAssertNil(store.coachingEvent)
        store.beginAuthorizedPlan(try cameraPlan(), availableSupport: [])
        XCTAssertTrue(store.voiceFeedbackEnabled)
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

extension ConfiguredWorkoutFlowTests {
    func testCameraHoldFramesAdvanceDisplayedSecondsWithoutRepChangesAndExcludeMissingFrames() async throws {
        let vision = VisionWorker(cameraAvailable: { true }, requestAccess: { _ in })
        let store = TrainingStore(historyURL: cameraHistoryURL(), vision: vision)
        store.beginAuthorizedPlan(try CoachSavedPlan.catalogue(exerciseID: "plank", sets: 1, target: 20, restSeconds: 30), availableSupport: [])
        XCTAssertTrue(store.selectConfiguredInput(.phoneCamera)); store.beginConfiguredSet()
        let generation = try XCTUnwrap(store.configured?.generation)
        var points = Array(repeating: PosePoint(x: 0, y: 0, confidence: 0), count: 33)
        for (i,x,y) in [(11,0.3,0.4),(12,0.32,0.43),(13,0.3,0.6),(14,0.32,0.63),(15,0.5,0.6),(16,0.52,0.63),(23,0.6,0.4),(24,0.62,0.43),(25,0.75,0.4),(26,0.77,0.43),(27,0.9,0.4),(28,0.92,0.43)] {
            points[i] = .init(x: x, y: y, confidence: 1)
        }
        let start = store.now
        for i in 0...7 {
            let time = start + Double(i)*0.2
            vision.onFrame?(.init(time: time, width: 1000, height: 1000, points: points), UIImage(), generation)
            for _ in 0..<100 where store.frame?.time != time { try await Task.sleep(for: .milliseconds(1)) }
        }
        XCTAssertEqual(store.configured?.measuredSeconds(at: start+30) ?? -1, 1.4, accuracy: 0.00001)
        XCTAssertEqual(store.configuredDisplayedSeconds, 1)
        vision.onFrame?(.init(time: start+2, width: 1000, height: 1000, points: []), UIImage(), generation)
        for _ in 0..<100 where store.frame?.time != start+2 { try await Task.sleep(for: .milliseconds(1)) }
        XCTAssertEqual(store.configured?.measuredSeconds(at: start+30) ?? -1, 1.4, accuracy: 0.00001)
        XCTAssertEqual(store.configured?.actualReps, nil)
        store.pause(); store.finish()
    }
}

extension ConfiguredWorkoutFlowTests {
    func testNativeFrameBoundaryPreservesBothLimbSamplesAndProxyProvenance() async throws {
        for exercise in [Exercise.standingBicepsCurl, .gluteBridge, .sitToStand] {
            let vision = VisionWorker(cameraAvailable: { true }, requestAccess: { _ in })
            let store = TrainingStore(historyURL: cameraHistoryURL(), vision: vision)
            let support = Set(ExerciseCatalog.find(exercise.rawValue)?.support.map { [$0] } ?? [])
            store.beginAuthorizedPlan(try CoachSavedPlan.catalogue(exerciseID: exercise.rawValue, sets: 1, target: 8, restSeconds: 30, availableSupport: support), availableSupport: support)
            XCTAssertTrue(store.selectConfiguredInput(.phoneCamera)); store.beginConfiguredSet()
            let generation = try XCTUnwrap(store.configured?.generation)
            let timeline: [(Double,Double)] = exercise == .sitToStand ? [(0,100),(0.2,100),(0.5,140),(0.8,170),(1,170)] : [(0,170),(0.2,170),(0.4,140),(0.6,90),(0.8,90),(1.2,170),(1.4,170)]
            for (time, angle) in timeline {
                var points = Array(repeating: PosePoint(x: 0,y: 0,confidence: 0), count: 33)
                for side in 0...1 {
                    let offset = Double(side)*0.02
                    func put(_ index: Int, _ x: Double, _ y: Double) { points[index+side] = .init(x:x+offset,y:y,confidence:1) }
                    if exercise == .standingBicepsCurl {
                        put(11,0.4,0.2); put(13,0.4,0.4); put(15,0.4+sin(angle * .pi/180)*0.2,0.4-cos(angle * .pi/180)*0.2); put(23,0.4,0.65)
                    } else if exercise == .gluteBridge {
                        put(11,0.15,0.7); put(23,0.45,angle < 100 ? 0.58 : 0.7); put(25,0.65,0.5); put(27,0.75,0.8)
                    } else {
                        put(11,0.4,0.1); put(23,0.4,0.3); put(25,0.4,0.55); put(27,0.4+sin(angle * .pi/180)*0.25,0.55-cos(angle * .pi/180)*0.25)
                    }
                }
                vision.onFrame?(.init(time:time,width:1000,height:1000,points:points), UIImage(), generation)
                for _ in 0..<100 where store.frame?.time != time { try await Task.sleep(for: .milliseconds(1)) }
            }
            XCTAssertEqual(store.configured?.actualReps, 1, exercise.rawValue)
            if exercise == .standingBicepsCurl { XCTAssertEqual(store.configured?.counter?.completedLimbCycles, 2) }
            if exercise == .standingBicepsCurl { XCTAssertNotNil(store.configured?.counter?.lastRepPhases) }
            else { XCTAssertNil(store.configured?.counter?.lastRepPhases) }
            if exercise == .sitToStand { XCTAssertTrue(store.configured?.repDurations.isEmpty == true) }
            store.pause(); store.finish()
        }
    }
}

extension ConfiguredWorkoutFlowTests {
    func testManualTimerTargetNeverBecomesObservedTargetWhenSwitchingToCamera() async throws {
        let vision = VisionWorker(cameraAvailable: { true }, requestAccess: { _ in })
        let store = TrainingStore(historyURL: cameraHistoryURL(), vision: vision)
        defer { store.pause(); store.finish() }
        store.beginAuthorizedPlan(try CoachSavedPlan.catalogue(exerciseID: "plank", sets: 1, target: 1, restSeconds: 30), availableSupport: [])
        store.beginConfiguredSet()
        try await Task.sleep(for: .milliseconds(1100))
        XCTAssertTrue(store.selectConfiguredInput(.phoneCamera))
        let run = try XCTUnwrap(store.configured)
        let start = store.now
        let manualSeconds = run.measuredSeconds(at: start)
        XCTAssertGreaterThanOrEqual(manualSeconds, 1)
        XCTAssertEqual(run.quantityOrigin(at: start), .activeTimer)
        XCTAssertEqual(run.quantitySourcePresentation(at: start).title, "Manual hold, active timer")
        XCTAssertNotEqual(store.coachingEvent?.decision.reason, .targetReached, "Selecting camera cannot relabel the manual target.")
        for index in 0...1 {
            let time = start + Double(index)*0.2
            vision.onFrame?(qualifiedPlankFrame(at: time), UIImage(), run.generation)
            for _ in 0..<100 where store.frame?.time != time { try await Task.sleep(for: .milliseconds(1)) }
            XCTAssertEqual(store.frame?.time, time)
            store.coachingTick(at: time)
            XCTAssertEqual(store.configured?.holdCounter?.observedSeconds ?? -1, Double(index)*0.2, accuracy: 0.00001)
            XCTAssertEqual(store.configured?.measuredSeconds(at: time) ?? -1, manualSeconds + Double(index)*0.2, accuracy: 0.00001)
            XCTAssertEqual(store.configured?.quantityOrigin(at: time), index == 0 ? .activeTimer : .mixed)
            XCTAssertEqual(store.configured?.quantitySourcePresentation(at: time).title, index == 0 ? "Manual hold, active timer" : "Camera + manual quantity")
            let snapshot = CompanionSnapshot(session: try XCTUnwrap(store.configured), at: time)
            XCTAssertEqual(snapshot.configured?.quantityOrigin, index == 0 ? .activeTimer : .mixed)
            XCTAssertEqual(snapshot.quantityOriginLabel, index == 0 ? "Manual hold, active timer" : "Camera + manual quantity")
            XCTAssertTrue(snapshot.quantityAccessibilityValue.contains(index == 0 ? "Manual hold, active timer" : "Camera + manual quantity"))
            XCTAssertEqual(snapshot.configured?.source, .camera)
            XCTAssertNotEqual(store.coachingEvent?.decision.reason, .targetReached)
            XCTAssertFalse(store.coachingEvent?.decision.facts.contains(where: { $0.contains("observed seconds") }) ?? false)
        }
    }

    func testCameraOnlyTimedTargetStillProducesObservedSecondsFact() async throws {
        let vision = VisionWorker(cameraAvailable: { true }, requestAccess: { _ in })
        let store = TrainingStore(historyURL: cameraHistoryURL(), vision: vision)
        defer { store.pause(); store.finish() }
        store.beginAuthorizedPlan(try CoachSavedPlan.catalogue(exerciseID: "plank", sets: 1, target: 1, restSeconds: 30), availableSupport: [])
        XCTAssertTrue(store.selectConfiguredInput(.phoneCamera)); store.beginConfiguredSet()
        let run = try XCTUnwrap(store.configured)
        let start = store.now
        for index in 0...6 {
            let time = start + Double(index)*0.2
            vision.onFrame?(qualifiedPlankFrame(at: time), UIImage(), run.generation)
            for _ in 0..<100 where store.frame?.time != time { try await Task.sleep(for: .milliseconds(1)) }
            XCTAssertEqual(store.frame?.time, time)
        }
        store.coachingTick(at: start+2)
        XCTAssertEqual(store.configured?.quantityOrigin(at: start+2), .cameraObserved)
        XCTAssertEqual(store.coachingEvent?.decision.reason, .targetReached)
        XCTAssertTrue(store.coachingEvent?.decision.facts.contains(where: { $0.contains("observed seconds") }) ?? false)
    }

    private func qualifiedPlankFrame(at time: Double) -> PoseFrame {
        var points = Array(repeating: PosePoint(x: 0, y: 0, confidence: 0), count: 33)
        for (i,x,y) in [(11,0.3,0.4),(12,0.32,0.43),(13,0.3,0.6),(14,0.32,0.63),(15,0.5,0.6),(16,0.52,0.63),(23,0.6,0.4),(24,0.62,0.43),(25,0.75,0.4),(26,0.77,0.43),(27,0.9,0.4),(28,0.92,0.43)] {
            points[i] = .init(x: x, y: y, confidence: 1)
        }
        return .init(time: time, width: 1000, height: 1000, points: points)
    }
}

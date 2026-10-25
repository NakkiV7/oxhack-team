import AVFoundation
import XCTest
import UIKit
@testable import Spottr

@MainActor
final class PreviewRepCueTests: XCTestCase {
    func testEvenLegacyTargetStillEncouragesAndNextSetStartsANewTwoRepMilestone() {
        for exercise in Exercise.allCases {
            let (store, cached, clock) = makeStore(exercise: exercise)
            defer { store.cancelCoaching() }
            for index in 0..<exercise.target { completeRep(index, store: store, clock: clock) }
            XCTAssertEqual(cached.spoken.filter { $0.reason == .steadyRhythm }.count, exercise.target / 2)
            XCTAssertEqual(store.coachingEvent?.decision.reason, .steadyRhythm,
                           "Reaching an even target must not replace the requested cached encouragement with local target speech")
            XCTAssertEqual(store.session.phase, .active)
            store.endSet(); store.next()
            let count = cached.spoken.count
            completeRep(0, store: store, clock: clock)
            XCTAssertEqual(cached.spoken.count, count)
            completeRep(1, store: store, clock: clock)
            XCTAssertEqual(cached.spoken.count, count + 1)
            XCTAssertEqual(cached.spoken.last?.reason, .steadyRhythm)
            XCTAssertEqual(cached.spoken.last?.generation, store.session.generation)
        }
    }

    func testConfiguredCameraEncouragesAtTwoRepTargetAcrossExplicitSetTransitions() async throws {
        for exercise in Exercise.allCases {
            let cached = RepRecordingVoice()
            let remote = RemoteVoicePlayback(local: RepRecordingVoice(), previewPlayback: cached, client: {
                XCTFail("Configured preview encouragement cannot request a provider")
                throw RemoteVoiceError.configuration
            })
            let vision = VisionWorker(cameraAvailable: { true }, requestAccess: { _ in })
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("history.json")
            let store = TrainingStore(historyURL: url, voicePlayback: remote, vision: vision, previewMode: true, previewPlayback: cached)
            store.repVoice.coach = nil   // the rep counter replaces this encouragement when on; see testPreviewEncouragementGivesWayToTheRepCounter
            defer { store.cancelCoaching(); vision.stop() }
            store.startPlan(try CoachSavedPlan.catalogue(exerciseID: exercise.rawValue, sets: 2, target: 2, restSeconds: 0), availableSupport: [])
            store.setVoiceFeedback(true)
            for set in 0..<2 {
                XCTAssertTrue(store.selectConfiguredInput(.phoneCamera))
                store.beginConfiguredSet()
                let generation = try XCTUnwrap(store.configured?.generation)
                for rep in 0..<2 {
                    for (offset, angle) in [(0.0, 170.0), (0.2, 170), (0.6, 90), (0.8, 90),
                                            (1.2, 90), (1.4, 90), (1.8, 170), (2.0, 170)] {
                        let time = Double(rep) * 2.2 + offset
                        vision.onFrame?(poseFrame(exercise: exercise, time: time, angle: angle), UIImage(), generation)
                        for _ in 0..<30 where store.frame?.time != time { await Task.yield() }
                        XCTAssertEqual(store.frame?.time, time)
                    }
                    XCTAssertEqual(store.configured?.actualReps, rep + 1)
                    XCTAssertEqual(cached.spoken.filter { $0.reason == .steadyRhythm }.count, set + rep)
                }
                XCTAssertEqual(store.coachingEvent?.decision.reason, .steadyRhythm)
                XCTAssertEqual(cached.spoken.last?.generation, generation)
                XCTAssertEqual(store.configured?.phase, .active, "A target cue cannot automatically end the set")
                XCTAssertTrue(store.history.isEmpty)
                store.endSet()
                if set == 0 { store.next() }
            }
        }
    }

    func testPreviewCameraEncouragesEveryTwoFreshRepsWithoutHistoryAndDoesNotRepeatATick() throws {
        for exercise in Exercise.allCases {
            let (store, cached, clock) = makeStore(exercise: exercise)
            defer { store.cancelCoaching() }
            XCTAssertTrue(store.history.isEmpty)
            completeRep(0, store: store, clock: clock)
            XCTAssertTrue(cached.spoken.isEmpty)
            completeRep(1, store: store, clock: clock)
            let first = try XCTUnwrap(cached.spoken.last)
            XCTAssertEqual(first.reason, .steadyRhythm)
            XCTAssertEqual(first.kind, .coaching(.pacing))
            XCTAssertEqual(first.sessionID, store.session.id)
            XCTAssertEqual(first.generation, store.session.generation)
            store.coachingTick(at: clock.now)
            XCTAssertEqual(cached.spoken.count, 1)
            cached.onFinish?(first.id)
            completeRep(2, store: store, clock: clock)
            XCTAssertEqual(cached.spoken.count, 1)
            completeRep(3, store: store, clock: clock)
            XCTAssertEqual(cached.spoken.count, 2)
            XCTAssertEqual(cached.spoken.last?.reason, .steadyRhythm)
            XCTAssertNotEqual(cached.spoken.last?.id, first.id, "A new cue allows the cached bank to choose its next variant")
            XCTAssertEqual(store.session.counter.reps, 4)
            XCTAssertTrue(store.history.isEmpty, "Encouragement cannot create completed work")
        }
    }

    func testNormalModeAndVideoCannotUseThePreviewRepShortcut() {
        for scenario in ["normal", "video"] {
            let (store, cached, clock) = makeStore(preview: scenario != "normal")
            defer { store.cancelCoaching() }
            if scenario == "video" {
                store.source = .video
                store.session.restartSet(source: .video, at: 0)
            }
            for index in 0..<4 { completeRep(index, store: store, clock: clock) }
            XCTAssertEqual(store.session.counter.reps, 4)
            XCTAssertTrue(cached.spoken.isEmpty, scenario)
            XCTAssertNotEqual(store.coachingEvent?.decision.reason, .steadyRhythm, scenario)
        }
    }

    func testMutedRepsCannotCatchUpWhenVoiceIsEnabledAgain() {
        let (store, cached, clock) = makeStore()
        defer { store.cancelCoaching() }
        store.setVoiceFeedback(false)
        completeRep(0, store: store, clock: clock)
        completeRep(1, store: store, clock: clock)
        store.setVoiceFeedback(true)
        store.coachingTick(at: clock.now)
        XCTAssertTrue(cached.spoken.isEmpty)
        completeRep(2, store: store, clock: clock)
        XCTAssertTrue(cached.spoken.isEmpty)
        completeRep(3, store: store, clock: clock)
        XCTAssertEqual(cached.spoken.map(\.reason), [.steadyRhythm])
    }

    func testPauseBackgroundAndOldGenerationCannotAnnounceOrReplayARep() {
        for scenario in ["pause", "background", "stale"] {
            let (store, cached, clock) = makeStore()
            defer { store.cancelCoaching() }
            completeRep(0, store: store, clock: clock)
            let oldGeneration = store.session.generation
            if scenario == "background" { store.setAppActive(false) }
            else { store.pause() }
            if scenario == "stale" { store.resume() }
            completeRep(1, store: store, clock: clock, generation: oldGeneration)
            XCTAssertEqual(store.session.counter.reps, 1)
            XCTAssertTrue(cached.spoken.isEmpty, scenario)
            if scenario == "background" { store.setAppActive(true) }
            if scenario != "stale" { store.resume() }
            store.coachingTick(at: clock.now)
            XCTAssertTrue(cached.spoken.isEmpty, "Returning to active state cannot replay paused or stale work")
        }
    }

    func testTrackingAndAlignmentWinOverAnEligibleSecondRepAndCannotReplayItLater() {
        for cue in [Cue.tracking, .alignment] {
            let (store, cached, clock) = makeStore()
            defer { store.cancelCoaching() }
            completeRep(0, store: store, clock: clock)
            completeRep(1, store: store, clock: clock, tick: false)
            store.session.cue = cue
            store.coachingTick(at: clock.now)
            XCTAssertEqual(store.coachingEvent?.decision.priority, .form)
            XCTAssertEqual(cached.spoken.last?.kind, .coaching(.form))
            XCTAssertFalse(cached.spoken.contains { $0.reason == .steadyRhythm })
            store.session.cue = .controlled
            store.coachingTick(at: clock.now + 1)
            XCTAssertFalse(cached.spoken.contains { $0.reason == .steadyRhythm }, "Clearing a form cue is not a new rep")
        }
    }

    func testDiscomfortStopsEncouragementAndRepeatedTicksDoNotReplaceTheStopCue() {
        let (store, cached, clock) = makeStore()
        defer { store.cancelCoaching() }
        completeRep(0, store: store, clock: clock)
        store.endSet()
        store.feedback(reserve: nil, reason: .discomfort)
        XCTAssertEqual(store.coachingEvent?.decision.reason, .discomfort)
        XCTAssertEqual(store.coachingEvent?.decision.priority, .stop)
        store.coachingTick(at: store.now + 1)
        XCTAssertEqual(store.coachingEvent?.decision.reason, .discomfort)
        XCTAssertFalse(cached.spoken.contains { $0.reason == .steadyRhythm })
    }

    private func makeStore(preview: Bool = true, exercise: Exercise = .squat, repCounter: RepVoicePlan.Coach? = nil,
                           clips: RepClipRecorder? = nil) -> (TrainingStore, RepRecordingVoice, RepCueClock) {
        let clock = RepCueClock(), cached = RepRecordingVoice()
        let remote = RemoteVoicePlayback(local: RepRecordingVoice(), previewPlayback: cached, client: {
            XCTFail("Rep encouragement must use the cache without a provider request")
            throw RemoteVoiceError.configuration
        }, uptime: { clock.now })
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("history.json")
        let store = TrainingStore(historyURL: url, voicePlayback: remote, previewMode: preview, previewPlayback: cached)
        // The rep counter is off unless a test asks for it, so the preview encouragement tests keep their meaning.
        let recorder = clips ?? RepClipRecorder()
        store.repVoice = RepVoicePlayer(defaults: UserDefaults(suiteName: UUID().uuidString)!, makeOutput: recorder.make)
        store.repVoice.coach = repCounter
        store.selectedExercise = exercise
        store.start()
        store.hasInput = true
        store.setVoiceFeedback(true)
        return (store, cached, clock)
    }

    private func completeRep(_ index: Int, store: TrainingStore, clock: RepCueClock, generation: UUID? = nil, tick: Bool = true) {
        let base = Double(index) * 2.2
        for (offset, angle) in [(0.0, 170.0), (0.2, 170), (0.6, 90), (0.8, 90),
                                (1.2, 90), (1.4, 90), (1.8, 170), (2.0, 170)] {
            store.session.consume(.init(time: base + offset, angle: angle), generation: generation ?? store.session.generation)
        }
        clock.now = 100 + base + 2
        if tick { store.coachingTick(at: clock.now) }
    }

    private func poseFrame(exercise: Exercise, time: Double, angle: Double) -> PoseFrame {
        var points = Array(repeating: PosePoint(x: 0, y: 0, confidence: 0), count: 33)
        if exercise == .squat {
            points[23] = .init(x: 0.5, y: 0.25, confidence: 1)
            points[25] = .init(x: 0.5, y: 0.5, confidence: 1)
            points[27] = .init(x: 0.5 + sin(angle * .pi / 180) * 0.25,
                               y: 0.5 - cos(angle * .pi / 180) * 0.25, confidence: 1)
        } else {
            points[11] = .init(x: 0.2, y: 0.5, confidence: 1)
            points[13] = .init(x: 0.3, y: 0.5, confidence: 1)
            points[15] = .init(x: 0.3 - cos(angle * .pi / 180) * 0.1,
                               y: 0.5 + sin(angle * .pi / 180) * 0.1, confidence: 1)
            points[23] = .init(x: 0.5, y: 0.5, confidence: 1)
            points[27] = .init(x: 0.8, y: 0.5, confidence: 1)
        }
        return .init(time: time, width: 640, height: 640, points: points)
    }
}

@MainActor private final class RepCueClock { var now = 100.0 }

@MainActor private final class FakeRepClip: RepVoiceOutput {
    var onFinish: (() -> Void)?
    func play() -> Bool { true }
    func stop() {}
}

/// Records which rep clips the rep voice starts, and finishes them on demand.
@MainActor final class RepClipRecorder {
    private(set) var made: [(clip: String, folder: String)] = []
    private var current: FakeRepClip?
    func make(_ clip: String, _ folder: String) -> RepVoiceOutput {
        made.append((clip, folder)); let output = FakeRepClip(); current = output; return output
    }
    func finish() { current?.onFinish?() }
}

@MainActor
final class RepCounterVoiceTests: XCTestCase {
    private func store(preview: Bool, coach: RepVoicePlan.Coach?, clips: RepClipRecorder) -> (TrainingStore, RepRecordingVoice, RepCueClock) {
        let clock = RepCueClock(), cached = RepRecordingVoice()
        let remote = RemoteVoicePlayback(local: RepRecordingVoice(), previewPlayback: preview ? cached : nil, client: {
            throw RemoteVoiceError.configuration
        }, uptime: { clock.now })
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("history.json")
        let store = TrainingStore(historyURL: url, voicePlayback: remote, previewMode: preview, previewPlayback: preview ? cached : nil)
        store.repVoice = RepVoicePlayer(defaults: UserDefaults(suiteName: UUID().uuidString)!, makeOutput: clips.make)
        store.repVoice.coach = coach
        store.selectedExercise = .squat
        store.start()
        store.hasInput = true
        store.setVoiceFeedback(true)
        store.coachingTick(at: clock.now)
        return (store, cached, clock)
    }
    private func rep(_ index: Int, _ store: TrainingStore, _ clock: RepCueClock) {
        let base = Double(index) * 2.2
        for (offset, angle) in [(0.0, 170.0), (0.2, 170), (0.6, 90), (0.8, 90), (1.2, 90), (1.4, 90), (1.8, 170), (2.0, 170)] {
            store.session.consume(.init(time: base + offset, angle: angle), generation: store.session.generation)
        }
        clock.now = 100 + base + 2
        store.coachingTick(at: clock.now)
    }

    func testCountsEveryCameraRepAndAddsALineEveryThirdCleanRep() {
        let clips = RepClipRecorder()
        let (store, _, clock) = store(preview: false, coach: .goggins, clips: clips)
        defer { store.cancelCoaching() }
        clips.finish()
        for index in 0..<3 { rep(index, store, clock); clips.finish() }
        XCTAssertEqual(clips.made.map(\.clip), ["start", "count-01", "count-02", "count-03", "motivate-1"])
        XCTAssertTrue(clips.made.allSatisfy { $0.folder == "DemoVoice/goggins-reps" })
        XCTAssertTrue(store.history.isEmpty, "Spoken counts never create completed work")
    }

    func testStaysSilentWhenOffForVideoAndWhenVoiceFeedbackIsOff() {
        for scenario in ["off", "video", "muted"] {
            let clips = RepClipRecorder()
            let (store, _, clock) = store(preview: false, coach: scenario == "off" ? nil : .arnold, clips: clips)
            defer { store.cancelCoaching() }
            if scenario == "video" { store.source = .video; store.session.restartSet(source: .video, at: 0) }
            if scenario == "muted" { store.setVoiceFeedback(false) }
            let before = clips.made.count
            for index in 0..<3 { rep(index, store, clock); clips.finish() }
            XCTAssertEqual(clips.made.count, before, scenario)
        }
    }

    func testPreviewEncouragementGivesWayToTheRepCounter() {
        let clips = RepClipRecorder()
        let (store, cached, clock) = store(preview: true, coach: .arnold, clips: clips)
        defer { store.cancelCoaching() }
        clips.finish()
        for index in 0..<4 { rep(index, store, clock); clips.finish() }
        XCTAssertTrue(cached.spoken.isEmpty, "The every-two-reps clip would double up with the counts")
        XCTAssertEqual(clips.made.map(\.clip), ["start", "count-01", "count-02", "count-03", "motivate-1", "count-04"])
        XCTAssertTrue(clips.made.allSatisfy { $0.folder == "DemoVoice/arnold-reps" })
    }

    func testEveryRepClipIsBundledForBothCoachesInThePlayableFormat() throws {
        for coach in RepVoicePlan.Coach.allCases {
            for clip in RepVoicePlan.allClips {
                let url = try XCTUnwrap(Bundle.main.url(forResource: clip, withExtension: "mp3", subdirectory: coach.folder), "\(coach) \(clip)")
                let player = try AVAudioPlayer(contentsOf: url)
                XCTAssertEqual(player.format.sampleRate, 22_050, "\(coach) \(clip)")
                XCTAssertTrue(player.duration > 0 && player.duration <= 10, "\(coach) \(clip)")
            }
        }
    }

    func testCancellingStopsTheQueue() {
        let clips = RepClipRecorder()
        let (store, _, clock) = store(preview: false, coach: .arnold, clips: clips)
        rep(0, store, clock)
        store.pause()
        clips.finish()
        XCTAssertFalse(store.repVoice.isPlaying)
        XCTAssertEqual(clips.made.map(\.clip), ["start"], "The count waiting behind the start line is dropped on pause")
    }
}

@MainActor private final class RepRecordingVoice: VoicePlayback {
    var onFinish: ((UUID) -> Void)?
    var spoken: [VoiceCue] = []
    func speak(_ cue: VoiceCue) { spoken.append(cue) }
    func stop() {}
}

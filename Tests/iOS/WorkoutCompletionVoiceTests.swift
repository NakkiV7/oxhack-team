import XCTest
@testable import Spottr

@MainActor
final class WorkoutCompletionVoiceTests: XCTestCase {
    private func makeStore(url: URL? = nil, previewMode: Bool = true) -> (TrainingStore, CompletionRecordingVoice) {
        let cached = CompletionRecordingVoice()
        let remote = RemoteVoicePlayback(local: CompletionRecordingVoice(), previewPlayback: cached, client: {
            XCTFail("Workout completion cannot contact the gateway")
            throw RemoteVoiceError.configuration
        })
        let history = url ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("history.json")
        return (TrainingStore(historyURL: history, voicePlayback: remote, previewMode: previewMode, previewPlayback: cached), cached)
    }
    private func endManualSet(_ store: TrainingStore) {
        store.switchToManualReps(); store.setManualReps(2); store.endSet()
    }

    func testExplicitFinishAfterEndedWorkPlaysOneTypedCompletionAndTicksDoNotCancelIt() throws {
        let (store, cached) = makeStore()
        defer { store.cancelCoaching() }
        store.start(); store.setVoiceFeedback(true); endManualSet(store)
        XCTAssertTrue(cached.spoken.isEmpty)
        store.finish()
        let event = try XCTUnwrap(cached.spoken.first)
        XCTAssertEqual(event.reason, .workoutCompleted)
        XCTAssertEqual(event.kind, .coaching(.rest))
        XCTAssertEqual(event.sessionID, store.session.id)
        XCTAssertEqual(event.generation, store.session.generation)
        XCTAssertEqual(store.session.phase, .finished)
        XCTAssertEqual(store.history.first?.sets.first?.reps, 2)
        store.coachingTick()
        XCTAssertEqual(cached.stops, 0, "The ordinary timer must not cut off the completion clip")
        store.finish(); store.coachingTick()
        XCTAssertEqual(cached.spoken.count, 1, "Repeated finish/ticks cannot replay completion")
    }

    func testSelectedArnoldCompletesActualWorkoutOutsidePreview() {
        let (store, cached) = makeStore(previewMode: false)
        defer { store.cancelCoaching() }
        store.start(); store.setVoiceFeedback(true); endManualSet(store)
        store.finish()
        XCTAssertEqual(cached.spoken.map(\.reason), [.workoutCompleted])
    }

    func testLastConfiguredNextAfterEndedWorkPlaysCompletionOnce() throws {
        let (store, cached) = makeStore()
        defer { store.cancelCoaching() }
        let plan = try JSONDecoder().decode(CoachSavedPlan.self, from: Data(#"{"items":[{"exerciseID":"squat","sets":1,"target":2,"unit":"reps","restSeconds":30}],"approvedAt":0,"rationale":"Synthetic completion fixture"}"#.utf8))
        store.startPlan(plan, availableSupport: [])
        store.setVoiceFeedback(true); store.beginConfiguredSet(); store.setConfiguredReps(2); store.endSet()
        XCTAssertEqual(store.configured?.phase, .rest)
        XCTAssertTrue(cached.spoken.isEmpty)
        store.next()
        XCTAssertEqual(store.configured?.phase, .finished)
        XCTAssertEqual(cached.spoken.map(\.reason), [.workoutCompleted])
        XCTAssertEqual(store.history.first?.loggedSets.first?.reps, 2)
        store.next(); store.coachingTick()
        XCTAssertEqual(cached.spoken.count, 1)
    }

    func testFinalLegacyNextAfterSixEndedSetsPlaysCompletionOnce() {
        let (store, cached) = makeStore()
        defer { store.cancelCoaching() }
        store.start(); store.setVoiceFeedback(true)
        for index in 0..<6 {
            endManualSet(store)
            XCTAssertTrue(cached.spoken.isEmpty, "Ending a set is not workout completion")
            store.next()
            if index < 5 { XCTAssertTrue(cached.spoken.isEmpty) }
        }
        XCTAssertEqual(store.session.phase, .finished)
        XCTAssertEqual(store.history.first?.sets.count, 6)
        XCTAssertEqual(cached.spoken.map(\.reason), [.workoutCompleted])
        store.next(); store.coachingTick()
        XCTAssertEqual(cached.spoken.count, 1)
    }

    func testEmptyBackgroundDiscomfortAndFeedbackCancellationCannotAnnounceCompletion() {
        for scenario in ["empty", "background", "discomfort", "cancel"] {
            let (store, cached) = makeStore()
            defer { store.cancelCoaching() }
            store.start(); store.setVoiceFeedback(true)
            if scenario != "empty" { endManualSet(store) }
            switch scenario {
            case "background": store.setAppActive(false); store.finish(); store.setAppActive(true)
            case "discomfort": store.feedback(reserve: nil, reason: .discomfort); store.finish()
            case "cancel": store.cancelCoaching() // Cancelling feedback is not an explicit workout finish.
            default: store.finish()
            }
            store.coachingTick()
            XCTAssertTrue(cached.spoken.filter { $0.reason == .workoutCompleted }.isEmpty, scenario)
        }
    }

    func testLateVoiceEnableAndReopeningSavedHistoryCannotReplayCompletion() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("history.json")
        let (store, cached) = makeStore(url: url)
        defer { store.cancelCoaching() }
        store.start(); endManualSet(store); store.finish()
        store.setVoiceFeedback(true); store.coachingTick()
        XCTAssertTrue(cached.spoken.isEmpty)
        let (reopened, reopenedCache) = makeStore(url: url)
        defer { reopened.cancelCoaching() }
        XCTAssertEqual(reopened.history.first?.id, store.session.id)
        reopened.setVoiceFeedback(true); reopened.coachingTick()
        XCTAssertTrue(reopenedCache.spoken.isEmpty)
    }
}

@MainActor
private final class CompletionRecordingVoice: VoicePlayback {
    var onFinish: ((UUID) -> Void)?
    var spoken: [VoiceCue] = []
    var stops = 0
    func speak(_ cue: VoiceCue) { spoken.append(cue) }
    func stop() { stops += 1 }
}

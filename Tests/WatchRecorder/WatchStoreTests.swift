import Foundation
import HealthKit
import CoreMotion

@main struct WatchStoreTests {
    @MainActor static var failures = 0
    @MainActor static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { failures += 1; print("FAIL: \(message)") }
    }
    @MainActor static func settle() async { for _ in 0..<100 { await Task.yield() } }

    @MainActor static func endingRequiresConfirmationAndRejectsChangedContext() async {
        let store = WatchStore()
        var session = TrainingSession(); session.start(at: 0)
        store.state.receive(CompanionSnapshot(session: session))
        store.reachable = true
        store.command(.finish)
        expect(store.link.commands.isEmpty, "Requesting End session does not send a command")
        expect(store.pendingFinish != nil, "End session opens confirmation")
        store.cancelFinish()
        expect(store.pendingFinish == nil && store.link.commands.isEmpty, "Cancel keeps the session untouched")
        store.command(.finish)
        session.pause(at: 1)
        store.state.receive(CompanionSnapshot(session: session, sentAt: Date().addingTimeInterval(0.001)))
        store.confirmFinish()
        expect(store.link.commands.isEmpty, "Changed generation invalidates an old confirmation")
        store.command(.finish); store.confirmFinish(); store.confirmFinish()
        expect(store.link.commands.count == 1 && store.link.commands.first?.action == .finish,
               "An explicit current confirmation sends End session exactly once")
        expect(store.link.commands.first?.generation == session.generation, "Confirmed command retains current generation")
        await settle()
    }

    @MainActor static func pendingCollectionDoesNotClaimRecordingOrSendTelemetry() async {
        let store = WatchStore()
        var session = TrainingSession(); session.start(at: 0)
        store.state.receive(CompanionSnapshot(session: session))
        let before = HKWorkoutSession.created.count
        store.record()
        expect(!store.recording && store.recordingBusy, "Pending access is busy but not recording")
        store.tick()
        expect(store.link.samples.isEmpty && store.heart == nil, "Pending access creates no telemetry or heart rate")
        await settle()
        expect(HKWorkoutSession.created.count == before + 1, "The requested recorder starts once")
        guard let workout = HKWorkoutSession.created.last else { return }
        workout.liveBuilder.collectionCompletion?(true, nil)
        await settle()
        expect(store.recording, "Only successful collection establishes recording")
        session.pause(at: 1)
        store.link.onSnapshot?(CompanionSnapshot(session: session, sentAt: Date().addingTimeInterval(0.001)))
        await settle()
        expect(store.recordingState == .paused, "Phone pause is reflected in recorder status")
        store.tick()
        expect(store.link.samples.isEmpty, "Paused recording does not resend cached telemetry")
        store.recorder.end()
        await settle()
    }

    @MainActor static func staleDuplicateCannotResumeAPausedRecorder() async {
        var now = Date()
        let store = WatchStore(now: { now })
        var session = TrainingSession(); session.start(at: 0)
        let active = CompanionSnapshot(session: session, sentAt: now)
        store.link.onSnapshot?(active)
        await settle()
        store.record()
        await settle()
        guard let workout = HKWorkoutSession.created.last, let motion = CMMotionManager.created.last else {
            expect(false, "The fresh active snapshot allows explicit recording"); return
        }
        workout.liveBuilder.collectionCompletion?(true, nil)
        await settle()
        expect(store.recordingState == .recording && motion.isDeviceMotionActive, "Fresh recording starts motion")

        now = now.addingTimeInterval(11)
        store.tick()
        expect(store.recordingState == .paused && !motion.isDeviceMotionActive, "Expired phone state pauses collection")
        let sampleCount = store.link.samples.count
        store.link.onSnapshot?(active)
        await settle()
        expect(store.recordingState == .paused, "Replaying the retained stale timestamp cannot resume recording")
        expect(!motion.isDeviceMotionActive, "Stale replay cannot restart motion between ticks")
        store.tick()
        expect(store.link.samples.count == sampleCount, "Stale replay cannot publish telemetry")

        let fresh = CompanionSnapshot(session: session, sentAt: now)
        store.link.onSnapshot?(fresh)
        await settle()
        expect(store.recordingState == .recording && motion.isDeviceMotionActive, "A newly accepted fresh active snapshot can resume")
        var paused = session; paused.pause(at: 1)
        store.link.onSnapshot?(CompanionSnapshot(session: paused, sentAt: now))
        await settle()
        expect(store.recordingState == .recording && motion.isDeviceMotionActive, "An equal timestamp cannot apply different phase side effects")
        store.recorder.end()
        await settle()
    }

    @MainActor static func main() async {
        await endingRequiresConfirmationAndRejectsChangedContext()
        await pendingCollectionDoesNotClaimRecordingOrSendTelemetry()
        await staleDuplicateCannotResumeAPausedRecorder()
        if failures > 0 { print("Watch store: \(failures) failures"); exit(1) }
        print("Watch store: 3 behavioral cases passed (SDK/link doubles; no device acceptance)")
    }
}

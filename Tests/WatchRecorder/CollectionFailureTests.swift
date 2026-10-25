import Foundation
import HealthKit
import CoreMotion

// Compiled with the actual WorkoutRecorder, WatchCaptureLifecycle and SensorReading.
// Only external SDK objects are replaced. No source extraction or recorder replica.
@main struct CollectionFailureTests {
    @MainActor static var failures = 0
    @MainActor static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { failures += 1; print("FAIL: \(message)") }
    }
    @MainActor static func until(_ condition: () -> Bool) async {
        for _ in 0..<1000 {
            if condition() { return }
            await Task.yield()
        }
        expect(condition(), "Callback did not arrive within the bounded actor turns")
    }

    @MainActor static func failedCollectionReleasesCaptureAndAllowsRetry(paused: Bool) async {
        let recorder = WorkoutRecorder()
        var statuses: [String] = [], recording: [Bool] = [], samples = 0
        recorder.onState = { statuses.append($0.message); recording.append($0.isRecording) }
        recorder.onMotion = { _, _ in samples += 1 }
        let before = HKWorkoutSession.created.count
        recorder.start()
        await until { HKWorkoutSession.created.count == before + 1 }
        let failedSession = HKWorkoutSession.created[before]
        let failedBuilder = failedSession.liveBuilder
        let motion = CMMotionManager.created.last!
        if paused { recorder.pause() }
        expect(!motion.isDeviceMotionActive, "Pending collection does not start motion")

        failedBuilder.collectionCompletion?(false, nil)
        await until { if case .failed = recorder.state { return true }; return false }
        expect(recording.last == false, "Failed collection makes recording false (paused=\(paused))")
        expect(!motion.isDeviceMotionActive, "Failed collection stops device motion")
        expect(failedSession.endCount == 1, "Failed collection ends its HealthKit session")
        expect(failedBuilder.discardCount == 1, "Failed collection discards unsaved workout")
        expect(failedBuilder.endCollectionCount == 0 && failedBuilder.finishCount == 0,
               "Failed collection does not enter the successful save path")
        motion.deliverQueuedSample()
        for _ in 0..<20 { await Task.yield() }
        expect(samples == 0, "A queued sample cannot publish after collection failure")

        recorder.start()
        await until { HKWorkoutSession.created.count == before + 2 }
        guard HKWorkoutSession.created.count == before + 2 else {
            expect(false, "Failed collection must release the recorder so a user can retry")
            recorder.end(); return
        }
        let replacement = HKWorkoutSession.created[before + 1]
        replacement.liveBuilder.collectionCompletion?(true, nil)
        let statusCount = statuses.count
        await until { statuses.count > statusCount }
        let statusAfterRetry = statuses, recordingAfterRetry = recording
        // A duplicate old completion must not stop, discard or relabel the retry.
        failedBuilder.collectionCompletion?(false, nil)
        failedBuilder.collectionCompletion?(true, nil)
        for _ in 0..<20 { await Task.yield() }
        expect(statuses == statusAfterRetry && recording == recordingAfterRetry,
               "Old builder callbacks cannot alter replacement recording or status")
        expect(replacement.endCount == 0 && replacement.liveBuilder.discardCount == 0,
               "Old builder failure cannot clean up the replacement capture")
        expect(motion.isDeviceMotionActive, "A successful retry still captures motion")
        recorder.end()
    }

    @MainActor static func successfulCollectionRemainsActive() async {
        let recorder = WorkoutRecorder()
        var statuses: [String] = [], recording: [Bool] = []
        recorder.onState = { statuses.append($0.message); recording.append($0.isRecording) }
        let before = HKWorkoutSession.created.count
        recorder.start()
        await until { HKWorkoutSession.created.count == before + 1 }
        let session = HKWorkoutSession.created[before]
        session.liveBuilder.collectionCompletion?(true, nil)
        await until { recorder.state == .recording }
        expect(recording.last == true && session.endCount == 0 && session.liveBuilder.discardCount == 0,
               "Successful collection is not reported as a failed or discarded capture")
        expect(CMMotionManager.created.last!.isDeviceMotionActive, "Successful capture retains motion")
        recorder.end()
    }

    @MainActor static func recordingWaitsForSuccessfulCollectionAndTracksPause() async {
        let recorder = WorkoutRecorder()
        let before = HKWorkoutSession.created.count
        recorder.start()
        expect(recorder.state == .requestingAccess, "Authorization is pending, not recording")
        expect(recorder.state.isBusy && !recorder.state.isRecording, "Pending authorization blocks duplicate starts without claiming recording")
        await until { HKWorkoutSession.created.count == before + 1 }
        let session = HKWorkoutSession.created[before]
        expect(recorder.state == .starting, "Creating a workout does not establish collection success")
        expect(!CMMotionManager.created.last!.isDeviceMotionActive, "Motion waits for successful collection")
        session.liveBuilder.collectionCompletion?(true, nil)
        await until { recorder.state == .recording }
        recorder.pause()
        expect(recorder.state == .paused, "Pause has an explicit local recording state")
        recorder.resume()
        expect(recorder.state == .recording, "Resume returns to recording")
        recorder.end()
        expect(recorder.state == .saving, "Saving is distinct from recording or success")
        await until { recorder.state == .saved }
    }

    @MainActor static func cancelledAuthorizationCannotRelabelIdleOrBeginAWorkout() async {
        HKHealthStore.deferAuthorization = true
        defer { HKHealthStore.deferAuthorization = false }
        let recorder = WorkoutRecorder()
        let before = HKWorkoutSession.created.count
        let requests = HKHealthStore.authorizationRequests.count
        recorder.start(); recorder.start()
        expect(HKHealthStore.authorizationRequests.count == requests + 1, "Pending access cannot request duplicate authorizations")
        let completion = HKHealthStore.authorizationRequests.last!
        recorder.end()
        expect(recorder.state == .idle, "Ending pending access returns to idle without claiming a saved workout")
        completion(false, nil)
        for _ in 0..<20 { await Task.yield() }
        expect(recorder.state == .idle, "Cancelled authorization failure cannot overwrite idle")
        completion(true, nil)
        for _ in 0..<20 { await Task.yield() }
        expect(HKWorkoutSession.created.count == before, "Cancelled authorization success cannot start a workout")
    }

    @MainActor static func deniedWorkoutSharingAllowsAnExplicitRetry() async {
        HKHealthStore.authorization = .sharingDenied
        let recorder = WorkoutRecorder()
        let before = HKWorkoutSession.created.count
        recorder.start()
        await until { if case .failed = recorder.state { return true }; return false }
        expect(!recorder.state.isBusy && !recorder.state.isRecording, "Denied workout sharing is not recording and allows retry")
        expect(HKWorkoutSession.created.count == before, "Denied workout sharing does not create a workout")
        HKHealthStore.authorization = .sharingAuthorized
        recorder.start()
        await until { HKWorkoutSession.created.count == before + 1 }
        HKWorkoutSession.created.last!.liveBuilder.collectionCompletion?(true, nil)
        await until { recorder.state == .recording }
        recorder.end()
    }

    @MainActor static func endingBeforeCollectionSucceedsDiscardsInsteadOfSaving() async {
        let recorder = WorkoutRecorder()
        let before = HKWorkoutSession.created.count
        recorder.start()
        await until { HKWorkoutSession.created.count == before + 1 }
        let session = HKWorkoutSession.created[before]
        recorder.end()
        expect(recorder.state == .idle, "Ending startup does not claim a saved workout")
        expect(session.endCount == 1 && session.liveBuilder.discardCount == 1, "Ending startup releases its unsaved HealthKit session")
        expect(session.liveBuilder.endCollectionCount == 0 && session.liveBuilder.finishCount == 0, "Unconfirmed collection cannot enter the save path")
        session.liveBuilder.collectionCompletion?(true, nil)
        for _ in 0..<20 { await Task.yield() }
        expect(recorder.state == .idle, "Late startup success cannot relabel cancelled recording")
    }

    @MainActor static func main() async {
        await recordingWaitsForSuccessfulCollectionAndTracksPause()
        await cancelledAuthorizationCannotRelabelIdleOrBeginAWorkout()
        await deniedWorkoutSharingAllowsAnExplicitRetry()
        await endingBeforeCollectionSucceedsDiscardsInsteadOfSaving()
        await successfulCollectionRemainsActive()
        await failedCollectionReleasesCaptureAndAllowsRetry(paused: false)
        await failedCollectionReleasesCaptureAndAllowsRetry(paused: true)
        if failures > 0 { print("Watch recorder: \(failures) failures"); exit(1) }
        print("Watch recorder: 7 behavioral cases passed (SDK doubles; no HealthKit/device acceptance)")
    }
}

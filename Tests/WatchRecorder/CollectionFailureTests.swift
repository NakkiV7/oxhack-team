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
        recorder.onStatus = { statuses.append($0) }
        recorder.onRecording = { recording.append($0) }
        recorder.onMotion = { _, _ in samples += 1 }
        let before = HKWorkoutSession.created.count
        recorder.start()
        await until { HKWorkoutSession.created.count == before + 1 }
        let failedSession = HKWorkoutSession.created[before]
        let failedBuilder = failedSession.liveBuilder
        let motion = CMMotionManager.created.last!
        if paused { recorder.pause() }
        else { expect(motion.isDeviceMotionActive, "An active capture starts motion") }

        failedBuilder.collectionCompletion?(false, nil)
        await until { !statuses.isEmpty }
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
        recorder.onStatus = { statuses.append($0) }
        recorder.onRecording = { recording.append($0) }
        let before = HKWorkoutSession.created.count
        recorder.start()
        await until { HKWorkoutSession.created.count == before + 1 }
        let session = HKWorkoutSession.created[before]
        session.liveBuilder.collectionCompletion?(true, nil)
        await until { !statuses.isEmpty }
        expect(recording.isEmpty && session.endCount == 0 && session.liveBuilder.discardCount == 0,
               "Successful collection is not reported as a failed or discarded capture")
        expect(CMMotionManager.created.last!.isDeviceMotionActive, "Successful capture retains motion")
        recorder.end()
    }

    @MainActor static func main() async {
        await successfulCollectionRemainsActive()
        await failedCollectionReleasesCaptureAndAllowsRetry(paused: false)
        await failedCollectionReleasesCaptureAndAllowsRetry(paused: true)
        if failures > 0 { print("Watch recorder: \(failures) failures"); exit(1) }
        print("Watch recorder: 3 behavioral cases passed (SDK doubles; no HealthKit/device acceptance)")
    }
}

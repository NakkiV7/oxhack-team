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

    @MainActor static func energyOnlyCallbacksUseCumulativeKilocaloriesAndStatisticsDate() async {
        let recorder = WorkoutRecorder()
        var energy: [ActiveEnergy] = [], heart: [SensorReading] = []
        recorder.onEnergy = { energy.append($0) }; recorder.onHeart = { heart.append($0) }
        let before = HKWorkoutSession.created.count
        recorder.start()
        await until { HKWorkoutSession.created.count == before + 1 }
        let builder = HKWorkoutSession.created[before].liveBuilder
        expect(HKHealthStore.requestedReadTypes == [.heartRate, .activeEnergyBurned], "Explicit recording requests both HR and active-energy reading")
        expect(builder.dataSource?.typesToCollect.contains(HKQuantityType(.activeEnergyBurned)) == true, "The workout datasource collects active energy")
        let date = Date()
        builder.statisticsByType[.activeEnergyBurned] = HKStatistics(sum: HKQuantity(unit: .kilocalorie(), doubleValue: 5), endDate: date)
        recorder.workoutBuilder(builder, didCollectDataOf: [HKQuantityType(.activeEnergyBurned)])
        for _ in 0..<20 { await Task.yield() }
        expect(energy.isEmpty, "Collection still pending cannot publish energy")
        builder.collectionCompletion?(true, nil)
        await until { recorder.state == .recording }
        recorder.workoutBuilder(builder, didCollectDataOf: [HKQuantityType(.activeEnergyBurned)])
        await until { energy.count == 1 }
        recorder.workoutBuilder(builder, didCollectDataOf: [HKQuantityType(.activeEnergyBurned)])
        await until { energy.count == 2 }
        expect(energy.map(\.kilocalories) == [5, 5], "Repeated cumulative callbacks do not increment the total")
        expect(energy.allSatisfy { $0.asOf == date }, "Statistics endDate survives; callback/send time is not a measurement timestamp")
        expect(heart.isEmpty, "Energy-only callbacks do not fabricate HR")
        builder.statisticsByType[.activeEnergyBurned] = HKStatistics(sum: HKQuantity(unit: .kilocalorie(), doubleValue: 7), endDate: date)
        builder.statisticsByType[.heartRate] = HKStatistics(recent: HKQuantity(unit: HKUnit.count().unitDivided(by: .minute()), doubleValue: 125), endDate: date)
        recorder.workoutBuilder(builder, didCollectDataOf: [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)])
        await until { energy.count == 3 && heart.count == 1 }
        expect(energy.last?.kilocalories == 7 && heart.last?.value == 125, "A combined callback preserves independent HR and cumulative-energy values")
        recorder.end(); await until { recorder.state == .saved }
    }

    @MainActor static func invalidAndMissingEnergyNeverBecomeAnEstimate() async {
        let recorder = WorkoutRecorder()
        var energy: [ActiveEnergy] = []
        recorder.onEnergy = { energy.append($0) }
        let before = HKWorkoutSession.created.count
        recorder.start(); await until { HKWorkoutSession.created.count == before + 1 }
        let builder = HKWorkoutSession.created[before].liveBuilder
        builder.collectionCompletion?(true, nil); await until { recorder.state == .recording }
        let now = Date()
        for (value, date) in [(-1.0, now), (.nan, now), (.infinity, now),
                              (5, Date(timeIntervalSince1970: .nan)), (5, now.addingTimeInterval(30)),
                              (5, now.addingTimeInterval(-60))] {
            builder.statisticsByType[.activeEnergyBurned] = HKStatistics(sum: HKQuantity(unit: .kilocalorie(), doubleValue: value), endDate: date)
            recorder.workoutBuilder(builder, didCollectDataOf: [HKQuantityType(.activeEnergyBurned)])
        }
        builder.statisticsByType[.activeEnergyBurned] = HKStatistics(recent: HKQuantity(unit: .kilocalorie(), doubleValue: 99), endDate: now)
        recorder.workoutBuilder(builder, didCollectDataOf: [HKQuantityType(.activeEnergyBurned)])
        for _ in 0..<30 { await Task.yield() }
        expect(energy.isEmpty, "Missing sum, invalid kcal, nonfinite/future/pre-run dates stay unavailable; recent quantity is not a total")
        builder.statisticsByType[.activeEnergyBurned] = HKStatistics(sum: HKQuantity(unit: .kilocalorie(), doubleValue: 0), endDate: Date())
        recorder.workoutBuilder(builder, didCollectDataOf: [HKQuantityType(.activeEnergyBurned)])
        await until { energy.count == 1 }
        expect(energy.last?.kilocalories == 0, "A real reported zero is retained rather than confused with missing data")
        recorder.end(); await until { recorder.state == .saved }
    }

    @MainActor static func energyIdentitySurvivesResumeButRejectsStoppedOrReplacedBuilders() async {
        let recorder = WorkoutRecorder()
        var energy: [ActiveEnergy] = []
        recorder.onEnergy = { energy.append($0) }
        let before = HKWorkoutSession.created.count
        recorder.start(); await until { HKWorkoutSession.created.count == before + 1 }
        let old = HKWorkoutSession.created[before].liveBuilder
        old.collectionCompletion?(true, nil); await until { recorder.state == .recording }
        func deliver(_ builder: HKLiveWorkoutBuilder, _ value: Double) {
            builder.statisticsByType[.activeEnergyBurned] = HKStatistics(sum: HKQuantity(unit: .kilocalorie(), doubleValue: value), endDate: Date())
            recorder.workoutBuilder(builder, didCollectDataOf: [HKQuantityType(.activeEnergyBurned)])
        }
        deliver(old, 7); await until { energy.count == 1 }
        let firstID = energy.first?.recordingID
        recorder.pause(); deliver(old, 8)
        for _ in 0..<20 { await Task.yield() }
        expect(energy.count == 1, "Paused callbacks cannot publish energy")
        recorder.resume(); deliver(old, 6); await until { energy.count == 2 }
        expect(energy.last?.recordingID == firstID && energy.last?.kilocalories == 6, "Resume retains the run ID and permits a lower genuine cumulative revision")
        deliver(old, 9); recorder.end()
        await until { recorder.state == .saved }
        expect(energy.count == 2, "A queued callback cannot publish after stop")
        recorder.start(); await until { HKWorkoutSession.created.count == before + 2 }
        let current = HKWorkoutSession.created[before + 1].liveBuilder
        current.collectionCompletion?(true, nil); await until { recorder.state == .recording }
        deliver(old, 100); deliver(current, 1)
        await until { energy.count == 3 }
        expect(energy.count == 3 && energy.last?.kilocalories == 1 && energy.last?.recordingID != firstID,
               "A replacement builder has a new run ID and rejects the old builder's late callback")
        recorder.end(); await until { recorder.state == .saved }
    }

    @MainActor static func motionUsesAppleUnitsAndBootRelativeSampleTime() async {
        let recorder = WorkoutRecorder()
        var samples: [(SensorReading, SensorReading)] = []
        recorder.onMotion = { samples.append(($0, $1)) }
        let before = HKWorkoutSession.created.count
        recorder.start(); await until { HKWorkoutSession.created.count == before + 1 }
        let builder = HKWorkoutSession.created[before].liveBuilder
        builder.collectionCompletion?(true, nil); await until { recorder.state == .recording }
        let measuredAt = Date()
        let data = CMDeviceMotion(acceleration: .init(x: -0.3, y: 0.4, z: 0),
                                  rotation: .init(x: 0, y: -1.25, z: 0),
                                  timestamp: ProcessInfo.processInfo.systemUptime)
        CMMotionManager.created.last!.deliverQueuedSample(data)
        await until { samples.count == 1 }
        guard let sample = samples.first else { recorder.end(); return }
        expect(abs(sample.0.value - 0.5) < 0.000001, "Gravity-removed acceleration magnitude retains g, not m/s²")
        expect(sample.1.value == 1.25, "Rotation magnitude retains radians/s, not degrees/s")
        expect(abs(sample.0.date.timeIntervalSince(measuredAt)) < 0.05 && sample.0.date == sample.1.date,
               "Core Motion uptime timestamp maps to one shared measurement date, not the 1970 epoch")
        recorder.end(); await until { recorder.state == .saved }
    }

    @MainActor static func main() async {
        await motionUsesAppleUnitsAndBootRelativeSampleTime()
        await recordingWaitsForSuccessfulCollectionAndTracksPause()
        await cancelledAuthorizationCannotRelabelIdleOrBeginAWorkout()
        await deniedWorkoutSharingAllowsAnExplicitRetry()
        await endingBeforeCollectionSucceedsDiscardsInsteadOfSaving()
        await successfulCollectionRemainsActive()
        await failedCollectionReleasesCaptureAndAllowsRetry(paused: false)
        await failedCollectionReleasesCaptureAndAllowsRetry(paused: true)
        await energyOnlyCallbacksUseCumulativeKilocaloriesAndStatisticsDate()
        await invalidAndMissingEnergyNeverBecomeAnEstimate()
        await energyIdentitySurvivesResumeButRejectsStoppedOrReplacedBuilders()
        if failures > 0 { print("Watch recorder: \(failures) failures"); exit(1) }
        print("Watch recorder: 11 behavioral cases passed (SDK doubles; no HealthKit/device acceptance)")
    }
}

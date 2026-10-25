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

    @MainActor static func energyOnlyTelemetryPreservesTheCumulativeObservationAndResetsForANewSession() async {
        let store = WatchStore()
        var session = TrainingSession(); session.start(at: 0)
        store.link.onSnapshot?(CompanionSnapshot(session: session))
        await settle()
        store.record(); await settle()
        guard let workout = HKWorkoutSession.created.last else { expect(false, "Recorder starts for fresh session"); return }
        workout.liveBuilder.collectionCompletion?(true, nil); await settle()
        let date = Date()
        workout.liveBuilder.statisticsByType[.activeEnergyBurned] = HKStatistics(sum: HKQuantity(unit: .kilocalorie(), doubleValue: 5), endDate: date)
        store.recorder.workoutBuilder(workout.liveBuilder, didCollectDataOf: [HKQuantityType(.activeEnergyBurned)])
        await settle()
        store.tick(); store.tick()
        expect(store.activeEnergy?.kilocalories == 5 && store.activeEnergy?.asOf == date, "Store retains actual energy and statistics timestamp")
        expect(store.link.samples.count == 2 && store.link.samples.allSatisfy { $0.activeEnergy == store.activeEnergy }, "Energy-only telemetry carries the same cumulative observation without summing ticks")
        expect(store.link.samples.allSatisfy { $0.heartRate == nil }, "Energy availability cannot create heart-rate data")
        let count = store.link.samples.count
        session.pause(at: 1)
        store.link.onSnapshot?(CompanionSnapshot(session: session, sentAt: Date().addingTimeInterval(0.001)))
        await settle(); store.tick()
        expect(store.link.samples.count == count, "Paused store does not send cached energy")
        var next = TrainingSession(); next.start(at: 0)
        store.link.onSnapshot?(CompanionSnapshot(session: next, sentAt: Date().addingTimeInterval(0.002)))
        await settle()
        expect(store.activeEnergy == nil, "A new phone session cannot inherit the old recording's energy")
        store.record(); await settle()
        expect(store.activeEnergy == nil, "Starting again does not invent an energy estimate before callbacks")
        store.recorder.end(); await settle()
    }

    @MainActor static func olderEnergyCannotReplaceTheLatestEstimateButCorrectionsCanLowerIt() async {
        let store = WatchStore()
        var session = TrainingSession(); session.start(at: 0)
        store.link.onSnapshot?(CompanionSnapshot(session: session)); await settle()
        store.record(); await settle()
        guard let builder = HKWorkoutSession.created.last?.liveBuilder else { expect(false, "Recorder starts for fresh session"); return }
        builder.collectionCompletion?(true, nil); await settle()
        let first = Date(), second = first.addingTimeInterval(0.001), third = first.addingTimeInterval(0.002)
        func deliver(_ kcal: Double, asOf: Date) async {
            builder.statisticsByType[.activeEnergyBurned] = HKStatistics(sum: HKQuantity(unit: .kilocalorie(), doubleValue: kcal), endDate: asOf)
            store.recorder.workoutBuilder(builder, didCollectDataOf: [HKQuantityType(.activeEnergyBurned)])
            await settle()
        }
        await deliver(7, asOf: second)
        let recordingID = store.activeEnergy?.recordingID
        await deliver(5, asOf: first)
        expect(store.link.samples.isEmpty, "The ordering regression is exercised before the next telemetry tick")
        expect(store.activeEnergy?.kilocalories == 7 && store.activeEnergy?.asOf == second,
               "An older same-run callback cannot replace a newer cumulative observation before tick")
        store.tick()
        expect(store.link.samples.last?.activeEnergy?.kilocalories == 7 && store.link.samples.last?.activeEnergy?.asOf == second,
               "The next tick sends the latest timestamp rather than the last-arriving stale callback")
        await deliver(6, asOf: second)
        expect(store.activeEnergy?.kilocalories == 6 && store.activeEnergy?.asOf == second,
               "An equal-asOf correction can lower cumulative energy")
        await deliver(4, asOf: third)
        expect(store.activeEnergy?.kilocalories == 4 && store.activeEnergy?.asOf == third && store.activeEnergy?.recordingID == recordingID,
               "A newer-asOf correction can lower energy without changing the recording identity")
        store.recorder.end(); await settle()
    }

    @MainActor static func main() async {
        await endingRequiresConfirmationAndRejectsChangedContext()
        await pendingCollectionDoesNotClaimRecordingOrSendTelemetry()
        await staleDuplicateCannotResumeAPausedRecorder()
        await energyOnlyTelemetryPreservesTheCumulativeObservationAndResetsForANewSession()
        await olderEnergyCannotReplaceTheLatestEstimateButCorrectionsCanLowerIt()
        if failures > 0 { print("Watch store: \(failures) failures"); exit(1) }
        print("Watch store: 5 behavioral cases passed (SDK/link doubles; no device acceptance)")
    }
}

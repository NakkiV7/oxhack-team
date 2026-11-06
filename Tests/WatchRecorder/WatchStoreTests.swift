import Foundation
import HealthKit
import CoreMotion
import WatchKit

@main struct WatchStoreTests {
    @MainActor static var failures = 0
    @MainActor static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { failures += 1; print("FAIL: \(message)") }
    }
    @MainActor static func settle() async { for _ in 0..<100 { await Task.yield() } }

    @MainActor static func fixture(now: @escaping () -> Date = Date.init) throws -> WatchStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("watch.json")
        let archive = try WatchWorkoutArchive(url: url)
        let owner = WorkoutOwner(accountID: UUID(), profileID: UUID()), age = try TrainingAgeContext(ageYears: 30, guardianManaged: false)
        let grant = WatchAccessGrant(owner: owner, policyID: UUID(), age: age, verifiedAt: now().addingTimeInterval(-1), membershipDeadline: nil)
        try archive.receive(.init(sequence: 1, owner: owner, policyID: grant.policyID, age: age, sharing: true, grant: grant, choices: [], support: [], timeZoneID: TimeZone.current.identifier))
        return WatchStore(now: now, archiveURL: url)
    }
    @MainActor static func deliver(_ store: WatchStore, _ snapshot: CompanionSnapshot) {
        guard let transport = store.programme else { expect(false, "Fixture has scoped authority"); return }
        store.link.onScopedSnapshot?(.init(snapshot: snapshot, owner: transport.owner, policyID: transport.policyID, allowsHealth: true))
    }

    @MainActor static func endingRequiresConfirmationAndRejectsChangedContext() async {
        let store = try! fixture()
        var session = TrainingSession(); session.start(at: 0)
        Self.deliver(store, CompanionSnapshot(session: session)); await settle()
        store.reachable = true
        store.command(.finish)
        expect(store.link.commands.isEmpty, "Requesting End session does not send a command")
        expect(store.pendingFinish != nil, "End session opens confirmation")
        store.cancelFinish()
        expect(store.pendingFinish == nil && store.link.commands.isEmpty, "Cancel keeps the session untouched")
        store.command(.finish)
        session.pause(at: 1)
        Self.deliver(store, CompanionSnapshot(session: session, sentAt: Date().addingTimeInterval(0.001))); await settle()
        store.confirmFinish()
        expect(store.link.commands.isEmpty, "Changed generation invalidates an old confirmation")
        store.command(.finish); store.confirmFinish(); store.confirmFinish()
        expect(store.link.commands.count == 1 && store.link.commands.first?.action == .finish,
               "An explicit current confirmation sends End session exactly once")
        expect(store.link.commands.first?.generation == session.generation, "Confirmed command retains current generation")
        await settle()
    }

    @MainActor static func pendingCollectionDoesNotClaimRecordingOrSendTelemetry() async {
        let store = try! fixture()
        var session = TrainingSession(); session.start(at: 0)
        let before = HKWorkoutSession.created.count
        Self.deliver(store, CompanionSnapshot(session: session)); await settle()
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
        Self.deliver(store, CompanionSnapshot(session: session, sentAt: Date().addingTimeInterval(0.001)))
        await settle()
        expect(store.recordingState == .paused, "Phone pause is reflected in recorder status")
        store.tick()
        expect(store.link.samples.isEmpty, "Paused recording does not resend cached telemetry")
        store.recorder.end()
        await settle()
    }

    @MainActor static func disconnectionKeepsEstablishedRecordingButNeverEnablesStaleCommands() async {
        var now = Date()
        let store = try! fixture(now: { now })
        var session = TrainingSession(); session.start(at: 0)
        let active = CompanionSnapshot(session: session, sentAt: now)
        Self.deliver(store, active)
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
        expect(store.recordingState == .recording && motion.isDeviceMotionActive, "Expired phone state does not pause an established recording")
        let sampleCount = store.link.samples.count
        Self.deliver(store, active)
        await settle()
        expect(store.recordingState == .recording, "Replaying stale phone state does not relabel recording")
        expect(motion.isDeviceMotionActive, "Established motion capture continues while the phone is stale")
        store.tick()
        expect(store.link.samples.count > sampleCount, "Telemetry keeps the original recording session while disconnected")
        store.reachable = true
        store.command(.pause)
        expect(store.link.commands.isEmpty, "A stale phone snapshot cannot authorize a command")

        let fresh = CompanionSnapshot(session: session, sentAt: now)
        Self.deliver(store, fresh)
        await settle()
        expect(store.recordingState == .recording && motion.isDeviceMotionActive, "A newly accepted fresh active snapshot can resume")
        var paused = session; paused.pause(at: 1)
        Self.deliver(store, CompanionSnapshot(session: paused, sentAt: now))
        await settle()
        expect(store.recordingState == .recording && motion.isDeviceMotionActive, "An equal timestamp cannot apply different phase side effects")
        store.recorder.end()
        await settle()
    }

    @MainActor static func energyOnlyTelemetryPreservesTheCumulativeObservationAndResetsForANewSession() async {
        let store = try! fixture()
        var session = TrainingSession(); session.start(at: 0)
        Self.deliver(store, CompanionSnapshot(session: session))
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
        session.pause(at: 1)
        Self.deliver(store, CompanionSnapshot(session: session, sentAt: Date().addingTimeInterval(0.001)))
        await settle()
        let count = store.link.samples.count
        store.tick()
        expect(store.link.samples.count == count, "Paused store does not send cached energy after its final flush")
        var next = TrainingSession(); next.start(at: 0)
        Self.deliver(store, CompanionSnapshot(session: next, sentAt: Date().addingTimeInterval(0.002)))
        await settle()
        expect(store.activeEnergy == nil, "A new phone session cannot inherit the old recording's energy")
        store.record(); await settle()
        expect(store.activeEnergy == nil, "Starting again does not invent an energy estimate before callbacks")
        store.recorder.end(); await settle()
    }

    @MainActor static func olderEnergyCannotReplaceTheLatestEstimateButCorrectionsCanLowerIt() async {
        let store = try! fixture()
        var session = TrainingSession(); session.start(at: 0)
        Self.deliver(store, CompanionSnapshot(session: session)); await settle()
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


    @MainActor static func heartRateCallbacksCannotRegressOrInventAValidReading() async {
        let store = try! fixture()
        var session = TrainingSession(); session.start(at: 0)
        Self.deliver(store, CompanionSnapshot(session: session)); await settle()
        store.record(); await settle()
        guard let builder = HKWorkoutSession.created.last?.liveBuilder else { expect(false, "Recorder starts"); return }
        builder.collectionCompletion?(true, nil); await settle()
        let first = Date(), later = first.addingTimeInterval(0.001)
        func deliver(_ value: Double, at date: Date) async {
            builder.statisticsByType[.heartRate] = HKStatistics(recent: HKQuantity(unit: HKUnit.count().unitDivided(by: .minute()), doubleValue: value), endDate: date)
            store.recorder.workoutBuilder(builder, didCollectDataOf: [HKQuantityType(.heartRate)])
            await settle()
        }
        await deliver(122, at: later)
        await deliver(119, at: first)
        expect(store.heart == SensorReading(value: 122, date: later), "Older HealthKit callback cannot displace the latest heart reading")
        await deliver(121, at: later)
        expect(store.heart?.value == 121, "Equal-timestamp correction retains the original sample date")
        await deliver(0, at: later.addingTimeInterval(0.001))
        expect(store.heart?.value == 121, "Invalid heart rate cannot displace an observed value")
        store.tick()
        expect(store.link.samples.last?.heartRate == store.heart, "Tick transports the measured value and timestamp")
        store.recorder.end(); await settle()
    }

    @MainActor static func localStopFlushesItsBoundSessionBeforeClearingValues() async {
        var now = Date()
        let store = try! fixture(now: { now })
        var session = TrainingSession(); session.start(at: 0)
        Self.deliver(store, CompanionSnapshot(session: session, sentAt: now)); await settle()
        store.record(); await settle()
        guard let builder = HKWorkoutSession.created.last?.liveBuilder else { expect(false, "Recorder starts"); return }
        builder.collectionCompletion?(true, nil); await settle()
        let energy = ActiveEnergy(recordingID: UUID(), kilocalories: 4, asOf: now)
        store.activeEnergy = energy
        now = now.addingTimeInterval(20)
        store.tick()
        expect(store.recordingState == .recording, "The established workout survives phone timeout")
        let batchesBefore = store.link.batches.count
        store.stopLocalRecording()
        expect(store.link.batches.count > batchesBefore, "A local stop durably enqueues the final observed values")
        expect(store.link.batches.last?.last?.sessionID == session.id && store.link.batches.last?.last?.activeEnergy == energy,
               "Final flush keeps the original session and measured cumulative energy")
        expect(store.link.flushCount > 0 && store.activeEnergy == nil && store.heart == nil, "Final batch flush occurs before transient readings clear")
        expect(store.link.commands.isEmpty, "Local Watch stop does not fabricate an iPhone finish command")
        await settle()
    }

    @MainActor static func explicitPhonePauseDuringStartupSurvivesCollectionCompletion() async {
        let store = try! fixture()
        var session = TrainingSession(); session.start(at: 0)
        Self.deliver(store, CompanionSnapshot(session: session)); await settle()
        store.record(); await settle()
        guard let builder = HKWorkoutSession.created.last?.liveBuilder, let motion = CMMotionManager.created.last else {
            expect(false, "Pending collection exists"); return
        }
        session.pause(at: 1)
        Self.deliver(store, CompanionSnapshot(session: session, sentAt: Date().addingTimeInterval(0.001)))
        await settle()
        builder.collectionCompletion?(true, nil); await settle()
        expect(store.recordingState == .paused && !motion.isDeviceMotionActive,
               "Explicit phone pause during startup must not be undone by successful collection completion")
        store.stopLocalRecording(); await settle()
    }

    @MainActor static func setupReadsExistingMotionAvailabilityWithoutStartingSensors() {
        let before = CMMotionManager.created.count
        let store = try! fixture()
        expect(CMMotionManager.created.count == before + 1, "Setup reuses the recorder motion manager")
        expect(store.link.setupMotionAvailable == CMMotionManager.created.last?.isDeviceMotionAvailable, "Actual Watch motion availability reaches the companion link")
        expect(CMMotionManager.created.dropFirst(before).allSatisfy { !$0.isDeviceMotionActive }, "Setup never starts motion collection")
    }

    @MainActor static func cachedWholeWorkoutAutomaticallyStartsOneRecorderWithoutPhoneSnapshot() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let date = Date(), owner = WorkoutOwner(accountID: UUID(), profileID: UUID())
        let age = try TrainingAgeContext(ageYears: 30, guardianManaged: false)
        let grant = WatchAccessGrant(owner: owner, policyID: UUID(), age: age, verifiedAt: date, membershipDeadline: nil)
        let plan = try CoachSavedPlan.catalogue(exerciseID: "squat", sets: 2, target: 8, restSeconds: 60)
        let url = directory.appendingPathComponent("journal.json")
        let archive = try WatchWorkoutArchive(url: url)
        try archive.receive(.init(sequence: 1, owner: owner, policyID: grant.policyID, age: age, sharing: true, grant: grant,
                                  choices: [.init(id: "today", date: date, plan: plan)], support: [], timeZoneID: TimeZone.current.identifier))
        let store = WatchStore(now: { date }, archiveURL: url)
        let before = HKWorkoutSession.created.count
        store.startCached(choiceID: "today"); await settle()
        expect(store.journal != nil, "A cached whole workout starts without a phone snapshot")
        let independentID = store.journal?.id
        var phone = TrainingSession(); phone.start(at: 0)
        Self.deliver(store, CompanionSnapshot(session: phone)); store.command(.finish); await settle()
        expect(store.journal?.id == independentID && store.pendingFinish == nil && store.link.commands.isEmpty, "Phone snapshots and commands cannot overwrite an independent workout")
        expect(HKWorkoutSession.created.count == before + 1, "Real recorder automatically requests collection exactly once")
        store.tick(); store.tick(); store.record(); await settle()
        expect(HKWorkoutSession.created.count == before + 1, "Ticks and repeated recording requests do not start again")
        expect(store.heart == nil, "Automatic warm-up never invents BPM")
        store.stopLocalRecording(); await settle()
    }

    @MainActor static func cachedManualControlsSurviveRestartExpiryAndPrepareNextSetWithoutStartingIt() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var date = Date(), uptime = 0.0
        let url = directory.appendingPathComponent("watch.json"), owner = WorkoutOwner(accountID: UUID(), profileID: UUID())
        let age = try TrainingAgeContext(ageYears: 10, guardianManaged: true)
        let grant = WatchAccessGrant(owner: owner, policyID: UUID(), age: age, verifiedAt: date, membershipDeadline: date.addingTimeInterval(3))
        let archive = try WatchWorkoutArchive(url: url)
        try archive.receive(.init(sequence: 1, owner: owner, policyID: grant.policyID, age: age, sharing: true, grant: grant, choices: [.init(id: "today", date: date, plan: try .catalogue(exerciseID: "frontArmRaise", sets: 1, target: 6, restSeconds: 3))], support: [], timeZoneID: TimeZone.current.identifier))
        let requests = HKHealthStore.authorizationRequests.count
        let store = WatchStore(now: { date }, archiveURL: url, clock: { uptime })
        store.startCached(choiceID: "today"); store.beginLocalSet(); uptime = 4; store.tick(); store.setLocalReps(3)
        expect(store.journal?.activeSeconds == 4 && store.journal?.reps == 3, "Manual Crown quantity and elapsed time are durable")
        let restarted = WatchStore(now: { date }, archiveURL: url, clock: { uptime })
        expect(restarted.journal?.phase == .paused && restarted.journal?.activeSeconds == 4, "Restart pauses without crediting downtime")
        date = date.addingTimeInterval(100); uptime = 200
        restarted.endLocalSet(); restarted.setEffort(.easy); restarted.requestLocalFinish(); restarted.confirmFinish(); restarted.confirmFinish(); await settle()
        expect(restarted.lastCompleted?.completed.first?.reps == 3 && restarted.lastCompleted?.completed.first?.effort == .easy, "Expired grant preserves actual manual completion and effort")
        expect(restarted.pendingWorkouts == 1 && restarted.link.workouts.last?.grant.owner == owner, "Completed junior practice remains bound to its original owner until app acknowledgement")
        expect(HKHealthStore.authorizationRequests.count == requests, "Junior manual practice never requests HealthKit")

        let adult = try TrainingAgeContext(ageYears: 30, guardianManaged: false)
        let adultGrant = WatchAccessGrant(owner: owner, policyID: UUID(), age: adult, verifiedAt: date, membershipDeadline: nil)
        restarted.link.onProgramme?(.init(sequence: 2, owner: owner, policyID: adultGrant.policyID, age: adult, sharing: true, grant: adultGrant, choices: [.init(id: "today", date: date, plan: try .catalogue(exerciseID: "squat", sets: 2, target: 8, restSeconds: 3))], support: [], timeZoneID: TimeZone.current.identifier)); await settle()
        restarted.startCached(choiceID: "today"); restarted.beginLocalSet(); restarted.setLocalReps(2); restarted.endLocalSet()
        let haptics = WKInterfaceDevice.played; uptime += 4; restarted.tick(); await settle()
        expect(restarted.journal?.index == 1 && restarted.journal?.hasStarted == false && restarted.journal?.activeSeconds == 0, "Rest expiry only prepares the next set")
        expect(WKInterfaceDevice.played == haptics + 1, "Rest expiry requests exactly one ready haptic")
        restarted.tick(); expect(WKInterfaceDevice.played == haptics + 1, "Ready state does not repeat haptics")
        restarted.stopLocalRecording(); await settle()
    }

    @MainActor static func restrictivePolicyCancelsRecorderAndLateMetricsButPreservesManualOrigin() async throws {
        let store = try fixture()
        let original = store.programme!, date = Date()
        let plan = try CoachSavedPlan.catalogue(exerciseID: "squat", sets: 2, target: 8, restSeconds: 3)
        store.link.onProgramme?(.init(sequence: 2, owner: original.owner, policyID: original.policyID, age: original.age, sharing: true, grant: original.grant, choices: [.init(id: "today", date: date, plan: plan)], support: [], timeZoneID: TimeZone.current.identifier)); await settle()
        store.startCached(choiceID: "today"); store.beginLocalSet(); store.setLocalReps(4); await settle()
        let workout = HKWorkoutSession.created.last!, builder = workout.liveBuilder
        builder.collectionCompletion?(true, nil); await settle()
        let child = try TrainingAgeContext(ageYears: 12, guardianManaged: true)
        store.link.onProgramme?(.init(sequence: 3, owner: original.owner, policyID: UUID(), age: child, sharing: false, grant: nil, choices: [], support: [], timeZoneID: TimeZone.current.identifier)); await settle()
        store.recorder.onHeart?(.init(value: 90, date: date)); builder.collectionCompletion?(true, nil); await settle()
        expect(store.heart == nil && !store.recordingBusy && workout.endCount > 0 && builder.discardCount > 0, "Known restriction cancels capture and rejects late callbacks")
        expect(store.journal?.policyRestricted == true && store.journal?.grant.age == original.age, "Restriction does not rewrite the captured age or owner")
        store.endLocalSet(); store.requestLocalFinish(); store.confirmFinish(); await settle()
        expect(store.lastCompleted?.completed.first?.reps == 4 && store.lastCompleted?.completionAllowsAdult == false, "Restriction preserves actual manual work without adult rewards")
    }

    @MainActor static func denialIsAttemptedOnceAndAnotherOwnerDoesNotDemoteOriginalJournal() async throws {
        HKHealthStore.authorization = .sharingDenied
        defer { HKHealthStore.authorization = .sharingAuthorized }
        let store = try fixture(), original = try fixture().programme!
        let own = store.programme!, date = Date()
        store.link.onProgramme?(.init(sequence: 2, owner: own.owner, policyID: own.policyID, age: own.age, sharing: true, grant: own.grant, choices: [.init(id: "today", date: date, plan: try .catalogue(exerciseID: "squat", sets: 1, target: 8, restSeconds: 3))], support: [], timeZoneID: TimeZone.current.identifier)); await settle()
        let requests = HKHealthStore.authorizationRequests.count
        store.startCached(choiceID: "today"); await settle(); store.record(); store.tick(); await settle()
        expect(HKHealthStore.authorizationRequests.count == requests + 1 && !store.recording, "Denied collection is attempted once; manual controls remain")
        store.beginLocalSet(); store.setLocalReps(2)
        store.link.onProgramme?(.init(sequence: 3, owner: original.owner, policyID: original.policyID, age: nil, sharing: false, grant: nil, choices: [], support: [], timeZoneID: TimeZone.current.identifier)); await settle()
        expect(store.journal?.policyRestricted == false && store.journal?.completionAllowsAdult == true, "An unrelated profile does not demote the original adult journal")
        store.endLocalSet(); store.requestLocalFinish(); store.confirmFinish(); await settle()
        expect(store.lastCompleted?.grant.owner == own.owner && store.link.workouts.isEmpty, "Other profile cannot adopt or receive original owner's workout")
    }

    @MainActor static func main() async {
        do {
            try await cachedWholeWorkoutAutomaticallyStartsOneRecorderWithoutPhoneSnapshot()
            try await cachedManualControlsSurviveRestartExpiryAndPrepareNextSetWithoutStartingIt()
            try await restrictivePolicyCancelsRecorderAndLateMetricsButPreservesManualOrigin()
            try await denialIsAttemptedOnceAndAnotherOwnerDoesNotDemoteOriginalJournal()
        }
        catch { expect(false, "Cached workflow fixture failed: \(error)") }
        setupReadsExistingMotionAvailabilityWithoutStartingSensors()
        await explicitPhonePauseDuringStartupSurvivesCollectionCompletion()
        await localStopFlushesItsBoundSessionBeforeClearingValues()
        await heartRateCallbacksCannotRegressOrInventAValidReading()
        await endingRequiresConfirmationAndRejectsChangedContext()
        await pendingCollectionDoesNotClaimRecordingOrSendTelemetry()
        await disconnectionKeepsEstablishedRecordingButNeverEnablesStaleCommands()
        await energyOnlyTelemetryPreservesTheCumulativeObservationAndResetsForANewSession()
        await olderEnergyCannotReplaceTheLatestEstimateButCorrectionsCanLowerIt()
        if failures > 0 { print("Watch store: \(failures) failures"); exit(1) }
        print("Watch store: 13 behavioral cases passed (SDK/link doubles; no device acceptance)")
    }
}

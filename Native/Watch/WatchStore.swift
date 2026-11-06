import SwiftUI
import WatchKit

@MainActor @Observable
final class WatchStore {
    var state = CompanionState()
    var reachable = false
    var status: String?
    var heart: SensorReading?
    var activeEnergy: ActiveEnergy?
    var acceleration: SensorReading?
    var rotation: SensorReading?
    private(set) var recordingState = WorkoutRecorder.State.idle
    private(set) var pendingFinish: CompanionCommand?
    private(set) var pendingLocalFinish = false
    private(set) var journal: WatchWorkoutJournal?
    private(set) var programme: WatchProgrammeTransport?
    private(set) var pendingWorkouts = 0
    private(set) var lastCompleted: WatchWorkoutJournal?
    var recording: Bool { recordingState.isRecording }
    var recordingBusy: Bool { recordingState.isBusy }
    let link = CompanionLink()
    let recorder = WorkoutRecorder()
    private let archive: WatchWorkoutArchive?
    var latestMotionWindow: WatchMotionWindow?
    var telemetryDeliveryStatus = WatchTelemetryDeliveryStatus()
    private var recordingSessionID: UUID?
    private var recordingOwner: WorkoutOwner?
    private var recordingPolicyID: UUID?
    private var scopedSnapshot: WatchScopedSnapshot?
    private var lastMotionPublication: Date?
    private var lastTransfer = Date.distantPast
    private var lastTick: Double
    private let now: () -> Date
    private let clock: () -> Double
    var telemetryStatusText: String {
        if let message = telemetryDeliveryStatus.message { return message }
        if pendingWorkouts > 0 { return "\(pendingWorkouts) completed workouts saved on Watch, waiting for their iPhone profile." }
        if telemetryDeliveryStatus.droppedSamples > 0 { return "\(telemetryDeliveryStatus.droppedSamples) older sensor samples removed at the queue limit." }
        return telemetryDeliveryStatus.pendingSamples > 0 ? "\(telemetryDeliveryStatus.pendingSamples) Watch samples waiting for iPhone." : "Watch data queue is up to date."
    }
    var canStartCached: Bool { journal == nil && programme?.sharing == true && programme?.grant?.permitsStart(at: now()) == true }
    var healthAllowed: Bool {
        guard let programme, programme.sharing, programme.age?.allowsHealthIntegration == true,
              programme.owner == recordingOwner, programme.policyID == recordingPolicyID else { return false }
        return journal?.policyRestricted != true
    }
    init(now: @escaping () -> Date = Date.init, archiveURL: URL? = nil,
         clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.now = now; self.clock = clock; lastTick = clock()
        let url = archiveURL ?? URL.applicationSupportDirectory.appendingPathComponent("Spottr/watch-workouts.json")
        do { archive = try WatchWorkoutArchive(url: url) }
        catch { archive = nil; status = "Saved workouts could not be opened. Keep this app installed and check storage." }
        reload()
        link.setSetupMotionAvailability(recorder.motionAvailable)
        link.onSnapshot = { [weak self] snapshot in
            Task { @MainActor in
                guard let self, self.journal == nil, self.scopedSnapshot == nil, snapshot.phase == .idle else { return }
                self.state.receive(snapshot, now: self.now())
            }
        }
        link.onScopedSnapshot = { [weak self] value in Task { @MainActor in self?.receive(value) } }
        link.onProgramme = { [weak self] value in Task { @MainActor in self?.receiveProgramme(value) } }
        link.onWorkoutAcknowledgement = { [weak self] value in
            Task { @MainActor in
                guard let self else { return }
                do { try self.archive?.acknowledge(id: value.id, owner: value.owner); self.reload() }
                catch { self.status = "Couldn’t save the iPhone acknowledgement. Your workout remains on Watch." }
            }
        }
        link.onReachability = { [weak self] reachable in
            Task { @MainActor in self?.reachable = reachable; self?.link.request(); self?.retryWorkouts(force: true) }
        }
        link.onTelemetryDeliveryStatus = { [weak self] status in Task { @MainActor in self?.telemetryDeliveryStatus = status } }
        telemetryDeliveryStatus = link.telemetryDeliveryStatus
        recorder.onMotionWindow = { [weak self] window in
            guard let self, self.healthAllowed else { return }
            self.latestMotionWindow = window; self.publishTelemetry(window: window); self.lastMotionPublication = self.now()
        }
        recorder.onHeart = { [weak self] reading in
            guard let self, self.healthAllowed, reading.heartRate(at: self.now()) != nil else { return }
            if let previous = self.heart, reading.date < previous.date { return }
            self.heart = reading
        }
        recorder.onEnergy = { [weak self] energy in
            guard let self, self.healthAllowed else { return }
            if let previous = self.activeEnergy, previous.recordingID == energy.recordingID, energy.asOf < previous.asOf { return }
            self.activeEnergy = energy
        }
        recorder.onMotion = { [weak self] acceleration, rotation in
            guard let self, self.healthAllowed else { return }
            self.acceleration = acceleration; self.rotation = rotation
        }
        recorder.onState = { [weak self] state in
            self?.recordingState = state
            if state == .saved { self?.record() }
        }
    }
    private func reload() { journal = archive?.active; programme = archive?.transport; pendingWorkouts = archive?.pendingCount ?? 0 }
    private func receiveProgramme(_ value: WatchProgrammeTransport) {
        do { try archive?.receive(value); reload() }
        catch { status = "Watch setup could not be saved. Your existing workout is retained."; return }
        guard programme?.sequence == value.sequence else { return }
        if recordingSessionID != nil && !healthAllowed { stopRecording(discard: true) }
        if scopedSnapshot?.owner != programme?.owner || scopedSnapshot?.policyID != programme?.policyID || programme?.sharing != true {
            scopedSnapshot = nil; state = CompanionState(); pendingFinish = nil
        }
        retryWorkouts(force: true)
    }
    private func receive(_ value: WatchScopedSnapshot) {
        guard journal == nil, let programme, programme.sharing, value.owner == programme.owner, value.policyID == programme.policyID else { return }
        let snapshot = value.snapshot, previous = state.snapshot
        guard snapshot.isFresh(at: now()), snapshot.sentAt > (previous?.sentAt ?? .distantPast) else { return }
        if previous?.sessionID != snapshot.sessionID { stopRecording() }
        scopedSnapshot = value; state.receive(snapshot, now: now())
        if pendingFinish?.sessionID != snapshot.sessionID || pendingFinish?.generation != snapshot.generation { pendingFinish = nil }
        if snapshot.phase == .paused, recordingBusy, recordingState != .paused, recordingState != .saving { recorder.pause(); publishTelemetry(); link.flushTelemetry() }
        if snapshot.phase == .active || snapshot.phase == .rest { recorder.resume(); record() }
        if snapshot.phase == .finished || snapshot.phase == .idle { stopRecording() }
    }
    func startCached(choiceID: String) {
        guard let archive else { return }
        do { try archive.start(choiceID: choiceID, at: now()); reload(); lastTick = clock(); status = nil; lastCompleted = nil; pendingFinish = nil; scopedSnapshot = nil; state = CompanionState(); record() }
        catch { status = "This workout cannot start yet. Check Watch sharing, setup and membership on iPhone, or sync saved workouts to free queue space." }
    }
    private func change(_ action: (inout WatchWorkoutJournal) throws -> Void) {
        guard let archive else { return }
        do { try archive.update(action); reload(); status = nil }
        catch { reload(); status = "Your last saved work is safe. This change could not be saved. Check storage and retry." }
    }
    func beginLocalSet() { change { try $0.beginSet() }; lastTick = clock(); record() }
    func setLocalReps(_ value: Int?) { change { try $0.setReps(value) } }
    func setEffort(_ value: SetEffort?) { change { try $0.effort(value) } }
    func pauseLocal() { tick(); change { $0.pause() }; recorder.pause() }
    func resumeLocal() { change { $0.resume() }; lastTick = clock(); if journal?.phase == .active { recorder.resume() } }
    func endLocalSet() { tick(); change { try $0.endSet() } }
    func nextLocalSet() { change { try $0.nextSet() }; lastTick = clock() }
    func requestLocalFinish() { if journal != nil { pendingLocalFinish = true } }
    func command(_ action: CompanionCommand.Action) {
        guard journal == nil, reachable, scopedSnapshot != nil, let command = state.command(action, now: now()) else { status = "Open Spottr on iPhone to reconnect."; return }
        if action == .finish { pendingFinish = command; return }
        send(command)
    }
    func cancelFinish() { pendingFinish = nil; pendingLocalFinish = false }
    func confirmFinish() {
        if pendingLocalFinish {
            pendingLocalFinish = false; tick(); stopRecording()
            let id = journal?.id
            change { $0.finish(at: now()) }
            lastCompleted = try? archive?.pendingWorkouts().first { $0.id == id }
            retryWorkouts(force: true); return
        }
        let pending = pendingFinish; pendingFinish = nil
        guard reachable, let pending, let current = state.command(.finish, now: now()), pending.sessionID == current.sessionID, pending.generation == current.generation else { return }
        send(current)
    }
    private func send(_ command: CompanionCommand) {
        link.command(command) { [weak self] received in Task { @MainActor in if !received { self?.status = "Couldn’t reach iPhone. Try again." } } }
    }
    func record() {
        guard !recordingBusy, let archive, let programme, programme.sharing, programme.age?.allowsHealthIntegration == true else { return }
        let id: UUID
        if let journal {
            guard !journal.policyRestricted, journal.grant.owner == programme.owner, journal.grant.policyID == programme.policyID else { return }
            id = journal.id
        } else {
            guard let scopedSnapshot, scopedSnapshot.allowsHealth, scopedSnapshot.snapshot.isFresh(at: now()), [.active, .rest].contains(scopedSnapshot.snapshot.phase) else { return }
            id = scopedSnapshot.snapshot.sessionID
        }
        do { guard try archive.markRecordingAttempt(id: id) else { return } }
        catch { status = "Health collection could not be prepared. Manual logging is available."; return }
        clearMetrics(); recordingSessionID = id; recordingOwner = programme.owner; recordingPolicyID = programme.policyID
        recorder.start()
    }
    private func clearMetrics() { heart = nil; acceleration = nil; rotation = nil; activeEnergy = nil; latestMotionWindow = nil; lastMotionPublication = nil }
    private func stopRecording(discard: Bool = false) {
        if discard { recorder.cancelForPolicy() }
        else { recorder.end(); publishTelemetry(); link.flushTelemetry() }
        recordingSessionID = nil; recordingOwner = nil; recordingPolicyID = nil; clearMetrics()
    }
    func stopLocalRecording() { stopRecording(); status = "Health collection stopped. Manual workout controls remain available." }
    private func publishTelemetry(window: WatchMotionWindow? = nil, includeEmpty: Bool = false) {
        guard let recordingSessionID, healthAllowed else { return }
        guard includeEmpty || heart != nil || activeEnergy != nil || acceleration != nil || rotation != nil || window != nil else { return }
        let sample = WatchTelemetry(sessionID: recordingSessionID, sentAt: now(), heartRate: heart, accelerationG: acceleration,
                                    rotationRadiansPerSecond: rotation, activeEnergy: activeEnergy, motionWindow: window)
        if journal?.id == recordingSessionID {
            if heart != nil || activeEnergy != nil || acceleration != nil || rotation != nil || window != nil {
                do { try archive?.appendTelemetry(sample) }
                catch { status = "Some sensor samples could not be saved. Your actual sets remain saved." }
            }
        } else { link.telemetryBatch([sample]); link.telemetry(sample) }
    }
    private func retryWorkouts(force: Bool = false) {
        guard force || now().timeIntervalSince(lastTransfer) >= 30 else { return }
        lastTransfer = now()
        guard let owner = programme?.owner else { return }
        do { for value in try archive?.pendingWorkouts(owner: owner) ?? [] { link.sendWorkout(value) } }
        catch { status = "Completed workouts could not be read. They remain on Watch; check storage and retry." }
    }
    func tick() {
        let time = clock(), delta = max(0, time - lastTick); lastTick = time
        if journal != nil {
            change { $0.advance(seconds: delta) }
            if let journal, journal.restReady, !journal.policyRestricted, journal.index + 1 < journal.items.count {
                change { try $0.nextSet() }; WKInterfaceDevice.current().play(.click)
            }
        }
        retryWorkouts(); link.retryTelemetry()
        guard recordingState == .recording else { return }
        if let lastMotionPublication, now().timeIntervalSince(lastMotionPublication) < 1.2 { return }
        publishTelemetry(includeEmpty: true)
    }
}

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
    var recording: Bool { recordingState.isRecording }
    var recordingBusy: Bool { recordingState.isBusy }
    let link = CompanionLink()
    let recorder = WorkoutRecorder()
    var latestMotionWindow: WatchMotionWindow?
    var telemetryDeliveryStatus = WatchTelemetryDeliveryStatus()
    private var recordingSessionID: UUID?
    private var lastMotionPublication: Date?
    private let now: () -> Date
    var telemetryStatusText: String {
        if let message = telemetryDeliveryStatus.message { return message }
        if telemetryDeliveryStatus.droppedSamples > 0 {
            return "Queue limit reached: \(telemetryDeliveryStatus.droppedSamples) samples removed from local storage."
        }
        return telemetryDeliveryStatus.pendingSamples > 0
            ? "\(telemetryDeliveryStatus.pendingSamples) Watch samples waiting for iPhone."
            : "Watch data queue is up to date."
    }

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
        link.setSetupMotionAvailability(recorder.motionAvailable)
        link.onSnapshot = { [weak self] snapshot in Task { @MainActor in self?.receive(snapshot) } }
        link.onReachability = { [weak self] reachable in
            Task { @MainActor in self?.reachable = reachable; self?.link.request() }
        }
        link.onTelemetryDeliveryStatus = { [weak self] status in
            Task { @MainActor in self?.telemetryDeliveryStatus = status }
        }
        telemetryDeliveryStatus = link.telemetryDeliveryStatus
        recorder.onMotionWindow = { [weak self] window in
            guard let self else { return }
            self.latestMotionWindow = window
            self.publishTelemetry(window: window)
            self.lastMotionPublication = self.now()
        }
        recorder.onHeart = { [weak self] reading in
            guard let self, reading.heartRate(at: self.now()) != nil else { return }
            if let previous = self.heart, reading.date < previous.date { return }
            self.heart = reading
        }
        recorder.onEnergy = { [weak self] energy in
            guard let self else { return }
            if let previous = self.activeEnergy, previous.recordingID == energy.recordingID,
               energy.asOf < previous.asOf { return }
            self.activeEnergy = energy
        }
        recorder.onMotion = { [weak self] acceleration, rotation in self?.acceleration = acceleration; self?.rotation = rotation }
        recorder.onState = { [weak self] state in
            self?.recordingState = state
            self?.status = state.message
        }
    }
    private func receive(_ snapshot: CompanionSnapshot) {
        let previous = state.snapshot
        let receivedAt = now()
        guard snapshot.isFresh(at: receivedAt), snapshot.sentAt > (previous?.sentAt ?? .distantPast) else { return }
        state.receive(snapshot, now: receivedAt)
        if pendingFinish?.sessionID != snapshot.sessionID || pendingFinish?.generation != snapshot.generation { pendingFinish = nil }
        if previous?.sessionID != snapshot.sessionID { stopRecording() }
        if snapshot.configured == nil, snapshot.reps > (previous?.reps ?? 0) { WKInterfaceDevice.current().play(.click) }
        if snapshot.phase == .paused, recordingBusy, recordingState != .paused, recordingState != .saving {
            recorder.pause(); publishTelemetry(); link.flushTelemetry()
        }
        if snapshot.phase == .active || snapshot.phase == .rest { recorder.resume() }
        if snapshot.phase == .finished || snapshot.phase == .idle { stopRecording() }
    }
    func command(_ action: CompanionCommand.Action) {
        guard reachable, let command = state.command(action, now: now()) else { status = "Open Spottr on iPhone to reconnect."; return }
        if action == .finish { pendingFinish = command; return }
        send(command)
    }
    func cancelFinish() { pendingFinish = nil }
    func confirmFinish() {
        let pending = pendingFinish
        pendingFinish = nil
        guard reachable, let pending, let current = state.command(.finish, now: now()),
              pending.sessionID == current.sessionID, pending.generation == current.generation else { return }
        send(current)
    }
    private func send(_ command: CompanionCommand) {
        link.command(command) { [weak self] received in
            Task { @MainActor in
                if !received { self?.status = "Couldn’t reach iPhone. Try again." }
            }
        }
    }
    func record() {
        guard let snapshot = state.snapshot, snapshot.isFresh(at: now()), [.active, .rest].contains(snapshot.phase) else { return }
        guard !recordingBusy else { return }
        heart = nil; acceleration = nil; rotation = nil; activeEnergy = nil
        recordingSessionID = snapshot.sessionID; lastMotionPublication = nil; latestMotionWindow = nil
        recorder.start()
    }
    private func stopRecording() {
        recorder.end()
        publishTelemetry(); link.flushTelemetry()
        recordingSessionID = nil; lastMotionPublication = nil; latestMotionWindow = nil
        heart = nil; acceleration = nil; rotation = nil; activeEnergy = nil
    }
    func stopLocalRecording() {
        stopRecording()
        status = "Watch recording stopped. Your iPhone session is unchanged."
    }
    private func publishTelemetry(window: WatchMotionWindow? = nil, includeEmpty: Bool = false) {
        guard let recordingSessionID else { return }
        guard includeEmpty || heart != nil || activeEnergy != nil || acceleration != nil || rotation != nil || window != nil else { return }
        let sample = WatchTelemetry(sessionID: recordingSessionID, sentAt: now(), heartRate: heart,
                                    accelerationG: acceleration, rotationRadiansPerSecond: rotation,
                                    activeEnergy: activeEnergy, motionWindow: window)
        link.telemetryBatch([sample])
        link.telemetry(sample)
    }
    func tick() {
        link.retryTelemetry()
        guard recordingState == .recording else { return }
        if let lastMotionPublication, now().timeIntervalSince(lastMotionPublication) < 1.2 { return }
        publishTelemetry(includeEmpty: true)
    }
}

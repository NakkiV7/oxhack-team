import SwiftUI
import WatchKit

@MainActor @Observable
final class WatchStore {
    var state = CompanionState()
    var reachable = false
    var status: String?
    var heart: SensorReading?
    var acceleration: SensorReading?
    var rotation: SensorReading?
    private(set) var recordingState = WorkoutRecorder.State.idle
    private(set) var pendingFinish: CompanionCommand?
    var recording: Bool { recordingState.isRecording }
    var recordingBusy: Bool { recordingState.isBusy }
    let link = CompanionLink()
    let recorder = WorkoutRecorder()
    private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
        link.onSnapshot = { [weak self] snapshot in Task { @MainActor in self?.receive(snapshot) } }
        link.onReachability = { [weak self] reachable in
            Task { @MainActor in self?.reachable = reachable; self?.link.request() }
        }
        recorder.onHeart = { [weak self] reading in self?.heart = reading }
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
        if snapshot.phase == .paused { recorder.pause() }
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
        heart = nil; acceleration = nil; rotation = nil
        recorder.start()
    }
    private func stopRecording() {
        recorder.end(); heart = nil; acceleration = nil; rotation = nil
    }
    func tick() {
        guard let snapshot = state.snapshot, snapshot.isFresh(at: now()) else { recorder.pause(); return }
        guard recordingState == .recording else { return }
        link.telemetry(.init(sessionID: snapshot.sessionID, heartRate: heart, accelerationG: acceleration, rotationRadiansPerSecond: rotation))
    }
}

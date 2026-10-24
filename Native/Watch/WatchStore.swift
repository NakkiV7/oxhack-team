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
    var recording = false
    let link = CompanionLink()
    let recorder = WorkoutRecorder()

    init() {
        link.onSnapshot = { [weak self] snapshot in Task { @MainActor in self?.receive(snapshot) } }
        link.onReachability = { [weak self] reachable in
            Task { @MainActor in self?.reachable = reachable; self?.link.request() }
        }
        recorder.onHeart = { [weak self] reading in self?.heart = reading }
        recorder.onMotion = { [weak self] acceleration, rotation in self?.acceleration = acceleration; self?.rotation = rotation }
        recorder.onStatus = { [weak self] status in self?.status = status }
        recorder.onRecording = { [weak self] recording in self?.recording = recording }
    }
    private func receive(_ snapshot: CompanionSnapshot) {
        let previous = state.snapshot
        state.receive(snapshot)
        guard state.snapshot?.sentAt == snapshot.sentAt else { return }
        if previous?.sessionID != snapshot.sessionID, recording { stopRecording() }
        if snapshot.configured == nil, snapshot.reps > (previous?.reps ?? 0) { WKInterfaceDevice.current().play(.click) }
        if snapshot.phase == .paused { recorder.pause() }
        if snapshot.phase == .active || snapshot.phase == .rest { recorder.resume() }
        if snapshot.phase == .finished || snapshot.phase == .idle { stopRecording() }
    }
    func command(_ action: CompanionCommand.Action) {
        guard reachable, let command = state.command(action) else { status = "Open Spottr on iPhone to reconnect."; return }
        link.command(command) { [weak self] received in
            Task { @MainActor in
                if !received { self?.status = "Couldn’t reach iPhone. Try again." }
            }
        }
    }
    func record() {
        guard let snapshot = state.snapshot, snapshot.isFresh(at: Date()), [.active, .rest].contains(snapshot.phase) else { return }
        recording = true; status = "Allow workout access"; recorder.start()
    }
    private func stopRecording() {
        guard recording else { return }
        recorder.end(); recording = false; heart = nil; acceleration = nil; rotation = nil
    }
    func tick() {
        guard let snapshot = state.snapshot, snapshot.isFresh(at: Date()) else { recorder.pause(); return }
        guard recording else { return }
        link.telemetry(.init(sessionID: snapshot.sessionID, heartRate: heart, accelerationG: acceleration, rotationRadiansPerSecond: rotation))
    }
}

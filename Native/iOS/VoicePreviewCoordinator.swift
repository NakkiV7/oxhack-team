import AVFoundation
import Observation
import UIKit

@MainActor @Observable final class VoicePreviewCoordinator {
    let preferences: RemoteVoicePlayback
    private let playback: RemoteVoicePlayback
    private let canPreview: () -> Bool
    private let permitsSelection: () -> Bool
    private(set) var isPlaying = false
    private(set) var enabled = true
    private(set) var message: String?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    var preference: VoiceCoachPreference { preferences.preference }
    init(preferences: RemoteVoicePlayback, playback: RemoteVoicePlayback? = nil,
         permitsSelection: @escaping () -> Bool = { true }, canPreview: @escaping () -> Bool) {
        self.preferences = preferences
        self.playback = playback ?? RemoteVoicePlayback(offlineOnly: true, defaults: preferences.preferencesDefaults, gentleOnly: preferences.gentleOnly)
        self.permitsSelection = permitsSelection; self.canPreview = canPreview
        self.playback.onFinish = { [weak self] _ in self?.isPlaying = false }
        for name in [AVAudioSession.routeChangeNotification, AVAudioSession.interruptionNotification, UIApplication.didEnterBackgroundNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.stop() }
            })
        }
    }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    func select(_ voice: VoiceCoachPreference, tone: TrainerTone) {
        stop(); message = nil
        guard permitsSelection() else { message = "Reopen this profile to choose your coaching voice."; return }
        do { try preferences.configureSelection(voice, tone: tone) }
        catch { message = "Choose a voice available for this profile."; return }
        guard enabled else { return }
        guard canPreview() else { message = "Your choice is saved. Listen to a sample after your workout."; return }
        do {
            try playback.previewSelection(voice, tone: tone)
            if let error = playback.errorMessage { message = error; playback.stop(); return }
            isPlaying = true
        } catch {
            playback.stop()
            message = "This recording could not play. Tap the voice to retry, or choose Local voice."
        }
    }
    func setEnabled(_ enabled: Bool) { self.enabled = enabled; if !enabled { stop() } }
    func stop() { playback.stop(); isPlaying = false }
}

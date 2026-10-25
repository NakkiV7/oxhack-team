import AVFoundation
import Foundation

enum DemoVoiceRecoveryReason { case endedSet, fatigue }

@MainActor
final class DemoVoicePlayback: VoicePlayback {
    var onFinish: ((UUID) -> Void)?
    private let local: VoicePlayback
    private let makeAudio: @MainActor (String) throws -> VoiceAudioOutput
    private let recoveryReason: @MainActor (VoiceCue) -> DemoVoiceRecoveryReason?
    private let uptime: () -> Double
    private var output: VoiceAudioOutput?
    private var active: (id: UUID, token: UUID)?
    private var localCueID: UUID?
    private var variant = 0

    static func isAvailable(preview: Bool, coach: VoiceCoachPreference) -> Bool {
        preview && coach == .arnold
    }

    static func clipName(reason: CoachingReason?, priority: CoachingPriority, variant: Int,
                         recovery: DemoVoiceRecoveryReason? = nil) -> String? {
        if priority == .rest, reason == nil, recovery != nil { return "recovery" }
        guard priority == .pacing else { return nil }
        let suffix = variant.isMultiple(of: 2) ? "1" : "2"
        switch reason {
        case .steadyRhythm: return "positive-\(suffix)"
        case .slowerRep: return "slower-\(suffix)"
        default: return nil
        }
    }

    init(local: VoicePlayback? = nil, makeAudio: (@MainActor (String) throws -> VoiceAudioOutput)? = nil,
         recoveryReason: @escaping @MainActor (VoiceCue) -> DemoVoiceRecoveryReason? = { _ in nil },
         uptime: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.local = local ?? LocalVoicePlayback()
        self.makeAudio = makeAudio ?? { try DemoBundledAudioOutput(name: $0) }
        self.recoveryReason = recoveryReason
        self.uptime = uptime
        self.local.onFinish = { [weak self] id in
            guard let self, self.localCueID == id, let active = self.active else { return }
            self.complete(token: active.token)
        }
    }

    func speak(_ cue: VoiceCue) {
        stop()
        let token = UUID()
        active = (cue.id, token)
        if cue.kind == .coaching(.stop) || cue.reason == .discomfort {
            localCueID = cue.id
            local.speak(cue)
            return
        }
        let now = uptime()
        guard now.isFinite, cue.issuedAt.isFinite, cue.issuedAt <= now,
              let deadline = cue.expiresAt, deadline.isFinite, deadline > now,
              !cue.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              cue.text.count <= 500 else { complete(token: token); return }
        guard case .coaching(let priority) = cue.kind,
              let name = Self.clipName(reason: cue.reason, priority: priority, variant: variant, recovery: recoveryReason(cue)) else {
            localCueID = cue.id
            local.speak(cue)
            return
        }
        variant = variant == 0 ? 1 : 0
        do {
            let player = try makeAudio(name)
            guard uptime().isFinite, uptime() < deadline else { complete(token: token); return }
            player.onFinish = { [weak self] in self?.complete(token: token) }
            output = player
            guard player.play() else { complete(token: token); return }
        } catch { complete(token: token) }
    }

    func stop() {
        active = nil
        output?.onFinish = nil
        output?.stop()
        output = nil
        if localCueID != nil {
            localCueID = nil
            local.stop()
        }
    }

    private func complete(token: UUID) {
        guard let current = active, current.token == token else { return }
        stop()
        onFinish?(current.id)
    }
}

@MainActor
private final class DemoBundledAudioOutput: NSObject, VoiceAudioOutput, AVAudioPlayerDelegate {
    var onFinish: (() -> Void)?
    private let player: AVAudioPlayer

    init(name: String, bundle: Bundle = .main) throws {
        guard ["positive-1", "positive-2", "slower-1", "slower-2", "recovery"].contains(name),
              let url = bundle.url(forResource: name, withExtension: "mp3", subdirectory: "DemoVoice/arnold") else {
            throw CocoaError(.fileNoSuchFile)
        }
        player = try AVAudioPlayer(contentsOf: url)
        super.init()
        guard player.format.sampleRate == 22_050, player.duration.isFinite,
              player.duration > 0, player.duration <= 10 else { throw CocoaError(.fileReadCorruptFile) }
        player.delegate = self
        player.prepareToPlay()
    }

    func play() -> Bool { player.play() }
    func stop() { player.stop() }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        finished(ObjectIdentifier(player))
    }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        finished(ObjectIdentifier(player))
    }
    private nonisolated func finished(_ identity: ObjectIdentifier) {
        Task { @MainActor [weak self] in
            guard let self, ObjectIdentifier(player) == identity else { return }
            onFinish?()
        }
    }
}

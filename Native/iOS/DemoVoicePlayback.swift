import AVFoundation
import Foundation
import Observation

enum DemoVoiceRecoveryReason { case endedSet, fatigue }

@MainActor
final class DemoVoicePlayback: VoicePlayback {
    var onFinish: ((UUID) -> Void)?
    private let local: VoicePlayback
    private let makeAudio: @MainActor (String) throws -> VoiceAudioOutput
    private let recoveryReason: @MainActor (VoiceCue) -> DemoVoiceRecoveryReason?
    private let prepareAudioSession: @MainActor () throws -> Void
    private let releaseAudioSession: @MainActor () -> Void
    private let uptime: () -> Double
    private var output: VoiceAudioOutput?
    private var active: (id: UUID, token: UUID)?
    private var localCueID: UUID?
    private var variants: [String: Int] = [:]
    private var audioSessionActive = false

    static func isAvailable(preview: Bool, coach: VoiceCoachPreference) -> Bool {
        preview && coach == .arnold
    }

    static func clipName(reason: CoachingReason?, priority: CoachingPriority, variant: Int,
                         recovery: DemoVoiceRecoveryReason? = nil) -> String? {
        let names = clipNames(reason: reason, priority: priority, recovery: recovery)
        guard !names.isEmpty else { return nil }
        return names[max(0, variant) % names.count]
    }

    private static func clipNames(reason: CoachingReason?, priority: CoachingPriority,
                                  recovery: DemoVoiceRecoveryReason?) -> [String] {
        if priority == .stop { return ["stop"] }
        if priority == .form, reason == .tracking { return ["tracking"] }
        if priority == .form, reason == .alignment { return ["alignment"] }
        if priority == .pacing, reason == .targetReached { return ["target"] }
        if priority == .rest, reason == .restReminder { return ["rest"] }
        if priority == .rest, reason == .workoutCompleted { return ["completion"] }
        if priority == .rest, reason == nil, recovery != nil { return ["recovery", "recovery-2"] }
        guard priority == .pacing else { return [] }
        switch reason {
        case .steadyRhythm: return ["positive-1", "positive-2", "positive-3", "positive-4", "positive-5"]
        case .slowerRep: return ["slower-1", "slower-2", "slower-3", "slower-4"]
        default: return []
        }
    }

    init(local: VoicePlayback? = nil, makeAudio: (@MainActor (String) throws -> VoiceAudioOutput)? = nil,
         recoveryReason: @escaping @MainActor (VoiceCue) -> DemoVoiceRecoveryReason? = { _ in nil },
         prepareAudioSession: (@MainActor () throws -> Void)? = nil,
         releaseAudioSession: (@MainActor () -> Void)? = nil,
         uptime: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.local = local ?? LocalVoicePlayback()
        self.makeAudio = makeAudio ?? { try DemoBundledAudioOutput(name: $0) }
        self.recoveryReason = recoveryReason
        self.prepareAudioSession = prepareAudioSession ?? {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
            try session.setActive(true)
        }
        self.releaseAudioSession = releaseAudioSession ?? {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
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
        let safety = cue.kind == .coaching(.stop) || cue.reason == .discomfort
        let now = uptime()
        let deadline = safety ? Double.infinity : (cue.expiresAt ?? .nan)
        guard safety || (now.isFinite && cue.issuedAt.isFinite && cue.issuedAt <= now &&
              deadline.isFinite && deadline > now &&
              !cue.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
              cue.text.count <= 500) else { complete(token: token); return }
        guard case .coaching(let priority) = cue.kind else { complete(token: token); return }
        let names = safety ? ["stop"] : Self.clipNames(reason: cue.reason, priority: priority, recovery: recoveryReason(cue))
        guard let group = names.first else {
            complete(token: token)
            return
        }
        let index = variants[group, default: 0] % names.count
        let name = names[index]
        variants[group] = (index + 1) % names.count
        do {
            let player = try makeAudio(name)
            guard safety || (uptime().isFinite && uptime() < deadline) else { complete(token: token); return }
            try prepareAudioSession()
            audioSessionActive = true
            guard safety || (uptime().isFinite && uptime() < deadline) else { complete(token: token); return }
            player.onFinish = { [weak self] in self?.complete(token: token) }
            output = player
            guard player.play() else { throw CocoaError(.fileReadUnknown) }
        } catch {
            if safety {
                output?.onFinish = nil
                output?.stop()
                output = nil
                localCueID = cue.id
                local.speak(cue)
            } else { complete(token: token) }
        }
    }

    func stop() {
        active = nil
        output?.onFinish = nil
        output?.stop()
        output = nil
        if audioSessionActive {
            audioSessionActive = false
            releaseAudioSession()
        }
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
        guard ["positive-1", "positive-2", "positive-3", "positive-4", "slower-1", "slower-2", "slower-3", "recovery", "recovery-2", "positive-5", "slower-4", "completion", "tracking", "alignment", "target", "rest", "stop"].contains(name),
              let url = bundle.url(forResource: name, withExtension: "mp3", subdirectory: "DemoVoice/arnold") else {
            throw CocoaError(.fileNoSuchFile)
        }
        player = try AVAudioPlayer(contentsOf: url)
        super.init()
        guard player.format.sampleRate == 22_050, player.duration.isFinite,
              player.duration > 0, player.duration <= 10 else { throw CocoaError(.fileReadCorruptFile) }
        player.delegate = self
        player.volume = 1
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

/// A playable clip for the rep voice; tests substitute a fake.
@MainActor protocol RepVoiceOutput: AnyObject {
    var onFinish: (() -> Void)? { get set }
    func play() -> Bool
    func stop()
}

/// Plays `RepVoicePlan` lines from the bundled Arnold or Goggins rep clips (offline, no gateway). Silent unless a coach is
/// chosen and the workout's Voice feedback is on; `cancel()` on pause, stop, voice off or background.
@MainActor @Observable
final class RepVoicePlayer {
    static let defaultsKey = "voice.repCounterCoach"
    /// The rep counter voice, or nil for off. Defaults to Arnold; `choose(_:)` remembers a person's choice.
    var coach: RepVoicePlan.Coach? { didSet { if coach != oldValue { cancel() } } }
    /// Clips started, newest last (for tests and diagnostics).
    @ObservationIgnored private(set) var started: [String] = []
    @ObservationIgnored private var plan = RepVoicePlan()
    @ObservationIgnored private var output: RepVoiceOutput?
    @ObservationIgnored private var audioSessionActive = false
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let uptime: () -> Double
    @ObservationIgnored private let makeOutput: @MainActor (String, String) throws -> RepVoiceOutput
    @ObservationIgnored private let usesAudioSession: Bool

    init(defaults: UserDefaults = .standard, uptime: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime },
         makeOutput: (@MainActor (String, String) throws -> RepVoiceOutput)? = nil) {
        self.defaults = defaults; self.uptime = uptime
        self.usesAudioSession = makeOutput == nil
        self.makeOutput = makeOutput ?? { try RepClipOutput(name: $0, folder: $1, bundle: .main) }
        let saved = defaults.string(forKey: Self.defaultsKey)
        coach = saved == "off" ? nil : RepVoicePlan.Coach(rawValue: saved ?? "") ?? .arnold
    }

    /// A person's choice from the coach voice sheet; remembered across launches.
    func choose(_ coach: RepVoicePlan.Coach?) {
        self.coach = coach
        defaults.set(coach?.rawValue ?? "off", forKey: Self.defaultsKey)
    }

    var isPlaying: Bool { output != nil }

    func start() { guard coach != nil else { return }; plan.start(at: uptime()); pump() }
    func rep(_ number: Int, clean: Bool) { guard coach != nil else { return }; plan.rep(number, clean: clean, at: uptime()); pump() }
    func closing() { guard coach != nil else { return }; plan.closing(at: uptime()); pump() }

    /// A form, pacing or stop cue is about to speak: stop rep lines so the cue is heard on its own.
    func yield() {
        plan.clear()
        output?.onFinish = nil; output?.stop(); output = nil
    }

    func cancel() {
        yield()
        releaseAudioSession()
    }

    private func pump() {
        guard output == nil, let coach else { return }
        while let line = plan.next(at: uptime()) {
            guard let clip = try? makeOutput(line.clip, coach.folder) else { continue }
            if usesAudioSession, !audioSessionActive {
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
                    try session.setActive(true)
                    audioSessionActive = true
                } catch { return }
            }
            clip.onFinish = { [weak self] in
                guard let self else { return }
                self.output = nil
                self.pump()
            }
            output = clip
            started.append(line.clip)
            if clip.play() { return }
            output = nil
        }
        releaseAudioSession()
    }

    private func releaseAudioSession() {
        guard audioSessionActive else { return }
        audioSessionActive = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

@MainActor
private final class RepClipOutput: NSObject, RepVoiceOutput, AVAudioPlayerDelegate {
    var onFinish: (() -> Void)?
    private let player: AVAudioPlayer

    init(name: String, folder: String, bundle: Bundle) throws {
        guard RepVoicePlan.allClips.contains(name),
              let url = bundle.url(forResource: name, withExtension: "mp3", subdirectory: folder) else { throw CocoaError(.fileNoSuchFile) }
        player = try AVAudioPlayer(contentsOf: url)
        super.init()
        guard player.format.sampleRate == 22_050, player.duration.isFinite, player.duration > 0, player.duration <= 10 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        player.delegate = self
        player.volume = 1
    }

    func play() -> Bool { player.play() }
    func stop() { player.stop() }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { finished(ObjectIdentifier(player)) }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) { finished(ObjectIdentifier(player)) }
    private nonisolated func finished(_ identity: ObjectIdentifier) {
        Task { @MainActor [weak self] in
            guard let self, ObjectIdentifier(player) == identity else { return }
            onFinish?()
        }
    }
}

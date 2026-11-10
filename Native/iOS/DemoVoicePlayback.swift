import AVFoundation
import Foundation
import Observation

enum DemoVoiceRecoveryReason { case endedSet, fatigue }

@MainActor
final class DemoVoicePlayback: VoicePlayback {
    var onFinish: ((UUID) -> Void)?
    var onInterrupt: (() -> Void)?
    private var interruptionObserver: NSObjectProtocol?
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
        preview && coach == .maya
    }

    static func clipName(reason: CoachingReason?, priority: CoachingPriority, variant: Int,
                         recovery: DemoVoiceRecoveryReason? = nil) -> String? {
        let names = clipNames(reason: reason, priority: priority, recovery: recovery)
        guard !names.isEmpty else { return nil }
        return names[max(0, variant) % names.count]
    }

    private static func clipNames(reason: CoachingReason?, priority: CoachingPriority,
                                  recovery: DemoVoiceRecoveryReason?) -> [String] {
        let selected: CoachingReason
        switch (priority, reason) {
        case (.stop, _): selected = .discomfort
        case (.form, .tracking?): selected = .tracking
        case (.form, .alignment?): selected = .alignment
        case (.pacing, .targetReached?): selected = .targetReached
        case (.pacing, .steadyRhythm?): selected = .steadyRhythm
        case (.pacing, .slowerRep?): selected = .slowerRep
        case (.rest, .restReminder?): selected = .restReminder
        case (.rest, .workoutCompleted?): selected = .workoutCompleted
        case (.rest, nil) where recovery != nil: selected = .restReminder
        default: return []
        }
        return TrainerCueLibrary.lines(reason: selected, tone: .encouraging).indices.map { "\(selected.rawValue)-\($0 + 1)" }
    }

    init(local: VoicePlayback? = nil, tone: TrainerTone = .encouraging, makeAudio: (@MainActor (String) throws -> VoiceAudioOutput)? = nil,
         recoveryReason: @escaping @MainActor (VoiceCue) -> DemoVoiceRecoveryReason? = { _ in nil },
         prepareAudioSession: (@MainActor () throws -> Void)? = nil,
         releaseAudioSession: (@MainActor () -> Void)? = nil,
         uptime: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.local = local ?? LocalVoicePlayback()
        self.makeAudio = makeAudio ?? { try DemoBundledAudioOutput(name: $0, tone: tone) }
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
        interruptionObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification,
            object: nil, queue: .main) { [weak self] notification in
            guard (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue else { return }
            Task { @MainActor [weak self] in self?.stop(); self?.onInterrupt?() }
        }
    }

    deinit { if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) } }

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
        let names = safety ? ["discomfort-1"] : Self.clipNames(reason: cue.reason, priority: priority, recovery: recoveryReason(cue))
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

    init(name: String, tone: TrainerTone, bundle: Bundle = .main) throws {
        guard let url = bundle.url(forResource: name, withExtension: "mp3", subdirectory: "DemoVoice/maya/\(tone.rawValue)") else {
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

/// Plays optional `RepVoicePlan` lines using the device speaking voice. Silent unless device voice is
/// chosen and the workout's Voice feedback is on; `cancel()` on pause, stop, voice off or background.
@MainActor @Observable
final class RepVoicePlayer {
    static let defaultsKey = "voice.repCounterCoach"
    /// The explicitly chosen rep counter voice, or nil for off.
    var coach: RepVoicePlan.Coach? { didSet { if coach != oldValue { cancel(); onInterrupt?() } } }
    /// Clips started, newest last (for tests and diagnostics).
    @ObservationIgnored private(set) var started: [String] = []
    @ObservationIgnored private var plan = RepVoicePlan()
    @ObservationIgnored private var output: RepVoiceOutput?
    @ObservationIgnored private var audioSessionActive = false
    @ObservationIgnored private var outputToken: UUID?
    @ObservationIgnored private var afterCurrent: (() -> Void)?
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?
    @ObservationIgnored var onInterrupt: (() -> Void)?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let uptime: () -> Double
    @ObservationIgnored private let makeOutput: @MainActor (String, String) throws -> RepVoiceOutput
    @ObservationIgnored private let usesAudioSession: Bool

    init(defaults: UserDefaults = .standard, uptime: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime },
         makeOutput: (@MainActor (String, String) throws -> RepVoiceOutput)? = nil) {
        self.defaults = defaults; self.uptime = uptime
        self.usesAudioSession = makeOutput == nil
        self.makeOutput = makeOutput ?? { _, text in RepDeviceVoiceOutput(text: text) }
        let saved = defaults.string(forKey: Self.defaultsKey)
        coach = saved.flatMap(RepVoicePlan.Coach.init(rawValue:))
        defaults.set(coach?.rawValue ?? "off", forKey: Self.defaultsKey)
        interruptionObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification,
            object: nil, queue: .main) { [weak self] notification in
            guard (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue else { return }
            Task { @MainActor [weak self] in self?.cancel(); self?.onInterrupt?() }
        }
    }

    deinit { if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) } }

    /// A person's choice from the coach voice sheet; remembered across launches.
    func choose(_ coach: RepVoicePlan.Coach?) {
        self.coach = coach
        defaults.set(coach?.rawValue ?? "off", forKey: Self.defaultsKey)
    }

    var isPlaying: Bool { output != nil }

    func start() { guard coach != nil else { return }; plan.start(at: uptime()); pump() }
    func rep(_ number: Int, clean: Bool) { guard coach != nil else { return }; plan.rep(number, clean: clean, at: uptime()); pump() }
    func closing() { guard coach != nil else { return }; plan.closing(at: uptime()); pump() }

    /// Retain the current sentence, discard pending counts, then hand off the shared session.
    func finishCurrent(then action: (() -> Void)?) {
        plan.clear()
        afterCurrent = action
        if output == nil {
            afterCurrent = nil
            releaseAudioSession()
            action?()
        }
    }

    /// An immediate action is about to take over the shared audio session.
    func yield() {
        plan.clear()
        afterCurrent = nil
        outputToken = nil
        output?.onFinish = nil; output?.stop(); output = nil
        releaseAudioSession()
    }

    func cancel() {
        yield()
        releaseAudioSession()
    }

    private func pump() {
        guard output == nil, coach != nil else { return }
        while let line = plan.next(at: uptime()) {
            guard let clip = try? makeOutput(line.clip, Self.spokenText(for: line.clip)) else { continue }
            if usesAudioSession, !audioSessionActive {
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
                    try session.setActive(true)
                    audioSessionActive = true
                } catch { return }
            }
            let token = UUID()
            outputToken = token
            clip.onFinish = { [weak self] in
                guard let self, self.outputToken == token else { return }
                self.outputToken = nil
                self.output?.onFinish = nil
                self.output = nil
                if let action = self.afterCurrent {
                    self.afterCurrent = nil
                    self.releaseAudioSession()
                    action()
                } else { self.pump() }
            }
            output = clip
            started.append(line.clip)
            if clip.play() { return }
            clip.onFinish = nil; clip.stop()
            outputToken = nil; output = nil
        }
        releaseAudioSession()
    }

    private static func spokenText(for clip: String) -> String {
        if clip == "start" { return "Begin when you are ready." }
        if clip.hasPrefix("count-"), let count = Int(clip.suffix(2)), (1...30).contains(count) { return String(count) }
        if clip.hasPrefix("motivate-"), let number = Int(clip.suffix(1)), (1...7).contains(number) {
            return TrainerCueLibrary.lines(reason: .steadyRhythm, tone: .gentle)[number - 1]
        }
        if clip.hasPrefix("closing-"), let number = Int(clip.suffix(1)), (1...3).contains(number) {
            return ["Set complete. Take a comfortable rest.", "Your reps are saved. Recover at your pace.", "Well done. Rest before continuing."][number - 1]
        }
        return ""
    }

    private func releaseAudioSession() {
        guard audioSessionActive else { return }
        audioSessionActive = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

@MainActor
private final class RepDeviceVoiceOutput: NSObject, RepVoiceOutput, AVSpeechSynthesizerDelegate {
    var onFinish: (() -> Void)?
    private let synthesizer = AVSpeechSynthesizer()
    private let utterance: AVSpeechUtterance
    private var active = false

    init(text: String) {
        utterance = AVSpeechUtterance(string: text)
        super.init()
        synthesizer.usesApplicationAudioSession = true
        synthesizer.delegate = self
    }
    func play() -> Bool {
        active = true
        synthesizer.speak(utterance)
        return true
    }
    func stop() {
        active = false
        synthesizer.stopSpeaking(at: .immediate)
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        completed(ObjectIdentifier(utterance))
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        completed(ObjectIdentifier(utterance))
    }
    private nonisolated func completed(_ id: ObjectIdentifier) {
        Task { @MainActor [weak self] in
            guard let self, active, ObjectIdentifier(utterance) == id else { return }
            active = false
            onFinish?()
        }
    }
}

import Foundation

@MainActor
final class CoachingVoiceBridge {
    private let controller: VoiceCuePlaybackController
    private let uptime: () -> Double
    private var latest: (context: VoiceCueContext, event: VoiceCue?, enabled: Bool, now: Double, uptime: Double)?
    private var waitingOnRep = false
    /// External coach/OS cancellation must also invalidate intents held by the store.
    var onCancellation: (() -> Void)?
    var repVoice: RepVoicePlayer? {
        didSet {
            oldValue?.onInterrupt = nil
            repVoice?.onInterrupt = { [weak self] in self?.interrupted() }
        }
    }
    var isSpeaking: Bool { controller.isSpeaking || waitingOnRep }
    var lastStartedCueID: UUID? { controller.lastStartedCueID }
    var isTrackingPromptPlaying: Bool { controller.isTrackingPromptPlaying }
    var completedTrackingPrompt: VoiceCue? { controller.completedTrackingPrompt }

    init(playback: VoicePlayback, uptime: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.uptime = uptime
        controller = VoiceCuePlaybackController(playback: playback, uptime: uptime)
        playback.onInterrupt = { [weak self] in self?.interrupted() }
    }

    func update(session: TrainingSession, event: CoachingEvent?, enabled: Bool, now: Double) {
        update(context: .init(sessionID: session.id, generation: session.generation, phase: session.phase),
               event: event, enabled: enabled, now: now)
    }

    func update(context: VoiceCueContext, event: CoachingEvent?, enabled: Bool, now: Double) {
        let cue = event.map {
            VoiceCue(id: $0.id, sessionID: $0.sessionID, generation: $0.generation,
                     text: $0.decision.text, kind: .coaching($0.decision.priority),
                     issuedAt: $0.issuedAt, expiresAt: $0.expiresAt, reason: $0.decision.reason)
        }
        update(context: context, cue: cue, enabled: enabled, now: now)
    }

    private func update(context: VoiceCueContext, cue: VoiceCue?, enabled: Bool, now: Double) {
        latest = (context, cue, enabled, now, uptime())
        let busy = repVoice?.isPlaying == true
        if cue?.kind == .coaching(.stop) { repVoice?.yield() }
        controller.update(context: context, event: cue, enabled: enabled, now: now,
                          playbackAvailable: !busy || cue?.kind == .coaching(.stop))
        let waits = busy && enabled && (context.phase == .active || context.phase == .rest || context.phase == .finished) &&
            (cue?.kind == .coaching(.form) || (cue?.kind == .coaching(.rest) && context.phase != .active))
        let wasWaiting = waitingOnRep
        waitingOnRep = waits
        guard busy, waits || wasWaiting else { return }
        repVoice?.finishCurrent(then: waits ? { [weak self] in
            guard let self, let latest = self.latest else { return }
            self.waitingOnRep = false
            let elapsed = self.uptime() - latest.uptime
            guard elapsed.isFinite, elapsed >= 0 else { self.cancel(); return }
            self.update(context: latest.context, cue: latest.event, enabled: latest.enabled, now: latest.now + elapsed)
        } : nil)
    }

    func transition(to context: VoiceCueContext) {
        latest = nil
        waitingOnRep = false
        repVoice?.finishCurrent(then: nil)
        controller.transition(to: context)
    }

    private func interrupted() {
        cancel()
        repVoice?.cancel()
        onCancellation?()
    }

    func cancel() {
        latest = nil
        waitingOnRep = false
        repVoice?.finishCurrent(then: nil)
        controller.cancel()
    }
}

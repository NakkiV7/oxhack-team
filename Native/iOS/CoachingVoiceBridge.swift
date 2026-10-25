import Foundation

@MainActor
final class CoachingVoiceBridge {
    private let controller: VoiceCuePlaybackController

    init(playback: VoicePlayback) {
        controller = VoiceCuePlaybackController(playback: playback)
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
        controller.update(context: context, event: cue, enabled: enabled, now: now)
    }

    func cancel() { controller.cancel() }
}

import Foundation

public struct VoiceCue: Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case coaching(CoachingPriority), chat }
    public let id: UUID
    public let sessionID: UUID
    public let generation: UUID
    public let text: String
    public let kind: Kind
    public let reason: CoachingReason?
    public let issuedAt: Double
    public let expiresAt: Double?

    public init(id: UUID, sessionID: UUID, generation: UUID, text: String, kind: Kind,
                issuedAt: Double, expiresAt: Double?, reason: CoachingReason? = nil) {
        self.id = id; self.sessionID = sessionID; self.generation = generation
        self.text = text; self.kind = kind; self.reason = reason; self.issuedAt = issuedAt; self.expiresAt = expiresAt
    }
}

public struct VoiceCueContext: Sendable, Equatable {
    public let sessionID: UUID
    public let generation: UUID
    public let phase: SessionPhase

    public init(sessionID: UUID, generation: UUID, phase: SessionPhase) {
        self.sessionID = sessionID; self.generation = generation; self.phase = phase
    }
}

@MainActor
public protocol VoicePlayback: AnyObject {
    var onFinish: ((UUID) -> Void)? { get set }
    func speak(_ cue: VoiceCue)
    func stop()
}

@MainActor
public final class VoiceCuePlaybackController {
    private let playback: VoicePlayback
    private var active: VoiceCue?
    private var seen: Set<UUID> = []
    private var context: VoiceCueContext?

    public init(playback: VoicePlayback) {
        self.playback = playback
        playback.onFinish = { [weak self] id in
            guard self?.active?.id == id else { return }
            self?.active = nil
        }
    }

    public func update(context: VoiceCueContext, event: VoiceCue?, enabled: Bool, now: Double) {
        if self.context?.sessionID != context.sessionID || self.context?.generation != context.generation {
            cancel()
            seen = []
        }
        self.context = context
        guard now.isFinite else { cancel(); return }
        if active?.expiresAt.map({ now >= $0 }) == true { cancel() }
        guard enabled, context.phase == .active || context.phase == .rest else {
            if let event { seen.insert(event.id) }
            cancel()
            return
        }
        guard let event else { cancel(); return }
        guard event.sessionID == context.sessionID, event.generation == context.generation else { return }
        guard seen.insert(event.id).inserted else { return }
        guard !event.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, event.text.count <= 500,
              event.issuedAt.isFinite, event.issuedAt <= now,
              event.expiresAt.map({ $0.isFinite && now < $0 }) ?? (event.kind == .coaching(.stop)) else { return }
        guard active.map({ rank(event.kind) >= rank($0.kind) }) ?? true else { return }
        cancel()
        active = event
        playback.speak(event)
    }

    private func rank(_ kind: VoiceCue.Kind) -> Int {
        switch kind {
        case .coaching(.stop): return 4
        case .coaching(.form): return 3
        case .coaching(.pacing): return 2
        case .coaching(.rest): return 1
        case .chat: return 0
        }
    }

    public func cancel() {
        guard active != nil else { return }
        active = nil
        playback.stop()
    }
}

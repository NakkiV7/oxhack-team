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
    var onInterrupt: (() -> Void)? { get set }
    func speak(_ cue: VoiceCue)
    func stop()
}

extension VoicePlayback {
    /// Engines without an OS interruption source need no special handling.
    public var onInterrupt: (() -> Void)? { get { nil } set {} }
}

@MainActor
public final class VoiceCuePlaybackController {
    private let playback: VoicePlayback
    private let uptime: () -> Double
    private var active: VoiceCue?
    private var deferred: VoiceCue?
    private var seen: Set<UUID> = []
    private var context: VoiceCueContext?
    private var timeAnchor: (logical: Double, uptime: Double)?
    public private(set) var lastStartedCueID: UUID?
    public var isSpeaking: Bool { active != nil }
    public var isTrackingPromptPlaying: Bool { active?.reason == .tracking && active?.kind == .coaching(.form) }
    public private(set) var completedTrackingPrompt: VoiceCue?

    public init(playback: VoicePlayback, uptime: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.playback = playback
        self.uptime = uptime
        playback.onInterrupt = { [weak self] in self?.cancel() }
        playback.onFinish = { [weak self] id in
            guard let self, let finished = self.active, finished.id == id else { return }
            if self.isTrackingPromptPlaying { self.completedTrackingPrompt = finished }
            self.active = nil
            guard let next = self.deferred else { return }
            self.deferred = nil
            guard let context = self.context, let anchor = self.timeAnchor else { return }
            let elapsed = self.uptime() - anchor.uptime
            guard elapsed.isFinite, elapsed >= 0,
                  self.isFresh(next, context: context, now: anchor.logical + elapsed),
                  self.isTransition(next, context: context) else { return }
            self.start(next)
        }
    }

    /// Only natural active/rest → rest/finished actions may retain the current sentence across a source generation.
    /// New sets, input switches, pauses and abandoned sessions must use normal update/cancel instead.
    public func transition(to context: VoiceCueContext) {
        guard self.context?.sessionID == context.sessionID,
              self.context?.phase == .active || self.context?.phase == .rest,
              context.phase == .rest || context.phase == .finished else { return }
        deferred = nil
        self.context = context
    }

    /// Same input and active set, explicitly continued after camera identity recovery.
    /// Invalidate old queued intent without treating a capture-token change as a speech cancellation.
    public func continueTracking(to context: VoiceCueContext) {
        guard self.context?.sessionID == context.sessionID, self.context?.phase == .active, context.phase == .active else { return }
        deferred = nil; completedTrackingPrompt = nil
        self.context = context
    }

    public func update(context: VoiceCueContext, event: VoiceCue?, enabled: Bool, now: Double, playbackAvailable: Bool = true) {
        if self.context?.sessionID != context.sessionID || self.context?.generation != context.generation {
            cancel()
            seen = []
            completedTrackingPrompt = nil
        }
        self.context = context
        guard now.isFinite else { cancel(); return }
        timeAnchor = (now, uptime())
        guard enabled, context.phase == .active || context.phase == .rest || context.phase == .finished else {
            if let event { seen.insert(event.id) }
            cancel()
            return
        }
        guard let event else { return }
        guard event.sessionID == context.sessionID, event.generation == context.generation else { return }
        guard !seen.contains(event.id) else { return }
        guard isFresh(event, context: context, now: now) else { seen.insert(event.id); return }
        if let active {
            if event.kind == .coaching(.stop) {
                cancel()
            } else if isTransition(event, context: context), active.kind != .coaching(.stop) {
                // Exactly one natural transition can wait; ordinary warnings never enter this slot.
                seen.insert(event.id)
                deferred = event
                return
            } else if event.kind == .coaching(.form), active.kind != .coaching(.stop),
                      rank(active.kind) < rank(event.kind) || event.reason != active.reason {
                // Reassess a still-current form intent on a later tick; never truncate the current sentence.
                return
            } else { seen.insert(event.id); return }
        }
        guard playbackAvailable || event.kind == .coaching(.stop) else {
            if event.kind != .coaching(.form), !isTransition(event, context: context) { seen.insert(event.id) }
            return
        }
        seen.insert(event.id)
        start(event)
    }

    private func isTransition(_ cue: VoiceCue, context: VoiceCueContext) -> Bool {
        cue.kind == .coaching(.rest) &&
            ((context.phase == .finished && cue.reason == .workoutCompleted) ||
             (context.phase == .rest && cue.reason != .workoutCompleted))
    }

    private func isFresh(_ cue: VoiceCue, context: VoiceCueContext, now: Double) -> Bool {
        guard cue.sessionID == context.sessionID, cue.generation == context.generation,
              !cue.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, cue.text.count <= 500,
              cue.issuedAt.isFinite, cue.issuedAt <= now,
              cue.expiresAt.map({ $0.isFinite && now < $0 }) ?? (cue.kind == .coaching(.stop)) else { return false }
        if cue.reason == .workoutCompleted { return isTransition(cue, context: context) }
        return context.phase == .active || context.phase == .rest
    }

    private func start(_ cue: VoiceCue) {
        active = cue
        lastStartedCueID = cue.id
        playback.speak(cue)
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
        completedTrackingPrompt = nil
        deferred = nil
        guard active != nil else { return }
        active = nil
        playback.stop()
    }
}

/// Optional device-voice rep counting: the count on every camera-counted rep,
/// a motivational line every third clean rep, a start line when a camera set begins and a closing line when it ends.
/// One line plays at a time and is never cut off by another rep line; a newer count replaces one still waiting, so an
/// old number is never said, and lines that waited too long are dropped. Form and stop cues take over through `clear()`.
public struct RepVoicePlan: Sendable {
    public enum Coach: String, CaseIterable, Codable, Sendable {
        case device
        public var title: String { "Device voice" }
    }
    public struct Line: Equatable, Sendable {
        public enum Kind: String, Sendable { case count, motivation, start, closing }
        public let clip: String
        public let kind: Kind
        public let issuedAt: Double
        /// Seconds a line may wait before it is no longer worth saying.
        public var maxWait: Double {
            switch kind {
            case .count: return 1.5
            case .motivation, .start: return 4
            case .closing: return 8
            }
        }
    }
    public static let countLimit = 30
    public static let motivationEvery = 3
    public static let motivationClips = (1...7).map { "motivate-\($0)" }
    public static let closingClips = (1...3).map { "closing-\($0)" }
    public static var allClips: [String] {
        (1...countLimit).map(countClip) + motivationClips + closingClips + ["start"]
    }
    public static func countClip(_ rep: Int) -> String { String(format: "count-%02d", rep) }

    public private(set) var queue: [Line] = []
    private var motivationIndex = 0
    private var closingIndex = 0
    public init() {}

    public mutating func start(at time: Double) {
        queue = [Line(clip: "start", kind: .start, issuedAt: time)]
    }

    /// A counted rep. `clean` is true when the rep had no form issue.
    public mutating func rep(_ number: Int, clean: Bool, at time: Double) {
        queue.removeAll { $0.kind == .count || $0.kind == .start || time - $0.issuedAt > $0.maxWait }
        if (1...Self.countLimit).contains(number) { queue.append(Line(clip: Self.countClip(number), kind: .count, issuedAt: time)) }
        guard clean, number > 0, number.isMultiple(of: Self.motivationEvery) else { return }
        queue.removeAll { $0.kind == .motivation }
        queue.append(Line(clip: Self.motivationClips[motivationIndex % Self.motivationClips.count], kind: .motivation, issuedAt: time))
        motivationIndex += 1
    }

    public mutating func closing(at time: Double) {
        queue = [Line(clip: Self.closingClips[closingIndex % Self.closingClips.count], kind: .closing, issuedAt: time)]
        closingIndex += 1
    }

    /// The next line to play now, skipping any that waited too long.
    public mutating func next(at time: Double) -> Line? {
        while !queue.isEmpty {
            let line = queue.removeFirst()
            if time >= line.issuedAt, time - line.issuedAt <= line.maxWait { return line }
        }
        return nil
    }

    public mutating func clear() { queue.removeAll() }
}

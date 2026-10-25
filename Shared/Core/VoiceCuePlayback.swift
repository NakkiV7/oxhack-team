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
        let completion = event?.reason == .workoutCompleted
        let eligiblePhase = completion
            ? context.phase == .finished && event?.kind == .coaching(.rest)
            : context.phase == .active || context.phase == .rest
        guard enabled, eligiblePhase else {
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
        if completion, active?.kind != .coaching(.stop) { cancel() }
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

/// Spoken rep counting from bundled coach clips, modelled on the web squat coach: the count on every camera-counted rep,
/// a motivational line every third clean rep, a start line when a camera set begins and a closing line when it ends.
/// One line plays at a time and is never cut off by another rep line; a newer count replaces one still waiting, so an
/// old number is never said, and lines that waited too long are dropped. Form and stop cues take over through `clear()`.
public struct RepVoicePlan: Sendable {
    public enum Coach: String, CaseIterable, Codable, Sendable {
        case arnold, goggins
        public var title: String { rawValue.capitalized }
        /// Bundle subdirectory holding this coach's clips.
        public var folder: String { "DemoVoice/\(rawValue)-reps" }
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

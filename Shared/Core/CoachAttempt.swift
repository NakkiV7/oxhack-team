import Foundation

/// A fixed, versioned rule the camera can judge. Gemini never sets or changes these numbers.
public struct TempoContract: Codable, Equatable, Sendable {
    public enum Metric: String, Codable, Sendable { case lowering, repTime }
    public let exerciseID: String
    public let version: String
    public let metric: Metric
    public let label: String
    public let target: Double
    public let tolerance: Double
    public let pass: String

    public static let minimumValidReps = 3
    public static let squat = TempoContract(exerciseID: "squat", version: "squat-tempo-v1", metric: .lowering, label: "lowering time",
                                            target: 1.5, tolerance: 0.15,
                                            pass: "median lowering time within 0.15 s of the 1.5 s target over three counted reps")
    public static let pushup = TempoContract(exerciseID: "pushup", version: "pushup-cadence-v1", metric: .repTime, label: "rep time",
                                             target: 2.0, tolerance: 0.25,
                                             pass: "median rep time within 0.25 s of the 2.0 s target over three counted reps")
    /// Every movement the camera can assess. A catalogue exercise becomes assessable when it has a camera tracker and a
    /// contract here; every other exercise stays a practice log until its tracker is trained and validated.
    public static let all: [TempoContract] = [squat, pushup]
    public static func contract(for exerciseID: String) -> TempoContract? {
        guard ExerciseCatalog.find(exerciseID)?.tracking != nil else { return nil }
        return all.first { $0.exerciseID == exerciseID }
    }
    /// The plural movement name used in cues and attributes, for example "squats".
    public var movement: String { ExerciseCatalog.find(exerciseID)?.name.lowercased() ?? exerciseID }

    func value(of rep: AttemptRep) -> Double? {
        let value = metric == .lowering ? rep.lowering : rep.total
        return value.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
    }
}

/// A rep as the counter reports it to the coaching loop.
public struct LoopRep: Equatable, Sendable {
    public let number: Int?
    public let counted: Bool
    public let lowering: Double?
    public let rising: Double?
    public let total: Double?
    /// Knee flexion reached, in degrees (180 minus the smallest knee angle).
    public let flexion: Double?
    public let issue: String?
    public init(number: Int? = nil, counted: Bool = true, lowering: Double? = nil, rising: Double? = nil, total: Double? = nil,
                flexion: Double? = nil, issue: String? = nil) {
        self.number = number; self.counted = counted; self.lowering = lowering; self.rising = rising; self.total = total
        self.flexion = flexion; self.issue = issue
    }
    /// The rep the counter just completed, with its phases when they were measured.
    public init(counter: RepCounter) {
        self.init(number: counter.reps, counted: true, lowering: counter.lastRepPhases?.lowering, rising: counter.lastRepPhases?.rising,
                  total: counter.lastRepDuration, flexion: counter.lastRepPhases.map { 180 - $0.minimumAngle })
    }
}

/// A rep as stored with an attempt.
public struct AttemptRep: Codable, Equatable, Sendable {
    public enum Role: String, Codable, Sendable { case baseline, retry }
    public let number: Int?
    public let at: Date
    public let lowering: Double?
    public let rising: Double?
    public let total: Double?
    public let flexion: Double?
    public let counted: Bool
    public let valid: Bool
    public let reason: String?
    public let role: Role
}

/// The computed comparison. Every number is calculated here; Gemini may only explain it.
public struct AttemptOutcome: Codable, Equatable, Sendable {
    public enum Classification: String, Codable, Sendable { case closer, similar, further, unable }
    public let classification: Classification
    public let reason: String?
    public let contractVersion: String
    public let target: Double
    public let tolerance: Double
    public let baselineCount: Int
    public let retryCount: Int
    public let baselineMedian: Double?
    public let retryMedian: Double?
    public let baselineError: Double?
    public let retryError: Double?
    public let baselineRange: Double?
    public let retryRange: Double?
    public let comparableRange: Bool?
    public let baselineMeets: Bool
    public let retryMeets: Bool
    /// Changes smaller than this are "about the same": half the pass tolerance (provisional).
    public let noiseTolerance: Double?

    public var title: String {
        switch classification {
        case .closer: return "Closer to the target"
        case .similar: return "About the same"
        case .further: return "Further from the target"
        case .unable: return "Unable to assess"
        }
    }
    /// Counts as evidence for the step: the retry met the target, or the baseline already did and the retry did not drift away.
    public var qualifies: Bool { classification != .unable && (retryMeets || (baselineMeets && classification != .further)) }

    static func unable(_ reason: String, contract: TempoContract, baselineCount: Int = 0, retryCount: Int = 0) -> AttemptOutcome {
        .init(classification: .unable, reason: reason, contractVersion: contract.version, target: contract.target, tolerance: contract.tolerance,
              baselineCount: baselineCount, retryCount: retryCount, baselineMedian: nil, retryMedian: nil, baselineError: nil, retryError: nil,
              baselineRange: nil, retryRange: nil, comparableRange: nil, baselineMeets: false, retryMeets: false, noiseTolerance: nil)
    }
}

public enum AttemptComparison {
    /// Medians over all valid reps, never a chosen subset. A retry that moved through much less range than the baseline is
    /// not a tempo change, so it cannot be scored.
    public static func compare(baseline: [AttemptRep], retry: [AttemptRep], contract: TempoContract) -> AttemptOutcome {
        let b = baseline.filter { $0.valid }.compactMap { rep in contract.value(of: rep).map { (value: $0, range: rep.flexion) } }
        let r = retry.filter { $0.valid }.compactMap { rep in contract.value(of: rep).map { (value: $0, range: rep.flexion) } }
        guard b.count >= TempoContract.minimumValidReps, r.count >= TempoContract.minimumValidReps else {
            return .unable("fewer than three valid reps in a phase", contract: contract, baselineCount: b.count, retryCount: r.count)
        }
        let baselineError = median(b.map { abs($0.value - contract.target) })!, retryError = median(r.map { abs($0.value - contract.target) })!
        let baselineRange = median(b.compactMap(\.range)), retryRange = median(r.compactMap(\.range))
        let comparable = baselineRange.flatMap { base in retryRange.map { $0 >= 0.85 * base } }
        let noise = contract.tolerance / 2, change = baselineError - retryError
        let classification: AttemptOutcome.Classification = comparable == false ? .unable : abs(change) <= noise ? .similar : change > 0 ? .closer : .further
        return .init(classification: classification,
                     reason: comparable == false ? "the retry moved through much less range than the baseline; a shorter movement is not a tempo adjustment" : nil,
                     contractVersion: contract.version, target: contract.target, tolerance: contract.tolerance, baselineCount: b.count, retryCount: r.count,
                     baselineMedian: rounded(median(b.map(\.value))), retryMedian: rounded(median(r.map(\.value))),
                     baselineError: rounded(baselineError), retryError: rounded(retryError),
                     baselineRange: rounded(baselineRange), retryRange: rounded(retryRange), comparableRange: comparable,
                     baselineMeets: baselineError <= contract.tolerance, retryMeets: comparable != false && retryError <= contract.tolerance,
                     noiseTolerance: comparable == false ? nil : noise)
    }

    static func median(_ values: [Double]) -> Double? {
        let sorted = values.sorted(), middle = sorted.count / 2
        guard !sorted.isEmpty else { return nil }
        return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
    }
    static func rounded(_ value: Double?) -> Double? { value.map { ($0 * 100).rounded() / 100 } }
}

/// One coaching change between baseline and retry.
public struct AttemptCue: Codable, Equatable, Sendable {
    public enum Action: String, Codable, Sendable {
        case cueTarget = "cue_target", maintainTarget = "maintain_target", requestBetterView = "request_better_view", noAssessment = "no_assessment"
    }
    public enum Provenance: String, Codable, Sendable { case gemini, deterministic }
    public let action: Action
    public let text: String
    public let provenance: Provenance
    public init(action: Action, text: String, provenance: Provenance) { self.action = action; self.text = text; self.provenance = provenance }

    /// Used when Gemini is unavailable or its cue fails validation: names the target and the direction of the baseline error.
    public static func deterministic(contract: TempoContract, baseline: [AttemptRep]) -> AttemptCue {
        guard let middle = AttemptComparison.median(baseline.filter(\.counted).compactMap(contract.value(of:))) else {
            return .init(action: .requestBetterView, text: "I could not time those reps. Step back so your hips and knees stay in view, then try three more.", provenance: .deterministic)
        }
        let target = String(format: "%.1f", contract.target)
        if abs(middle - contract.target) <= contract.tolerance {
            return .init(action: .maintainTarget, text: "Your \(contract.label) is already about \(target) s. Keep exactly that rhythm for three more.", provenance: .deterministic)
        }
        let now = String(format: "%.1f", middle), count = Int(contract.target.rounded())
        let text: String
        switch (contract.metric, middle < contract.target) {
        case (.lowering, true): text = "Take longer on the way down: count to \(count) as you lower, aiming for about \(target) s."
        case (.lowering, false): text = "Lower a little quicker and more evenly, aiming for about \(target) s instead of \(now) s."
        case (.repTime, true): text = "Slow each rep down: count to \(count) from the top, down and back up, aiming for about \(target) s."
        case (.repTime, false): text = "Move a little quicker and more evenly, aiming for about \(target) s per rep instead of \(now) s."
        }
        return .init(action: .cueTarget, text: text, provenance: .deterministic)
    }
}

/// The saved form of an attempt.
public struct CoachAttemptRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let exerciseID: String
    public let contractVersion: String
    public let startedAt: Date
    public let status: CoachAttemptLoop.State
    public let baselineReps: [AttemptRep]
    public let retryReps: [AttemptRep]
    public let cue: AttemptCue?
    public let targetFrozenAt: Date?
    public let outcome: AttemptOutcome?
    public let explanation: String?
    public let completedAt: Date?
}

/// Coach, retry, verify as an explicit state machine. The app feeds it reps and the person's actions; it never touches the
/// network. A stable request id makes a late or duplicate cue harmless.
public struct CoachAttemptLoop: Sendable {
    public enum State: String, Codable, Sendable { case setup, baseline, preparingCue, cueReady, readyToRetry, retry, verifying, result, paused, cancelled }
    public enum Event: Equatable, Sendable {
        case baselineRep(valid: Int)
        case baselineComplete(requestID: UUID)
        /// A rep already under way when Start retry was pressed: the person had not heard the cue yet.
        case retryIgnored
        case retryRep(valid: Int)
        case result(AttemptOutcome)
    }
    public struct Transition: Codable, Equatable, Sendable { public let at: Date; public let from: State; public let to: State; public let note: String }

    public let attemptID: UUID
    public let contract: TempoContract
    public let startedAt: Date
    public private(set) var state = State.setup
    public private(set) var baseline: [AttemptRep] = []
    public private(set) var retry: [AttemptRep] = []
    public private(set) var cue: AttemptCue?
    public private(set) var requestID: UUID?
    public private(set) var targetFrozenAt: Date?
    public private(set) var retryFrom: Date?
    public private(set) var outcome: AttemptOutcome?
    public private(set) var explanation: String?
    public private(set) var completedAt: Date?
    public private(set) var log: [Transition] = []
    private var resumeTo: State?

    public init(contract: TempoContract, attemptID: UUID = UUID(), startedAt: Date) {
        self.contract = contract; self.attemptID = attemptID; self.startedAt = startedAt
    }

    public func validCount(_ role: AttemptRep.Role) -> Int { (role == .baseline ? baseline : retry).filter(\.valid).count }

    /// Camera running and framing acceptable: start collecting the baseline.
    @discardableResult public mutating func begin(at time: Date) -> Bool {
        guard state == .setup else { return false }
        go(.baseline, "setup ok", at: time); return true
    }

    /// A rep from the counter. Reps outside the baseline and retry phases are ordinary training and return nil.
    public mutating func onRep(_ rep: LoopRep, at time: Date) -> Event? {
        switch state {
        case .baseline:
            record(rep, role: .baseline, at: time)
            guard validCount(.baseline) >= TempoContract.minimumValidReps else { return .baselineRep(valid: validCount(.baseline)) }
            let id = UUID(); requestID = id
            go(.preparingCue, "baseline complete", at: time)
            return .baselineComplete(requestID: id)
        case .readyToRetry, .retry:
            if state == .readyToRetry, let retryFrom, let total = rep.total, time.timeIntervalSince(retryFrom) < total - 0.25 { return .retryIgnored }
            if state == .readyToRetry { go(.retry, "first retry rep", at: time) }
            record(rep, role: .retry, at: time)
            guard validCount(.retry) >= TempoContract.minimumValidReps else { return .retryRep(valid: validCount(.retry)) }
            go(.verifying, "retry complete", at: time)
            let result = AttemptComparison.compare(baseline: baseline, retry: retry, contract: contract)
            finish(result, note: "outcome \(result.classification.rawValue)", at: time)
            return .result(result)
        default:
            return nil
        }
    }

    /// The cue arrived. Ignored unless it answers the open request. The target is frozen from here on.
    @discardableResult public mutating func cueReady(_ cue: AttemptCue, requestID: UUID, at time: Date) -> Bool {
        guard state == .preparingCue, requestID == self.requestID else { return false }
        self.cue = cue; targetFrozenAt = time
        go(.cueReady, "cue \(cue.provenance.rawValue)", at: time); return true
    }
    @discardableResult public mutating func cueFailed(at time: Date) -> Bool {
        guard state == .preparingCue, let requestID else { return false }
        return cueReady(.deterministic(contract: contract, baseline: baseline), requestID: requestID, at: time)
    }

    /// The person explicitly starts the retry.
    @discardableResult public mutating func startRetry(at time: Date) -> Bool {
        guard state == .cueReady else { return false }
        retryFrom = time; go(.readyToRetry, "person started retry", at: time); return true
    }

    /// Camera interruptions pause collection; the same camera resumes the same phase.
    @discardableResult public mutating func pause(at time: Date) -> Bool {
        guard [.baseline, .readyToRetry, .retry].contains(state) else { return false }
        resumeTo = state; go(.paused, "camera interrupted", at: time); return true
    }
    @discardableResult public mutating func resume(at time: Date) -> Bool {
        guard state == .paused, let resumeTo else { return false }
        go(resumeTo, "resumed", at: time); self.resumeTo = nil; return true
    }
    /// A different camera after the baseline makes the phases incomparable.
    public mutating func cameraChanged(at time: Date) -> Event? {
        guard [.readyToRetry, .retry].contains(state) || (state == .paused && [.readyToRetry, .retry].contains(resumeTo)) else { return nil }
        let result = AttemptOutcome.unable("camera changed between baseline and retry", contract: contract,
                                           baselineCount: validCount(.baseline), retryCount: validCount(.retry))
        finish(result, note: "camera changed", at: time)
        return .result(result)
    }
    @discardableResult public mutating func cancel(at time: Date) -> Bool {
        guard state != .result, state != .cancelled else { return false }
        go(.cancelled, "person cancelled", at: time); completedAt = time; return true
    }
    /// Gemini's explanation of the computed result. It cannot change the result.
    public mutating func explained(_ text: String) { if state == .result { explanation = text } }

    public var record: CoachAttemptRecord {
        .init(id: attemptID, exerciseID: contract.exerciseID, contractVersion: contract.version, startedAt: startedAt, status: state,
              baselineReps: baseline, retryReps: retry, cue: cue, targetFrozenAt: targetFrozenAt, outcome: outcome, explanation: explanation,
              completedAt: completedAt)
    }

    private mutating func finish(_ result: AttemptOutcome, note: String, at time: Date) {
        outcome = result; completedAt = time; resumeTo = nil
        go(.result, note, at: time)
    }
    private mutating func go(_ next: State, _ note: String, at time: Date) {
        log.append(.init(at: time, from: state, to: next, note: note)); state = next
    }
    private mutating func record(_ rep: LoopRep, role: AttemptRep.Role, at time: Date) {
        let measured = contract.value(of: .init(number: nil, at: time, lowering: rep.lowering, rising: nil, total: rep.total, flexion: nil,
                                                 counted: true, valid: true, reason: nil, role: role)) != nil
        let valid = rep.counted && measured
        let entry = AttemptRep(number: rep.number, at: time, lowering: rep.lowering, rising: rep.rising, total: rep.total, flexion: rep.flexion,
                               counted: rep.counted, valid: valid, reason: rep.counted ? (measured ? nil : "metric not measured") : (rep.issue ?? "not counted"),
                               role: role)
        if role == .baseline { baseline.append(entry) } else { retry.append(entry) }
    }
}

public enum StepVerification: String, Codable, Sendable { case none, firstCompletion, consistent }

public struct StepVerificationSummary: Equatable, Sendable {
    public let verification: StepVerification
    public let qualifyingAttempts: [UUID]
    public let days: Int
}

public enum NodeVerification {
    /// A camera step is AI-verified by one qualifying attempt, and verified as consistent when qualifying attempts fall on two
    /// different days in the person's calendar. Verification is a mark on top of the earned rule, never a replacement for it.
    public static func evaluate(attempts: [CoachAttemptRecord], exerciseID: String, calendar: Calendar = .current) -> StepVerificationSummary {
        guard let contract = TempoContract.contract(for: exerciseID) else { return .init(verification: .none, qualifyingAttempts: [], days: 0) }
        var seen = Set<UUID>()
        let qualifying = attempts.filter { $0.exerciseID == exerciseID && $0.contractVersion == contract.version && $0.outcome?.qualifies == true && seen.insert($0.id).inserted }
        let days = Set(qualifying.map { calendar.startOfDay(for: $0.completedAt ?? $0.startedAt) }).count
        return .init(verification: days >= 2 ? .consistent : qualifying.isEmpty ? .none : .firstCompletion,
                     qualifyingAttempts: qualifying.map(\.id), days: days)
    }
}

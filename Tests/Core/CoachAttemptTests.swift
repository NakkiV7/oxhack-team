import Foundation
import Testing
@testable import SpottrCore

private let t0 = Date(timeIntervalSince1970: 1_790_000_000)
private func rep(_ lowering: Double?, counted: Bool = true, flexion: Double? = 80, total: Double = 3) -> LoopRep {
    LoopRep(counted: counted, lowering: lowering, rising: 1, total: total, flexion: flexion)
}
private func reps(_ values: [Double], role: AttemptRep.Role, flexion: Double = 80, metric: TempoContract.Metric = .lowering) -> [AttemptRep] {
    values.map { AttemptRep(number: nil, at: t0, lowering: metric == .lowering ? $0 : nil, rising: 1, total: metric == .repTime ? $0 : 3,
                            flexion: flexion, counted: true, valid: true, reason: nil, role: role) }
}
/// A counted rep timed on the contract's metric.
private func timedRep(_ value: Double, _ contract: TempoContract) -> LoopRep {
    contract.metric == .lowering ? rep(value) : LoopRep(counted: true, lowering: nil, rising: nil, total: value, flexion: 80)
}

/// Runs a whole attempt through the state machine and returns its saved record.
func completedAttempt(_ contract: TempoContract = .squat, baseline: [Double], retry: [Double], at start: Date) -> CoachAttemptRecord {
    var loop = CoachAttemptLoop(contract: contract, startedAt: start)
    loop.begin(at: start)
    var request: UUID?
    for (i, value) in baseline.enumerated() {
        if case .baselineComplete(let id) = loop.onRep(timedRep(value, contract), at: start.addingTimeInterval(Double(i + 1) * 4)) { request = id }
    }
    loop.cueReady(AttemptCue(action: .cueTarget, text: "Count to two on the way down.", provenance: .gemini), requestID: request!, at: start.addingTimeInterval(20))
    loop.startRetry(at: start.addingTimeInterval(25))
    for (i, value) in retry.enumerated() { _ = loop.onRep(timedRep(value, contract), at: start.addingTimeInterval(30 + Double(i) * 4)) }
    return loop.record
}

@Test func comparisonClassifiesAgainstTheFrozenTarget() {
    let closer = AttemptComparison.compare(baseline: reps([0.9, 1.0, 0.8], role: .baseline), retry: reps([1.45, 1.5, 1.6], role: .retry), contract: .squat)
    #expect(closer.classification == .closer && closer.retryMeets && !closer.baselineMeets && closer.qualifies)
    #expect(closer.baselineMedian == 0.9 && closer.retryMedian == 1.5 && closer.retryError == 0.05)
    let similar = AttemptComparison.compare(baseline: reps([1.37, 1.34, 1.4], role: .baseline), retry: reps([1.37, 1.4, 1.35], role: .retry), contract: .squat)
    #expect(similar.classification == .similar && similar.baselineMeets && similar.qualifies)
    let further = AttemptComparison.compare(baseline: reps([1.5, 1.45, 1.55], role: .baseline), retry: reps([0.8, 0.9, 1.0], role: .retry), contract: .squat)
    #expect(further.classification == .further && !further.qualifies)
    let tooFew = AttemptComparison.compare(baseline: reps([1.5, 1.4], role: .baseline), retry: reps([1.5, 1.4, 1.6], role: .retry), contract: .squat)
    #expect(tooFew.classification == .unable && tooFew.reason == "fewer than three valid reps in a phase")
    let shallow = AttemptComparison.compare(baseline: reps([1.0, 1.0, 1.0], role: .baseline, flexion: 90),
                                            retry: reps([1.5, 1.5, 1.5], role: .retry, flexion: 60), contract: .squat)
    #expect(shallow.classification == .unable && shallow.comparableRange == false && !shallow.retryMeets && !shallow.qualifies)
}

@Test func deterministicCueNamesTheTargetAndTheDirection() {
    #expect(AttemptCue.deterministic(contract: .squat, baseline: reps([0.8, 0.9, 1.0], role: .baseline)).text
            == "Take longer on the way down: count to 2 as you lower, aiming for about 1.5 s.")
    #expect(AttemptCue.deterministic(contract: .squat, baseline: reps([2.2, 2.1, 2.3], role: .baseline)).text
            == "Lower a little quicker and more evenly, aiming for about 1.5 s instead of 2.2 s.")
    #expect(AttemptCue.deterministic(contract: .squat, baseline: reps([1.5, 1.4, 1.6], role: .baseline)).action == .maintainTarget)
    #expect(AttemptCue.deterministic(contract: .squat, baseline: []).action == .requestBetterView)
}

@Test func coachLoopWalksFromSetupToAResultAndIgnoresLateOrEarlyInput() throws {
    var loop = CoachAttemptLoop(contract: .squat, startedAt: t0)
    let beforeBaseline = loop.onRep(rep(1.0), at: t0)
    #expect(beforeBaseline == nil)                                      // reps before the baseline are ordinary training
    let began = loop.begin(at: t0)
    let firstRep = loop.onRep(rep(0.9), at: t0.addingTimeInterval(4))
    #expect(began && firstRep == .baselineRep(valid: 1))
    _ = loop.onRep(rep(nil, counted: false), at: t0.addingTimeInterval(8))  // a shallow attempt is kept but not valid
    _ = loop.onRep(rep(1.0), at: t0.addingTimeInterval(12))
    guard case .baselineComplete(let request) = loop.onRep(rep(0.8), at: t0.addingTimeInterval(16)) else { Issue.record("baseline not complete"); return }
    #expect(loop.state == .preparingCue && loop.baseline.count == 4 && loop.validCount(.baseline) == 3)
    let foreign = loop.cueReady(AttemptCue(action: .cueTarget, text: "Slower", provenance: .gemini), requestID: UUID(), at: t0.addingTimeInterval(17))
    let whileWaiting = loop.onRep(rep(1.2), at: t0.addingTimeInterval(18))   // reps while the cue is prepared belong to neither phase
    let accepted = loop.cueReady(AttemptCue(action: .cueTarget, text: "Count to two.", provenance: .gemini), requestID: request, at: t0.addingTimeInterval(19))
    let started = loop.startRetry(at: t0.addingTimeInterval(20))
    #expect(!foreign && whileWaiting == nil && accepted && started)
    let early = loop.onRep(rep(1.5, total: 3), at: t0.addingTimeInterval(21))   // began before Start retry
    #expect(early == .retryIgnored && loop.state == .readyToRetry && loop.retry.isEmpty)
    let firstRetry = loop.onRep(rep(1.45), at: t0.addingTimeInterval(25))
    #expect(firstRetry == .retryRep(valid: 1))
    _ = loop.onRep(rep(1.5), at: t0.addingTimeInterval(29))
    guard case .result(let outcome) = loop.onRep(rep(1.6), at: t0.addingTimeInterval(33)) else { Issue.record("no result"); return }
    #expect(outcome.classification == .closer && loop.state == .result)
    let cancelledAfterResult = loop.cancel(at: t0.addingTimeInterval(34))
    #expect(!cancelledAfterResult)                                      // a finished attempt stays finished
    loop.explained("Your retry median was 1.5 s, inside the target.")
    let record = loop.record
    #expect(record.status == .result && record.retryReps.count == 3 && record.baselineReps[1].valid == false)
    #expect(record.targetFrozenAt == t0.addingTimeInterval(19) && record.completedAt == t0.addingTimeInterval(33))
    #expect(record.explanation != nil && record.cue?.provenance == .gemini)
    #expect(try JSONDecoder().decode(CoachAttemptRecord.self, from: JSONEncoder().encode(record)) == record)
}

@Test func interruptionsPauseResumeOrEndTheAttempt() {
    var loop = CoachAttemptLoop(contract: .squat, startedAt: t0)
    loop.begin(at: t0)
    _ = loop.onRep(rep(0.9), at: t0.addingTimeInterval(4))
    let paused = loop.pause(at: t0.addingTimeInterval(5))
    #expect(paused && loop.state == .paused)
    let changedDuringBaseline = loop.cameraChanged(at: t0.addingTimeInterval(6))   // a new camera during the baseline just resumes collection
    let resumed = loop.resume(at: t0.addingTimeInterval(7))
    #expect(changedDuringBaseline == nil && resumed && loop.state == .baseline && loop.validCount(.baseline) == 1)
    _ = loop.onRep(rep(1.0), at: t0.addingTimeInterval(11)); _ = loop.onRep(rep(0.8), at: t0.addingTimeInterval(15))
    let fellBack = loop.cueFailed(at: t0.addingTimeInterval(16))
    #expect(fellBack && loop.cue?.provenance == .deterministic && loop.state == .cueReady)
    loop.startRetry(at: t0.addingTimeInterval(17))
    let pausedInRetry = loop.pause(at: t0.addingTimeInterval(18))
    #expect(pausedInRetry)
    guard case .result(let outcome) = loop.cameraChanged(at: t0.addingTimeInterval(19)) else { Issue.record("no result"); return }
    #expect(outcome.classification == .unable && outcome.reason == "camera changed between baseline and retry" && loop.state == .result)
    var cancelled = CoachAttemptLoop(contract: .squat, startedAt: t0)
    cancelled.begin(at: t0)
    let stopped = cancelled.cancel(at: t0.addingTimeInterval(1))
    let afterCancel = cancelled.onRep(rep(1.5), at: t0.addingTimeInterval(2))
    #expect(stopped && afterCancel == nil)
}

@Test func verificationNeedsAQualifyingAttemptAndTwoDaysForConsistency() {
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Europe/London")!
    let pass = completedAttempt(baseline: [0.9, 1.0, 0.8], retry: [1.45, 1.5, 1.6], at: t0)
    let drift = completedAttempt(baseline: [1.5, 1.45, 1.55], retry: [0.8, 0.9, 1.0], at: t0.addingTimeInterval(3_600))
    let nextDay = completedAttempt(baseline: [1.4, 1.5, 1.5], retry: [1.5, 1.5, 1.45], at: t0.addingTimeInterval(86_400))
    #expect(NodeVerification.evaluate(attempts: [drift], exerciseID: "squat", calendar: calendar).verification == .none)
    #expect(NodeVerification.evaluate(attempts: [pass, drift, pass], exerciseID: "squat", calendar: calendar)
            == StepVerificationSummary(verification: .firstCompletion, qualifyingAttempts: [pass.id], days: 1))
    #expect(NodeVerification.evaluate(attempts: [pass, nextDay], exerciseID: "squat", calendar: calendar).verification == .consistent)
    #expect(NodeVerification.evaluate(attempts: [pass, nextDay], exerciseID: "pushup", calendar: calendar).verification == .none)
}

@Test func loopRepReadsTheCountersMeasuredPhases() {
    var counter = RepCounter(exercise: .squat)
    for (time, angle) in [(0.0, 170.0), (0.2, 170), (0.6, 130), (1.0, 90), (1.2, 90), (1.8, 170), (2.0, 170)] {
        _ = counter.consume(.init(time: time, angle: angle))
    }
    let looped = LoopRep(counter: counter)
    #expect(looped.number == 1 && looped.total == 1.8 && looped.flexion == 90)
    #expect(abs((looped.lowering ?? 0) - 0.4) < 1e-9 && abs((looped.rising ?? 0) - 0.8) < 1e-9)
}

@Test func pushUpsAreAssessedOnRepTimeThroughTheSameLoop() {
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Europe/London")!
    let record = completedAttempt(.pushup, baseline: [1.4, 1.5, 1.3], retry: [1.9, 2.0, 2.1], at: t0)
    #expect(record.exerciseID == "pushup" && record.contractVersion == "pushup-cadence-v1")
    #expect(record.outcome?.classification == .closer && record.outcome?.retryMeets == true && record.outcome?.retryMedian == 2.0)
    #expect(NodeVerification.evaluate(attempts: [record], exerciseID: "pushup", calendar: calendar).verification == .firstCompletion)
    #expect(NodeVerification.evaluate(attempts: [record], exerciseID: "squat", calendar: calendar).verification == .none)
    #expect(AttemptCue.deterministic(contract: .pushup, baseline: reps([1.4, 1.5, 1.3], role: .baseline, metric: .repTime)).text
            == "Slow each rep down: count to 2 from the top, down and back up, aiming for about 2.0 s.")
    #expect(AttemptCue.deterministic(contract: .pushup, baseline: reps([2.6, 2.8, 2.7], role: .baseline, metric: .repTime)).text
            == "Move a little quicker and more evenly, aiming for about 2.0 s per rep instead of 2.7 s.")
    // A push-up rep without a measured duration is kept but cannot count.
    var loop = CoachAttemptLoop(contract: .pushup, startedAt: t0)
    loop.begin(at: t0)
    _ = loop.onRep(LoopRep(counted: true), at: t0.addingTimeInterval(3))
    #expect(loop.baseline.count == 1 && loop.validCount(.baseline) == 0 && loop.baseline[0].reason == "metric not measured")
}

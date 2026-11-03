// The coach -> retry -> verify loop as an explicit state machine. The page feeds it reps from the counter and user actions;
// it never talks to the network itself. Stable attempt and request ids make late or duplicate responses harmless.
import { compare, deterministicCue, metricValue, MIN_VALID } from './coach.mjs';

export const STATES = ['setup', 'baseline', 'preparing_cue', 'cue_ready', 'ready_to_retry', 'retry', 'verifying', 'result', 'paused', 'cancelled'];

export class CoachLoop {
  constructor({ contract, attemptId = crypto.randomUUID(), uuid = () => crypto.randomUUID(), clock = () => Date.now() }) {
    Object.assign(this, { contract, attemptId, uuid, clock });
    this.state = 'setup'; this.baseline = []; this.retry = []; this.cue = null; this.outcome = null; this.explanation = null;
    this.requestId = null; this.target = null; this.resumeTo = null; this.interventions = []; this.log = [];
  }
  #go(state, note) { this.log.push({ at: this.clock(), from: this.state, to: state, note }); this.state = state; }
  #valid(rep) { return !!rep.counted && metricValue(rep, this.contract.metric) != null; }
  #record(rep, role) {
    const r = { repN: rep.n ?? null, at: this.clock(), down: rep.tDown ?? null, up: rep.tUp ?? null, secs: rep.secs ?? null, travel: rep.travel ?? null, depth: rep.depth ?? null, counted: !!rep.counted, valid: this.#valid(rep), reason: rep.counted ? (this.#valid(rep) ? null : 'metric not measured') : (rep.issue ?? 'not counted'), role };
    (role === 'baseline' ? this.baseline : this.retry).push(r);
    return r;
  }
  validCount(role) { return (role === 'baseline' ? this.baseline : this.retry).filter((r) => r.valid).length; }

  // Setup checks passed (camera running, framing ok): start collecting the baseline.
  begin() { if (this.state !== 'setup') return false; this.#go('baseline', 'setup ok'); return true; }

  // A rep from the counter. Returns an event the page acts on, or null.
  onRep(rep) {
    if (this.state === 'baseline') {
      this.#record(rep, 'baseline');
      if (this.validCount('baseline') >= MIN_VALID) { this.requestId = this.uuid(); this.#go('preparing_cue', 'baseline complete'); return { event: 'baseline_complete', requestId: this.requestId, baseline: this.baseline }; }
      return { event: 'baseline_rep', valid: this.validCount('baseline') };
    }
    // A rep that was already under way when Start retry was pressed (it ends sooner after the press than it lasted, with a
    // quarter-second allowance for reaction) is not a retry rep: the person had not heard the cue yet.
    if (this.state === 'ready_to_retry' && this.retryFrom != null && rep.secs && this.clock() - this.retryFrom < rep.secs * 1000 - 250) return { event: 'retry_ignored', reason: 'began before Start retry' };
    if (this.state === 'ready_to_retry' || this.state === 'retry') {
      if (this.state === 'ready_to_retry') this.#go('retry', 'first retry rep');
      this.#record(rep, 'retry');
      if (this.validCount('retry') >= MIN_VALID) { this.#go('verifying', 'retry complete'); return this.#verify(); }
      return { event: 'retry_rep', valid: this.validCount('retry') };
    }
    return null; // reps in other states are ordinary training, not part of the attempt
  }

  // The cue arrived (from Gemini via the server, or deterministic). Ignored unless it answers the open request.
  cueReady(cue, requestId) {
    if (this.state !== 'preparing_cue' || requestId !== this.requestId) return false;
    this.cue = cue; this.target = { metric: this.contract.metric, value: this.contract.target, unit: this.contract.unit, tolerance: this.contract.tolerance, rule: 'median absolute error over three valid reps', contractVersion: this.contract.version, frozenAt: this.clock() };
    this.#go('cue_ready', `cue ${cue.provenance ?? 'unknown'}`); return true;
  }
  cueFailed() { if (this.state !== 'preparing_cue') return false; return this.cueReady({ ...deterministicCue(this.contract, this.baseline), provenance: 'deterministic' }, this.requestId); }

  // The user explicitly starts the retry. The target cannot change after this.
  startRetry() { if (this.state !== 'cue_ready') return false; this.retryFrom = this.clock(); this.#go('ready_to_retry', 'user started retry'); return true; }

  #verify() {
    this.outcome = { ...compare(this.baseline, this.retry, this.contract), target: this.target.value, verifiedAt: this.clock() };
    this.#go('result', `outcome ${this.outcome.classification}`);
    return { event: 'result', outcome: this.outcome };
  }
  explained(explanation) { if (this.state === 'result') this.explanation = explanation; }

  // Camera interruptions pause collection; a material camera change makes the phases incomparable.
  pause() { if (['baseline', 'retry', 'ready_to_retry'].includes(this.state)) { this.resumeTo = this.state; this.#go('paused', 'camera interrupted'); return true; } return false; }
  resume() { if (this.state !== 'paused') return false; this.#go(this.resumeTo, 'resumed'); this.resumeTo = null; return true; }
  cameraChanged() {
    if (['retry', 'ready_to_retry'].includes(this.state) || (this.state === 'paused' && ['retry', 'ready_to_retry'].includes(this.resumeTo))) {
      this.outcome = { classification: 'unable', reason: 'camera changed between baseline and retry', target: this.target?.value ?? this.contract.target, contractVersion: this.contract.version, verifiedAt: this.clock() };
      this.#go('result', 'camera changed'); return { event: 'result', outcome: this.outcome };
    }
    return null;
  }
  cancel() { if (['result', 'cancelled'].includes(this.state)) return false; this.#go('cancelled', 'user cancelled'); return true; }
  // An HRT cue delivered during the attempt is recorded so the baseline is never claimed uncoached.
  intervention(note) { this.interventions.push({ at: this.clock(), state: this.state, note }); }

  snapshot() {
    return { attemptId: this.attemptId, status: this.state, contractVersion: this.contract.version, exercise: this.contract.exerciseId, variation: this.contract.variation,
      target: this.target, baselineReps: this.baseline, retryReps: this.retry, cue: this.cue, outcome: this.outcome, explanation: this.explanation, interventions: this.interventions };
  }
}

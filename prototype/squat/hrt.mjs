// Short-horizon tempo forecasting for squats: after a counted rep, estimate the probability that the lowering phase of
// one of the next two reps falls outside the programme's tempo range, then decide whether that is worth a cue.
// Pure logic, shared by the page (live and replay) and by hrt/train.mjs (offline evaluation), so the features a model
// was trained on are, by construction, the features it sees at run time. Nothing here looks past the current rep.

export const LABEL_VERSION = 'tempo-v2'; // v2 (25 Oct 06:05, before any held-out evaluation): the event is the first sustained departure, not any single rep outside the band
export const SUSTAIN = 3;                 // a departure holds when at least 2 of 3 consecutive reps are outside the band
export const FEATURE_VERSION = 'f2'; // f2 adds the set-baseline drift features (before any held-out evaluation)
export let HORIZON = 2;        // reps; the deployed artifact carries its own horizon (see setHorizon)
export function setHorizon(h) { HORIZON = Math.max(1, Math.round(h)); }
export const MIN_REPS = 3;     // counted reps before the first forecast
export const WINDOW = 3;       // rolling window of recent reps
export const POLICY_VERSION = 'budget-v1';

// Programme tempo targets for the lowering phase, in seconds. A target is a prescription, not a definition of safe or
// correct technique. "controlled" is the default; the range was frozen before the evaluation (see docs/HRT.md).
export const TARGETS = {
  controlled: { id: 'controlled-v1', label: 'Controlled lowering, 0.6 to 1.5 s', L: 0.6, U: 1.5 },
  relative: { id: 'relative-v1', label: 'Keep your tempo: lowering within 25% of your first three reps', rel: 0.25 },
  slow: { id: 'slow-v1', label: 'Slow eccentric, 2 to 4 s', L: 2.0, U: 4.0 },
};
// Primary target: relative, revised on 25 Oct 2026 05:40 before any held-out evaluation, because at a natural fast pace the
// fixed 0.6 s edge coincides with the lowering duration itself and labels become rounding noise (see docs/HRT.md).
export const DEFAULT_TARGET = 'relative';

// The bounds a set is judged against: fixed for a programme range, or derived from the set's own first MIN_REPS counted
// reps for a relative target (null until those reps exist). Both kinds freeze within the set.
export function bounds(target, reps) {
  if (target.rel == null) return { L: target.L, U: target.U };
  const first = reps.filter((r) => r.counted).slice(0, MIN_REPS).map((r) => r.tDown).filter(Number.isFinite);
  if (first.length < MIN_REPS) return null;
  const base = median(first);
  return { L: Math.round(base * (1 - target.rel) * 100) / 100, U: Math.round(base * (1 + target.rel) * 100) / 100, base };
}

export const FEATURES = ['down', 'down_med', 'down_trend', 'down_range', 'down_drift', 'margin', 'up', 'up_trend', 'up_drift', 'rep_n', 'elapsed', 'depth_trend', 'depth_missing'];
export const FEATURE_SETS = { // for the ablations and the set-position baseline
  position: ['rep_n', 'elapsed'],
  tempo: ['down', 'down_med', 'down_trend', 'down_range', 'down_drift', 'margin', 'up', 'up_trend', 'up_drift', 'rep_n', 'elapsed'],
  full: FEATURES,
};

export const violates = (down, b) => !(b && Number.isFinite(down) && down >= b.L && down <= b.U); // b: bounds (or a fixed target)
const median = (a) => { const s = [...a].sort((x, y) => x - y); const m = s.length >> 1; return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2; };
const last = (a, n) => a.slice(Math.max(0, a.length - n));

// reps: every attempt of the set in order, counted or not, each with { counted, tDown, tUp, secs, depth, tEnd }.
// t: 1-based index among counted reps (the origin). Returns the feature vector for the origin, or null before MIN_REPS.
export function featuresAt(reps, t, target) {
  const counted = reps.filter((r) => r.counted);
  if (t < MIN_REPS || t > counted.length) return null;
  const b = bounds(target, reps);
  const seen = counted.slice(0, t), cur = seen[t - 1], prev = seen.slice(0, -1);
  const downs = seen.map((r) => r.tDown), ups = seen.map((r) => r.tUp);
  const recentDown = last(downs, WINDOW), prevDown = last(prev.map((r) => r.tDown), WINDOW), prevUp = last(prev.map((r) => r.tUp), WINDOW);
  const first = seen.slice(0, MIN_REPS); // the set's own baseline: its first three counted reps
  const prevDepth = prev.map((r) => r.depth).filter(Number.isFinite);
  const depthKnown = Number.isFinite(cur.depth) && prevDepth.length > 0;
  const setStart = seen[0].tEnd - seen[0].secs; // the set clock starts when the first rep began, live and offline alike
  return {
    down: cur.tDown,
    down_med: median(recentDown),
    down_trend: cur.tDown - median(prevDown),
    down_range: Math.max(...recentDown) - Math.min(...recentDown),
    down_drift: median(recentDown) - median(first.map((r) => r.tDown)),
    margin: Math.min(cur.tDown - b.L, b.U - cur.tDown) / (b.U - b.L),
    up: cur.tUp,
    up_trend: cur.tUp - median(prevUp),
    up_drift: median(last(ups, WINDOW)) - median(first.map((r) => r.tUp)),
    rep_n: t,
    elapsed: cur.tEnd - setStart,
    depth_trend: depthKnown ? cur.depth - median(last(prevDepth, WINDOW)) : 0,
    depth_missing: depthKnown ? 0 : 1,
  };
}

// The first sustained departure of a set: counted rep k is outside the bounds and so are at least 2 of reps k..k+2.
// { k } when found; { k: null, undecidedAt } when a rep outside the band cannot be judged sustained yet; { k: null } otherwise.
export function departureAt(reps, b, { setEnded = false } = {}) {
  const v = reps.filter((r) => r.counted).map((r) => (violates(r.tDown, b) ? 1 : 0));
  for (let i = 0; i < v.length; i++) {
    if (!v[i]) continue;
    const seen = v.slice(i, i + SUSTAIN), sum = seen.reduce((a, x) => a + x, 0);
    if (sum >= 2) return { k: i + 1 };                                              // two of three already outside: settled
    if (seen.length < SUSTAIN) return setEnded ? { k: null } : { k: null, undecidedAt: i + 1 };
  }
  return { k: null };
}

// Why a forecast is not made at this origin, or null when it is eligible. Uses only the attempts up to the origin.
export function ineligible(reps, t, target) {
  const counted = reps.filter((r) => r.counted);
  if (t < MIN_REPS || !counted[t - 1]) return 'baseline';
  const upto = reps.slice(0, reps.indexOf(counted[t - 1]) + 1), b = bounds(target, upto);
  if (violates(counted[t - 1].tDown, b)) return 'current_rep_outside_target';
  if (departureAt(upto, b).k != null) return 'after_departure'; // the tempo has already shifted this set
  return null;
}

// The outcome of a forecast made after counted rep t: Y = 1 when the set's first sustained departure starts at rep t+1
// or t+2. Deciding that needs the next two counted reps, plus up to two more when one of them is outside the band (to
// tell a blip from a departure). An uncounted attempt inside that window, or the end of the set before it is complete,
// excludes the origin; an origin at or after the departure is excluded as well (nothing left to forecast).
export function labelAt(reps, t, target, { setEnded = false, horizon = HORIZON } = {}) {
  const counted = reps.filter((r) => r.counted);
  const origin = reps.indexOf(counted[t - 1]);
  if (origin < 0) return { state: 'pending' };
  const b = bounds(target, reps);
  if (!b) return { state: 'pending' };
  const dep = departureAt(reps, b, { setEnded });
  if (dep.k != null && dep.k <= t) return { state: 'excluded', reason: 'after_departure', futureReps: [] };
  const n = counted.length, vAt = (i) => (violates(counted[i - 1].tDown, b) ? 1 : 0);
  // Walk the horizon: a departure at j is settled once two of reps j..j+2 are outside; a rep inside rules j out at once.
  let y = 0, k = null, needUpTo = t + horizon, undecided = false;
  for (let j = t + 1; j <= t + horizon; j++) {
    if (j > n) { undecided = true; break; }
    if (!vAt(j)) continue;
    const seen = [j, j + 1, j + 2].filter((i) => i <= n), sum = seen.reduce((a, i) => a + vAt(i), 0);
    if (sum >= 2) { y = 1; k = j; needUpTo = seen[seen.length - 1]; break; }
    if (seen.length < SUSTAIN) { undecided = true; needUpTo = j + SUSTAIN - 1; break; }
  }
  const last = counted[Math.min(needUpTo, n) - 1];
  const future = reps.slice(origin + 1, last ? reps.indexOf(last) + 1 : reps.length);
  const bad = future.find((r) => !r.counted);
  if (bad) return { state: 'excluded', reason: 'invalid_rep_in_horizon', futureReps: future };
  if (undecided) return setEnded ? { state: 'excluded', reason: 'set_ended', futureReps: future } : { state: 'pending', futureReps: future };
  return { state: 'observed', y, onsetOffset: y ? k - t : null, futureReps: future.slice(0, horizon) };
}

// The page's existing reactive rule, evaluated as an alerting policy: it fires on the rep that is already slow.
export const SLOW_ASCENT_S = 2.2;
export function heuristicAlert(reps, t) {
  const counted = reps.filter((r) => r.counted).slice(0, t);
  const cur = counted[t - 1], earlier = counted.slice(0, -1).map((r) => r.tUp);
  if (!cur) return false;
  return cur.tUp > SLOW_ASCENT_S || (earlier.length >= 2 && cur.tUp > 1.6 * median(earlier));
}

// A model artifact: { features, mean, sd, coef, intercept, calibration? { a, b } }. Standardise, logit, sigmoid.
export const sigmoid = (z) => 1 / (1 + Math.exp(-z));
export function predictProb(artifact, x) {
  let z = artifact.intercept;
  artifact.features.forEach((f, i) => { const v = Number.isFinite(x[f]) ? x[f] : 0; z += artifact.coef[i] * ((v - artifact.mean[i]) / (artifact.sd[i] || 1)); });
  const p = sigmoid(z);
  return artifact.calibration ? sigmoid(artifact.calibration.a * Math.log(p / (1 - p)) + artifact.calibration.b) : p;
}

// Run-time forecaster for one set. Feed every attempt the counter produces; get back the forecast made at that rep (if
// any) and the outcomes it resolves. Forecasts are immutable records; outcomes are separate records that point at them.
export class Forecaster {
  constructor({ artifact = null, target = TARGETS[DEFAULT_TARGET], mode = 'shadow', threshold = artifact?.threshold ?? 0.5, uuid = () => crypto.randomUUID(), clock = () => Date.now() } = {}) {
    Object.assign(this, { artifact, target, mode, threshold, uuid, clock });
    this.horizon = artifact?.horizon ?? HORIZON;
    this.reps = []; this.forecasts = []; this.outcomes = []; this.open = []; this.lastCueRep = -Infinity; this.ended = false; this.bounds = null;
    this.state = { kind: 'baseline', have: 0, need: MIN_REPS };
  }

  get countedN() { return this.reps.filter((r) => r.counted).length; }

  // rep: the counter's record; tEnd: set-clock seconds at which it finished; delivered: optional callback(cueText) for coaching mode.
  onRep(rep, tEnd, { latencyMs = null } = {}) {
    if (this.ended) return { forecast: null, outcomes: [] };
    const started = performance.now();
    this.reps.push({ counted: !!rep.counted, tDown: rep.tDown ?? null, tUp: rep.tUp ?? null, secs: rep.secs ?? 0, depth: rep.depth ?? null, tEnd, n: rep.n ?? null });
    this.bounds = bounds(this.target, this.reps);
    const outcomes = this.#resolve();
    let forecast = null;
    if (rep.counted) {
      const t = this.countedN;
      const reason = ineligible(this.reps, t, this.target);
      if (reason === 'baseline') this.state = { kind: 'baseline', have: t, need: MIN_REPS };
      else if (reason === 'after_departure') this.state = { kind: 'departed', k: departureAt(this.reps, this.bounds).k };
      else if (reason) this.state = { kind: 'monitoring', note: reason };
      else if (!this.artifact) this.state = { kind: 'unavailable' };
      else {
        const x = featuresAt(this.reps, t, this.target);
        const p = predictProb(this.artifact, x);
        const pol = this.artifact.policy ?? { kind: 'logistic', threshold: this.threshold };
        const driftRatio = Math.abs(x.down_drift) / ((x.down_med - x.down_drift) || 1);
        const wantsCue = pol.kind === 'drift' ? driftRatio >= pol.theta : p >= this.threshold;
        const cooldown = t - this.lastCueRep < this.horizon; // one cue per horizon
        const action = !wantsCue ? 'silent' : this.mode !== 'coaching' ? 'suppressed' : cooldown ? 'suppressed' : 'cue';
        forecast = {
          predictionId: this.uuid(), repN: t, cutoffAt: new Date(this.clock()).toISOString(), emittedAt: new Date(this.clock()).toISOString(),
          features: x, probability: Math.round(p * 10000) / 10000, threshold: pol.kind === 'drift' ? null : this.threshold, policyKind: pol.kind, driftRatio: Math.round(driftRatio * 1000) / 1000, action,
          suppressedReason: action === 'suppressed' ? (this.mode !== 'coaching' ? 'shadow_mode' : 'cooldown') : null,
          mode: this.mode, modelRun: this.artifact.modelRun, targetId: this.target.id, labelVersion: LABEL_VERSION, featureVersion: FEATURE_VERSION,
          policyVersion: POLICY_VERSION, horizon: this.horizon, latencyMs: latencyMs ?? Math.round((performance.now() - started) * 100) / 100, deliveredAt: null,
        };
        if (action === 'cue') { this.lastCueRep = t; forecast.deliveredAt = forecast.emittedAt; }
        this.forecasts.push(forecast); this.open.push({ forecast, t });
        this.state = { kind: action === 'cue' ? 'cue' : 'monitoring', probability: p, forecast };
      }
    }
    return { forecast, outcomes };
  }

  // Resolve every open forecast whose horizon the attempts now cover.
  #resolve(setEnded = false) {
    const done = [];
    this.open = this.open.filter(({ forecast, t }) => {
      const lab = labelAt(this.reps, t, this.target, { setEnded, horizon: this.horizon });
      if (lab.state === 'pending') return true;
      const origin = this.reps.filter((r) => r.counted)[t - 1];
      const outcome = {
        predictionId: forecast.predictionId, labelVersion: LABEL_VERSION, state: lab.state, outcome: lab.state === 'observed' ? lab.y : null,
        exclusionReason: lab.reason ?? null, onsetOffset: lab.onsetOffset ?? null,
        futureReps: lab.futureReps.map((r) => ({ n: r.n, counted: r.counted, down: r.tDown, violates: r.counted ? violates(r.tDown, this.bounds) : null, tEnd: r.tEnd })),
        leadSecs: lab.onsetOffset ? Math.round((lab.futureReps[lab.onsetOffset - 1].tEnd - origin.tEnd) * 10) / 10 : null,
        observedAt: new Date(this.clock()).toISOString(), coached: forecast.action === 'cue',
      };
      this.outcomes.push(outcome); done.push(outcome);
      return false;
    });
    return done;
  }

  // The set is over: anything still open is excluded as set_ended. Returns those outcomes.
  end() {
    if (this.ended) return [];
    this.ended = true;
    this.state = { kind: 'ended' };
    return this.#resolve(true);
  }
}

// Text for the card and the voice, by state. Probabilities are never spoken; the cue names the criterion and an action.
// b: the set's bounds (see bounds()).
export function cueText(b, horizon = HORIZON) {
  return { cue: 'Your lowering pace may drift on the next reps. Keep the same rhythm on the way down.', why: `Forecast: lowering leaves ${b?.L ?? '?'} to ${b?.U ?? '?'} s and stays out, starting within the next ${horizon} reps.` };
}

// Short-horizon tempo forecasting for squats: after a counted rep, estimate the probability that the lowering phase of
// one of the next two reps falls outside the programme's tempo range, then decide whether that is worth a cue.
// Pure logic, shared by the page (live and replay) and by hrt/train.mjs (offline evaluation), so the features a model
// was trained on are, by construction, the features it sees at run time. Nothing here looks past the current rep.

export const LABEL_VERSION = 'tempo-v1';
export const FEATURE_VERSION = 'f1';
export const HORIZON = 2;      // reps
export const MIN_REPS = 3;     // counted reps before the first forecast
export const WINDOW = 3;       // rolling window of recent reps
export const POLICY_VERSION = 'budget-v1';

// Programme tempo targets for the lowering phase, in seconds. A target is a prescription, not a definition of safe or
// correct technique. "controlled" is the default; the range was frozen before the evaluation (see docs/HRT.md).
export const TARGETS = {
  controlled: { id: 'controlled-v1', label: 'Controlled lowering, 0.6 to 1.5 s', L: 0.6, U: 1.5 },
  slow: { id: 'slow-v1', label: 'Slow eccentric, 2 to 4 s', L: 2.0, U: 4.0 },
};
export const DEFAULT_TARGET = 'controlled';

export const FEATURES = ['down', 'down_med', 'down_trend', 'down_range', 'margin', 'up', 'up_trend', 'rep_n', 'elapsed', 'depth_trend', 'depth_missing'];
export const FEATURE_SETS = { // for the ablations and the set-position baseline
  position: ['rep_n', 'elapsed'],
  tempo: ['down', 'down_med', 'down_trend', 'down_range', 'margin', 'up', 'up_trend', 'rep_n', 'elapsed'],
  full: FEATURES,
};

export const violates = (down, target) => !(Number.isFinite(down) && down >= target.L && down <= target.U);
const median = (a) => { const s = [...a].sort((x, y) => x - y); const m = s.length >> 1; return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2; };
const last = (a, n) => a.slice(Math.max(0, a.length - n));

// reps: every attempt of the set in order, counted or not, each with { counted, tDown, tUp, secs, depth, tEnd }.
// t: 1-based index among counted reps (the origin). Returns the feature vector for the origin, or null before MIN_REPS.
export function featuresAt(reps, t, target) {
  const counted = reps.filter((r) => r.counted);
  if (t < MIN_REPS || t > counted.length) return null;
  const seen = counted.slice(0, t), cur = seen[t - 1], prev = seen.slice(0, -1);
  const downs = seen.map((r) => r.tDown), ups = seen.map((r) => r.tUp);
  const recentDown = last(downs, WINDOW), prevDown = last(prev.map((r) => r.tDown), WINDOW), prevUp = last(prev.map((r) => r.tUp), WINDOW);
  const prevDepth = prev.map((r) => r.depth).filter(Number.isFinite);
  const depthKnown = Number.isFinite(cur.depth) && prevDepth.length > 0;
  const setStart = seen[0].tEnd - seen[0].secs; // the set clock starts when the first rep began, live and offline alike
  return {
    down: cur.tDown,
    down_med: median(recentDown),
    down_trend: cur.tDown - median(prevDown),
    down_range: Math.max(...recentDown) - Math.min(...recentDown),
    margin: Math.min(cur.tDown - target.L, target.U - cur.tDown) / (target.U - target.L),
    up: cur.tUp,
    up_trend: cur.tUp - median(prevUp),
    rep_n: t,
    elapsed: cur.tEnd - setStart,
    depth_trend: depthKnown ? cur.depth - median(last(prevDepth, WINDOW)) : 0,
    depth_missing: depthKnown ? 0 : 1,
  };
}

// Why a forecast is not made at this origin, or null when it is eligible.
export function ineligible(reps, t, target) {
  const counted = reps.filter((r) => r.counted);
  if (t < MIN_REPS) return 'baseline';
  if (violates(counted[t - 1]?.tDown, target)) return 'current_rep_outside_target';
  return null;
}

// The outcome of a forecast made after counted rep t, given the attempts seen so far. Observed only when the next two
// physical attempts are both counted reps; an uncounted attempt in the horizon or the end of the set excludes it.
export function labelAt(reps, t, target, { setEnded = false } = {}) {
  const counted = reps.filter((r) => r.counted);
  const origin = reps.indexOf(counted[t - 1]);
  if (origin < 0) return { state: 'pending' };
  const future = reps.slice(origin + 1, origin + 1 + HORIZON);
  const bad = future.find((r) => !r.counted);
  if (bad) return { state: 'excluded', reason: 'invalid_rep_in_horizon', futureReps: future };
  if (future.length < HORIZON) return setEnded ? { state: 'excluded', reason: 'set_ended', futureReps: future } : { state: 'pending', futureReps: future };
  const v = future.map((r) => violates(r.tDown, target) ? 1 : 0);
  const onset = v.indexOf(1);
  return { state: 'observed', y: onset >= 0 ? 1 : 0, onsetOffset: onset >= 0 ? onset + 1 : null, futureReps: future };
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
    this.reps = []; this.forecasts = []; this.outcomes = []; this.open = []; this.lastCueRep = -Infinity; this.ended = false;
    this.state = { kind: 'baseline', have: 0, need: MIN_REPS };
  }

  get countedN() { return this.reps.filter((r) => r.counted).length; }

  // rep: the counter's record; tEnd: set-clock seconds at which it finished; delivered: optional callback(cueText) for coaching mode.
  onRep(rep, tEnd, { latencyMs = null } = {}) {
    if (this.ended) return { forecast: null, outcomes: [] };
    const started = performance.now();
    this.reps.push({ counted: !!rep.counted, tDown: rep.tDown ?? null, tUp: rep.tUp ?? null, secs: rep.secs ?? 0, depth: rep.depth ?? null, tEnd, n: rep.n ?? null });
    const outcomes = this.#resolve();
    let forecast = null;
    if (rep.counted) {
      const t = this.countedN;
      const reason = ineligible(this.reps, t, this.target);
      if (reason === 'baseline') this.state = { kind: 'baseline', have: t, need: MIN_REPS };
      else if (reason) this.state = { kind: 'monitoring', note: reason };
      else if (!this.artifact) this.state = { kind: 'unavailable' };
      else {
        const x = featuresAt(this.reps, t, this.target);
        const p = predictProb(this.artifact, x);
        const wantsCue = p >= this.threshold;
        const cooldown = t - this.lastCueRep < HORIZON; // one cue per horizon
        const action = !wantsCue ? 'silent' : this.mode !== 'coaching' ? 'suppressed' : cooldown ? 'suppressed' : 'cue';
        forecast = {
          predictionId: this.uuid(), repN: t, cutoffAt: new Date(this.clock()).toISOString(), emittedAt: new Date(this.clock()).toISOString(),
          features: x, probability: Math.round(p * 10000) / 10000, threshold: this.threshold, action,
          suppressedReason: action === 'suppressed' ? (this.mode !== 'coaching' ? 'shadow_mode' : 'cooldown') : null,
          mode: this.mode, modelRun: this.artifact.modelRun, targetId: this.target.id, labelVersion: LABEL_VERSION, featureVersion: FEATURE_VERSION,
          policyVersion: POLICY_VERSION, horizon: HORIZON, latencyMs: latencyMs ?? Math.round((performance.now() - started) * 100) / 100, deliveredAt: null,
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
      const lab = labelAt(this.reps, t, this.target, { setEnded });
      if (lab.state === 'pending') return true;
      const origin = this.reps.filter((r) => r.counted)[t - 1];
      const outcome = {
        predictionId: forecast.predictionId, labelVersion: LABEL_VERSION, state: lab.state, outcome: lab.state === 'observed' ? lab.y : null,
        exclusionReason: lab.reason ?? null, onsetOffset: lab.onsetOffset ?? null,
        futureReps: lab.futureReps.map((r) => ({ n: r.n, counted: r.counted, down: r.tDown, violates: r.counted ? violates(r.tDown, this.target) : null, tEnd: r.tEnd })),
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
export function cueText(target) {
  return { cue: 'Your lowering pace may drift on the next reps. Keep the same rhythm on the way down.', why: `Forecast: lowering outside ${target.L} to ${target.U} s within the next ${HORIZON} reps.` };
}

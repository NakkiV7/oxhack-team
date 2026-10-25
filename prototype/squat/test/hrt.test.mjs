import test from 'node:test';
import assert from 'node:assert/strict';
import { TARGETS, HORIZON, MIN_REPS, FEATURES, violates, featuresAt, ineligible, labelAt, heuristicAlert, predictProb, Forecaster, cueText } from '../hrt.mjs';

const T = TARGETS.controlled;
// A set as the counter would report it: counted reps with lowering/rising durations, plus one shallow attempt.
const rep = (n, tDown, tUp, tEnd, extra = {}) => ({ n, counted: true, tDown, tUp, secs: Math.round((tDown + tUp) * 10) / 10, depth: 0.02, tEnd, ...extra });
const SET = [rep(1, 1.0, 0.8, 3.0), rep(2, 1.1, 0.8, 6.0), rep(3, 0.9, 0.9, 9.0), rep(4, 1.0, 1.0, 12.0), rep(5, 0.5, 1.2, 14.5), rep(6, 0.4, 1.4, 17.0)];
const artifact = { modelRun: 'test', features: FEATURES, mean: FEATURES.map(() => 0), sd: FEATURES.map(() => 1), coef: FEATURES.map(() => 0), intercept: 0, threshold: 0.5 };

test('target boundaries are inclusive and a missing duration always violates', () => {
  assert.equal(violates(0.6, T), false); assert.equal(violates(1.5, T), false);
  assert.equal(violates(0.59, T), true); assert.equal(violates(1.51, T), true);
  assert.equal(violates(null, T), true); assert.equal(violates(NaN, T), true);
});

test('features need three counted reps and use only reps up to the origin', () => {
  assert.equal(featuresAt(SET, 2, T), null);
  const x = featuresAt(SET, 4, T);
  assert.deepEqual(Object.keys(x), FEATURES);
  assert.equal(x.down, 1.0); assert.equal(x.down_med, 1.0); assert.equal(x.down_trend, 0); // median of 1.0, 1.1, 0.9 is 1.0
  assert.equal(Math.round(x.down_range * 10) / 10, 0.2); assert.equal(Math.round(x.margin * 100) / 100, Math.round((0.4 / 0.9) * 100) / 100);
  assert.equal(x.rep_n, 4); assert.equal(Math.round(x.elapsed * 10) / 10, 10.8); // 12.0 minus the start of rep 1 (3.0 - 1.8)
  assert.equal(x.depth_missing, 0);
  const later = SET.map((r, i) => (i >= 4 ? { ...r, tDown: 9 } : r)); // changing future reps cannot change the origin's features
  assert.deepEqual(featuresAt(later, 4, T), x);
});

test('missing depth is flagged rather than guessed', () => {
  const x = featuresAt(SET.map((r) => ({ ...r, depth: null })), 3, T);
  assert.equal(x.depth_trend, 0); assert.equal(x.depth_missing, 1);
});

test('eligibility: baseline first, then the current rep must meet the target', () => {
  assert.equal(ineligible(SET, 2, T), 'baseline');
  assert.equal(ineligible(SET, 4, T), null);
  assert.equal(ineligible(SET, 5, T), 'current_rep_outside_target');
});

test('labels cover exactly the next two physical attempts', () => {
  assert.deepEqual(labelAt(SET, 3, T).state, 'observed'); assert.equal(labelAt(SET, 3, T).y, 1); assert.equal(labelAt(SET, 3, T).onsetOffset, 2); // rep 5 violates
  assert.equal(labelAt(SET, 4, T).onsetOffset, 1); // rep 5 is next
  assert.equal(labelAt(SET.slice(0, 4), 2, T).y, 0);
  assert.equal(labelAt(SET.slice(0, 4), 3, T).state, 'pending');
  assert.deepEqual(labelAt(SET.slice(0, 4), 3, T, { setEnded: true }), { state: 'excluded', reason: 'set_ended', futureReps: [SET[3]] });
  const withAttempt = [...SET.slice(0, 4), { counted: false, secs: 0.8, tEnd: 13 }, SET[4]];
  assert.equal(labelAt(withAttempt, 4, T).reason, 'invalid_rep_in_horizon');
  assert.equal(labelAt(withAttempt, 3, T).state, 'excluded'); // rep 4 then the attempt: the attempt sits inside the horizon
});

test('an uncounted attempt inside the horizon excludes the origin, not skips it', () => {
  const withAttempt = [SET[0], SET[1], SET[2], { counted: false, secs: 0.8, tEnd: 10 }, SET[3], SET[4]];
  assert.equal(labelAt(withAttempt, 3, T).state, 'excluded');
});

test('the existing slow-ascent rule as an alert', () => {
  assert.equal(heuristicAlert(SET, 3), false);
  assert.equal(heuristicAlert([rep(1, 1, 0.8, 2), rep(2, 1, 0.8, 4), rep(3, 1, 2.3, 7)], 3), true); // over 2.2 s
  assert.equal(heuristicAlert([rep(1, 1, 0.5, 2), rep(2, 1, 0.5, 4), rep(3, 1, 0.9, 7)], 3), true); // over 1.6 x median earlier
});

test('predictProb standardises and stays inside (0, 1)', () => {
  const a = { ...artifact, coef: FEATURES.map((f) => (f === 'down_trend' ? 3 : 0)), mean: FEATURES.map((f) => (f === 'down_trend' ? 0.1 : 0)), sd: FEATURES.map((f) => (f === 'down_trend' ? 0.2 : 1)) };
  const p = predictProb(a, { down_trend: 0.3 }); // z = 3 * (0.3 - 0.1) / 0.2 = 3
  assert.ok(Math.abs(p - 1 / (1 + Math.exp(-3))) < 1e-9);
  assert.ok(predictProb({ ...a, intercept: 20 }, {}) < 1 && predictProb({ ...a, intercept: -20 }, {}) > 0);
  assert.ok(Math.abs(predictProb(a, { down_trend: NaN }) - 1 / (1 + Math.exp(1.5))) < 1e-9); // NaN is imputed as the training mean
});

const run = (mode, intercept, reps = SET, endIt = true) => {
  let id = 0;
  const f = new Forecaster({ artifact: { ...artifact, intercept }, mode, uuid: () => `p${++id}`, clock: () => 1_800_000_000_000 });
  const log = reps.map((r) => f.onRep(r, r.tEnd));
  const tail = endIt ? f.end() : [];
  return { f, log, tail };
};

test('shadow mode forecasts at every eligible origin and never cues', () => {
  const { f, log } = run('shadow', 2);
  assert.deepEqual(log.map((l) => l.forecast?.repN ?? null), [null, null, 3, 4, null, null]); // reps 5 and 6 are outside the target
  assert.ok(f.forecasts.every((x) => x.action === 'suppressed' && x.suppressedReason === 'shadow_mode' && x.probability > 0.5));
  assert.equal(f.state.kind, 'ended');
});

test('coaching mode cues above the threshold and holds for one horizon', () => {
  const longer = [...SET.slice(0, 4), rep(5, 1.0, 1.1, 15), rep(6, 1.0, 1.1, 18), rep(7, 1.0, 1.1, 21)];
  const { f } = run('coaching', 2, longer);
  assert.deepEqual(f.forecasts.map((x) => [x.repN, x.action]), [[3, 'cue'], [4, 'suppressed'], [5, 'cue'], [6, 'suppressed'], [7, 'cue']]);
  assert.equal(f.forecasts[1].suppressedReason, 'cooldown');
  assert.ok(f.forecasts[0].deliveredAt && !f.forecasts[1].deliveredAt);
});

test('below the threshold the forecast is recorded as silent', () => {
  const { f } = run('coaching', -2);
  assert.ok(f.forecasts.length >= 2 && f.forecasts.every((x) => x.action === 'silent' && x.probability < 0.5));
});

test('outcomes link to forecasts, carry lead time, and ending the set excludes open ones', () => {
  const { f, log, tail } = run('shadow', 0);
  const byId = Object.fromEntries(f.outcomes.map((o) => [o.predictionId, o]));
  assert.deepEqual(log[4].outcomes.map((o) => o.predictionId), ['p1']); // after rep 5 the forecast at rep 3 resolves
  assert.equal(byId.p1.outcome, 1); assert.equal(byId.p1.onsetOffset, 2); assert.equal(byId.p1.leadSecs, 5.5); // rep 5 ends 14.5, origin rep 3 ends 9.0
  assert.equal(log[5].outcomes[0].predictionId, 'p2'); assert.equal(byId.p2.onsetOffset, 1); assert.equal(byId.p2.leadSecs, 2.5);
  assert.deepEqual(tail, []); // nothing left open: reps 5 and 6 were never origins
  const short = run('shadow', 0, SET.slice(0, 4));
  assert.equal(short.tail.length, 2); assert.ok(short.tail.every((o) => o.state === 'excluded' && o.exclusionReason === 'set_ended')); // origins at reps 3 and 4 were open
  assert.equal(short.f.onRep(SET[4], 14.5).forecast, null); // nothing after end
});

test('forecast records are immutable and features match the offline definition', () => {
  const { f } = run('shadow', 0);
  const snapshot = JSON.stringify(f.forecasts[0]);
  assert.deepEqual(f.forecasts[0].features, featuresAt(SET, 3, T));
  f.end();
  assert.equal(JSON.stringify(f.forecasts[0]), snapshot);
  assert.ok(f.forecasts[0].latencyMs >= 0 && f.forecasts[0].latencyMs < 50);
});

test('without a model the forecaster reports unavailable and still tracks the baseline', () => {
  const f = new Forecaster({ artifact: null, mode: 'shadow' });
  SET.slice(0, 2).forEach((r) => f.onRep(r, r.tEnd));
  assert.deepEqual(f.state, { kind: 'baseline', have: 2, need: MIN_REPS });
  f.onRep(SET[2], 9);
  assert.equal(f.state.kind, 'unavailable'); assert.equal(f.forecasts.length, 0);
});

test('cue text names the criterion and the horizon, never a probability', () => {
  const t = cueText(T);
  assert.match(t.why, new RegExp(`${T.L} to ${T.U} s`)); assert.match(t.why, new RegExp(`${HORIZON} reps`));
  assert.doesNotMatch(t.cue + t.why, /%/);
});

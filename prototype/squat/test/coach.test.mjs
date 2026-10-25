import test from 'node:test';
import assert from 'node:assert/strict';
import { CATALOG, capability, contractFor, prerequisites, validateProgramme, fallbackProgramme, placeStart, compare, deterministicCue, evaluateNode, progressFor, sessionFacts, weekBounds, weeklyFacts, validateGoals, CONTRACTS } from '../coach.mjs';
import { CoachLoop } from '../coach-loop.mjs';
import { createCoachAI, numbersOk } from '../coach-gemini.mjs';
import { saveAttempt, saveAttemptAndProgress, claimWeeklyReport } from '../coach-store.mjs';

const SQ = CONTRACTS.squat;
const rep = (n, down, extra = {}) => ({ n, counted: true, tDown: down, tUp: 0.8, secs: down + 0.8, travel: 0.5, depth: 0.05, ...extra });

test('capabilities: squats are assessed in this app, push-ups are camera-counted elsewhere, everything else is practice', () => {
  assert.equal(capability('squat'), 'assessable'); assert.equal(capability('pushup'), 'counting');
  for (const id of ['wallPushup', 'inclinePushup', 'kneePushup', 'closeGripPushup', 'reverseLunge']) assert.equal(capability(id), 'practice-only');
  assert.equal(contractFor('kneePushup'), null); assert.equal(contractFor('squat').metric, 'down');
  assert.deepEqual(prerequisites('pushup'), ['kneePushup', 'plank']); assert.deepEqual(prerequisites('squat'), ['gluteBridge']);
  assert.equal(CATALOG.length, 19);
});

test('fallback programme validates, places beginners at the foundation and experienced people at the assessable node', () => {
  const beginner = fallbackProgramme({ goal: 'squat', ability: 'beginner' });
  assert.ok(validateProgramme(beginner, { goal: 'squat' }).ok, validateProgramme(beginner).errors.join('; '));
  assert.equal(beginner.start, 'gluteBridge'); assert.equal(beginner.nodes.filter((n) => n.optional).length, 1);
  const inter = fallbackProgramme({ goal: 'squat', ability: 'intermediate' });
  assert.equal(inter.start, 'squat'); assert.ok(inter.nodes.find((n) => n.id === 'gluteBridge').notRequired);
  assert.ok(validateProgramme(inter).ok);
  const push = fallbackProgramme({ goal: 'pushup', ability: 'beginner', equipment: ['wall', 'raised surface'] });
  assert.equal(push.start, 'wallPushup'); assert.ok(validateProgramme(push, { equipment: ['wall', 'raised surface'] }).ok, validateProgramme(push, { equipment: ['wall', 'raised surface'] }).errors.join('; '));
  assert.ok(validateProgramme(push, { equipment: ['raised surface'] }).errors.some((e) => /wall/.test(e))); // wall push-ups need a wall
});

test('programme validation catches invented ids, bad links, cycles and unreachable goals', () => {
  const bad = { goal: 'squat', nodes: [{ id: 'a', exerciseId: 'flyingSquat', prerequisites: [] }, { id: 'squat', exerciseId: 'squat', prerequisites: ['splitSquat'] }, { id: 'splitSquat', exerciseId: 'splitSquat', prerequisites: ['squat'] }, { id: 'gluteBridge', exerciseId: 'gluteBridge', prerequisites: [] }], start: 'gluteBridge', goalNode: 'nowhere' };
  const v = validateProgramme(bad);
  assert.ok(!v.ok); assert.ok(v.errors.some((e) => /unknown exercise/.test(e))); assert.ok(v.errors.some((e) => /cycle/.test(e))); assert.ok(v.errors.some((e) => /goal node missing/.test(e)));
  const wrongLink = { goal: 'squat', nodes: [{ id: 'gluteBridge', exerciseId: 'gluteBridge', prerequisites: [] }, { id: 'squat', exerciseId: 'squat', prerequisites: ['gluteBridge'] }, { id: 'plank', exerciseId: 'plank', prerequisites: [] }, { id: 'reverseLunge', exerciseId: 'reverseLunge', prerequisites: ['plank'] }], start: 'gluteBridge', goalNode: 'reverseLunge' };
  assert.ok(validateProgramme(wrongLink).errors.some((e) => /not an allowed progression link/.test(e)));
});

test('comparison uses medians over all valid reps, needs three per phase, and refuses a shorter retry', () => {
  const base = [rep(1, 0.8), rep(2, 0.9), rep(3, 0.7)], better = [rep(4, 1.4), rep(5, 1.5), rep(6, 1.6)];
  const c = compare(base, better, SQ);
  assert.equal(c.classification, 'closer'); assert.equal(c.baselineMedian, 0.8); assert.equal(c.retryMedian, 1.5); assert.equal(c.retryMeets, true); assert.equal(c.baselineMeets, false);
  assert.equal(compare(base, [rep(4, 0.8), rep(5, 0.9), rep(6, 0.7)], SQ).classification, 'similar');
  assert.equal(compare(base, [rep(4, 0.5), rep(5, 0.4), rep(6, 0.5)], SQ).classification, 'further');
  assert.equal(compare(base.slice(0, 2), better, SQ).classification, 'unable');
  const shallow = better.map((r) => ({ ...r, travel: 0.3 }));
  assert.equal(compare(base, shallow, SQ).classification, 'unable'); assert.match(compare(base, shallow, SQ).reason, /less range/);
  assert.equal(compare(base, [...better, rep(7, 9, { counted: false })], SQ).retryN, 3); // uncounted reps never enter
  const already = [rep(1, 1.5), rep(2, 1.45), rep(3, 1.55)];
  assert.equal(compare(already, already, SQ).baselineMeets, true); // maintain-target case
});

test('deterministic cue names the direction and the maintain case', () => {
  assert.equal(deterministicCue(SQ, [rep(1, 0.8), rep(2, 0.9), rep(3, 0.7)]).action, 'cue_target');
  assert.equal(deterministicCue(SQ, [rep(1, 1.5), rep(2, 1.5), rep(3, 1.6)]).action, 'maintain_target');
  assert.equal(deterministicCue(SQ, []).action, 'request_better_view');
});

test('node contract: first completion needs one qualifying attempt, consistency needs two calendar days; rewards are idempotent', () => {
  const ok = (at, retryMeets = true) => ({ attemptId: 'a' + at, workoutId: 'w', createdAt: at, outcome: { classification: 'closer', retryMeets, baselineMeets: false } });
  const one = progressFor(SQ, [ok('2026-10-25T10:00:00Z')], 2);
  assert.deepEqual([one.verification, one.badges, one.xp], ['first_completion', ['first-completion'], 2 * 10 + 50]);
  const sameDay = progressFor(SQ, [ok('2026-10-25T10:00:00Z'), ok('2026-10-25T11:00:00Z')], 2);
  assert.equal(sameDay.verification, 'first_completion'); // two attempts on one day are not consistency
  const twoDays = progressFor(SQ, [ok('2026-10-25T10:00:00Z'), ok('2026-10-26T10:00:00Z')], 2);
  assert.deepEqual([twoDays.verification, twoDays.xp], ['consistent', 20 + 50 + 100]);
  assert.deepEqual(progressFor(SQ, [ok('2026-10-25T10:00:00Z', false)], 0).verification, 'none'); // improvement alone is not a pass
  assert.deepEqual(progressFor(null, [ok('2026-10-25T10:00:00Z')], 3).verification, 'none'); // practice-only nodes never verify
  assert.deepEqual(progressFor(SQ, [ok('2026-10-25T10:00:00Z')], 2), one); // same evidence, same row
});

test('the coaching loop walks setup to result and ignores late or foreign cues', () => {
  let t = 0; const loop = new CoachLoop({ contract: SQ, attemptId: '11111111-1111-4111-8111-111111111111', uuid: () => 'req-1', clock: () => ++t });
  assert.equal(loop.state, 'setup'); assert.equal(loop.onRep(rep(1, 0.8)), null); // reps before begin are ordinary training
  assert.ok(loop.begin());
  assert.deepEqual(loop.onRep(rep(1, 0.8)).event, 'baseline_rep'); loop.onRep(rep(2, 9, { counted: false })); loop.onRep(rep(3, 0.9));
  const done = loop.onRep(rep(4, 0.7));
  assert.equal(done.event, 'baseline_complete'); assert.equal(loop.state, 'preparing_cue'); assert.equal(loop.validCount('baseline'), 3); assert.equal(loop.baseline.length, 4);
  assert.equal(loop.cueReady({ action: 'cue_target', text: 'Slower' }, 'req-other'), false); // wrong request id
  assert.equal(loop.onRep(rep(5, 1.0)), null); // reps while waiting for the cue are not part of either phase
  assert.ok(loop.cueReady({ action: 'cue_target', text: 'Count to two on the way down.', provenance: 'gemini' }, 'req-1'));
  assert.equal(loop.state, 'cue_ready'); assert.equal(loop.target.value, 1.5); const frozen = JSON.stringify(loop.target);
  assert.ok(loop.startRetry()); assert.equal(loop.state, 'ready_to_retry');
  loop.onRep(rep(6, 1.4)); assert.equal(loop.state, 'retry'); loop.onRep(rep(7, 1.5));
  const res = loop.onRep(rep(8, 1.6));
  assert.equal(res.event, 'result'); assert.equal(loop.state, 'result'); assert.equal(res.outcome.classification, 'closer');
  assert.equal(JSON.stringify(loop.target), frozen); assert.equal(loop.cancel(), false); // a finished attempt stays finished
  const snap = loop.snapshot(); assert.equal(snap.status, 'result'); assert.equal(snap.retryReps.length, 3); assert.equal(snap.baselineReps[1].valid, false);
});

test('pause, camera change, cancel and the deterministic cue fallback', () => {
  const loop = new CoachLoop({ contract: SQ, uuid: () => 'r', clock: () => 1 });
  loop.begin(); [0.8, 0.9, 0.7].forEach((d, i) => loop.onRep(rep(i + 1, d)));
  assert.ok(loop.cueFailed()); assert.equal(loop.cue.provenance, 'deterministic'); assert.equal(loop.state, 'cue_ready');
  loop.startRetry(); assert.ok(loop.pause()); assert.equal(loop.state, 'paused'); assert.ok(loop.resume()); assert.equal(loop.state, 'ready_to_retry');
  const changed = loop.cameraChanged(); assert.equal(changed.outcome.classification, 'unable'); assert.match(changed.outcome.reason, /camera changed/);
  const l2 = new CoachLoop({ contract: SQ }); l2.begin(); assert.ok(l2.cancel()); assert.equal(l2.state, 'cancelled'); assert.equal(l2.onRep(rep(1, 1)), null);
});

test('session and weekly facts are calculated with ids and never divide by a zero baseline', () => {
  const workout = { workout_id: 'w', exercise: 'squat', variation: 'standard', source: 'camera', started_at: '2026-10-25T10:00:00Z', ended_at: '2026-10-25T10:02:30Z' };
  const reps = [{ rep_n: 1, counted: true, good: true, down_secs: 1.4, measured_at: '2026-10-25T10:00:10Z', faults: [] }, { rep_n: 2, counted: true, good: false, down_secs: 1.6, measured_at: '2026-10-25T10:00:14Z', faults: ['Deeper'] }, { rep_n: 0, counted: false, measured_at: '2026-10-25T10:00:18Z' }];
  const s = sessionFacts({ workout, reps, attempts: [], predictions: [{ state: 'observed', outcome: 0, action: 'silent' }] });
  assert.equal(s.facts.find((f) => f.id === 'duration').value, 150); assert.equal(s.facts.find((f) => f.id === 'reps').value, 2); assert.equal(s.facts.find((f) => f.id === 'lowering').value, 1.5);
  assert.equal(s.timeline.length, 2); assert.match(s.facts.find((f) => f.id === 'biometrics').text, /No heart-rate/);
  assert.deepEqual(weekBounds('2026-10-25T03:00:00Z', 'Europe/London'), { start: '2026-10-19', end: '2026-10-26', prevStart: '2026-10-12' }); // Sunday 25 Oct belongs to the week of Monday 19 Oct
  assert.equal(weekBounds('2026-10-25T23:30:00Z', 'Europe/London').start, '2026-10-19'); // 00:30 BST Monday 26 Oct? no: BST ended 25 Oct; 23:30 UTC is 23:30 GMT Sunday
  const cur = [{ workout, reps }], w = weeklyFacts({ current: cur, previous: [], attempts: [], nodeProgress: [], goals: [], period: { start: '2026-10-19', end: '2026-10-26' } });
  assert.match(w.facts.find((f) => f.id === 'vs_reps').text, /none recorded the week before/); assert.match(w.facts.find((f) => f.id === 'coverage').text, /not known to be inactive/);
  const base = weeklyFacts({ current: cur, previous: null, period: { start: '2026-10-19', end: '2026-10-26' } });
  assert.ok(base.facts.find((f) => f.id === 'baseline_week'));
});

test('goal validation keeps Gemini inside the programme and measurable kinds', () => {
  const prog = fallbackProgramme({ goal: 'squat', ability: 'beginner' });
  assert.ok(validateGoals([{ id: 'g1', kind: 'practice_node', text: 'Practise glute bridges twice', nodeId: 'gluteBridge', target: 2 }], prog, SQ).ok);
  assert.ok(!validateGoals([{ id: 'g1', kind: 'win_olympics', text: 'x', target: 1 }], prog).ok);
  assert.ok(!validateGoals([{ id: 'g1', kind: 'practice_node', text: 'x', nodeId: 'pullup', target: 2 }], prog).ok);
  assert.ok(!validateGoals([{ id: 'g1', kind: 'metric_target', text: 'x', target: 2 }], prog, null).ok);
});

test('Gemini outputs are validated semantically and fall back deterministically', async () => {
  const calls = [];
  const fake = (reply) => createCoachAI({ callGemini: async (body) => { calls.push(body); return { candidates: [{ content: { parts: [{ text: JSON.stringify(reply) }] } }] }; }, log: () => {} });
  const base = [{ repN: 1, valid: true, down: 0.8, travel: 0.5 }, { repN: 2, valid: true, down: 0.9, travel: 0.5 }, { repN: 3, valid: true, down: 0.7, travel: 0.5 }];
  const good = await fake({ action: 'cue_target', cue_text: 'Take 1.5 s on the way down, counting slowly.', brief_rationale: 'median 0.8 below 1.5 target', evidence_ids: ['rep:1', 'baseline_median'], target_id: 'squat-tempo-v1' }).selectCue({}, base, SQ, 'req');
  assert.equal(good.provenance, 'gemini'); assert.equal(good.action, 'cue_target');
  const invented = await fake({ action: 'cue_target', cue_text: 'You will be 40% stronger. Aim for 1.5 s.', brief_rationale: 'x', evidence_ids: ['rep:1'], target_id: 'squat-tempo-v1' }).selectCue({}, base, SQ, 'req');
  assert.equal(invented.provenance, 'deterministic'); // 40 is not a number in the evidence
  const badIds = await fake({ action: 'cue_target', cue_text: 'Slower.', brief_rationale: 'x', evidence_ids: ['rep:99'], target_id: 'squat-tempo-v1' }).selectCue({}, base, SQ, 'req');
  assert.equal(badIds.provenance, 'deterministic');
  const wrongMaintain = await fake({ action: 'maintain_target', cue_text: 'Keep it.', brief_rationale: 'x', evidence_ids: ['rep:1'], target_id: 'squat-tempo-v1' }).selectCue({}, base, SQ, 'req');
  assert.equal(wrongMaintain.provenance, 'deterministic'); // baseline does not meet the target, so maintain is wrong
  const none = await createCoachAI({ callGemini: async () => null, log: () => {} }).selectCue({}, base, SQ, 'req');
  assert.equal(none.provenance, 'deterministic'); assert.equal(none.requestId, 'req');
  const attempt = { exercise: 'squat', cue: { text: 'Slower' }, outcome: { classification: 'closer', baselineMedian: 0.8, retryMedian: 1.5, baselineError: 0.7, retryError: 0, target: 1.5, tolerance: 0.15, noiseTolerance: 0.075, unit: 's', baselineN: 3, retryN: 3 } };
  const ex = await fake({ explanation: 'Your retry median was 1.5 s against 0.8 s before, closer to the target.', next_action: 'practice_node', fact_ids: ['classification', 'retry'] }).explainResult({ node: null, contract: null }, attempt);
  assert.equal(ex.provenance, 'gemini');
  const override = await fake({ explanation: 'Actually this was further from target and you are safe now.', next_action: 'practice_node', fact_ids: ['classification'] }).explainResult({}, attempt);
  assert.equal(override.provenance, 'deterministic'); assert.match(override.text, /closer/);
  assert.ok(numbersOk('three reps at 1.5 s', [1.5])); assert.ok(!numbersOk('a 40% gain', [1.5]));
  const prog = await fake({ nodes: [{ id: 'x', exerciseId: 'nope', why: '', prerequisites: [], optional: false }], start: 'x', goalNode: 'x', rationale: '' }).generateProgramme({ survey: { goal: 'squat', ability: 'beginner' } });
  assert.equal(prog.provenance, 'catalogue-fallback'); assert.equal(calls.length >= 2, true); // one repair attempt, then the fallback
});

test('store writes are keyed and a finished attempt never moves backwards', async () => {
  const calls = []; const pool = { query: async (sql, params) => { calls.push({ sql, params }); return { rows: [{ ok: true }], rowCount: 1 }; }, connect: async () => ({ query: pool.query, release() {} }) };
  const a = { attemptId: '11111111-1111-4111-8111-111111111111', workoutId: '22222222-2222-4222-8222-222222222222', exercise: 'squat', variation: 'standard', contractVersion: 'squat-tempo-v1', status: 'result', outcome: { classification: 'closer' } };
  await saveAttempt(pool, 'nakki', a);
  assert.match(calls[0].sql, /ON CONFLICT \(attempt_id\) DO UPDATE/); assert.match(calls[0].sql, /status IN \('result', 'cancelled'\) THEN spottr_cv.coaching_attempt.status/);
  await assert.rejects(saveAttempt(pool, 'nakki', { ...a, attemptId: 'bad' }));
  await assert.rejects(saveAttempt(pool, 'bad user!', a));
  calls.length = 0;
  await saveAttemptAndProgress(pool, 'nakki', { ...a, programmeId: '33333333-3333-4333-8333-333333333333', nodeId: 'squat' }, { verification: 'first_completion', evidence: [], criteriaVersion: 'squat-tempo-v1', xp: 50, badges: ['first-completion'] });
  assert.deepEqual(calls.map((c) => c.sql.split(/\s+/)[0]), ['BEGIN', 'INSERT', 'UPDATE', 'SELECT', 'SELECT', 'COMMIT']); // attempt, progress, then the unlock pass, one transaction
  calls.length = 0;
  const claim = await claimWeeklyReport({ connect: async () => ({ query: async (sql, params) => { calls.push(sql); return sql.startsWith('SELECT * FROM') ? { rows: [{ report_id: 'r', status: 'ready' }] } : { rows: [{ v: 1 }] }; }, release() {} }) }, 'nakki', { reportId: 'x', periodStart: '2026-10-19', periodEnd: '2026-10-26', timezone: 'UTC', cutoffAt: 'now', fingerprint: 'abc' });
  assert.equal(claim.claimed, false); assert.equal(claim.row.report_id, 'r'); // same inputs: no second generation
});

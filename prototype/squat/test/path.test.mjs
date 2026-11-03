import test from 'node:test';
import assert from 'node:assert/strict';
import { CATALOG, capability, criteriaFor, bandOf, fallbackProgramme, placeStart, validateProgramme, validRoute, defaultRoute, defaultTarget, validTarget, levelFor, attributes, diffProgrammes, PRACTICE_COMPLETE } from '../coach.mjs';
import { createCoachAI } from '../coach-gemini.mjs';
import { logPractice, saveProgramme } from '../coach-store.mjs';
import { layout, edgesOf, nodeStatus } from '../coach-ui/map.mjs';

const ids = (g) => g.nodes.map((n) => n.id);
const cat = Object.fromEntries(CATALOG.map((e) => [e.id, e]));

test('criteria are versioned per capability and never claim assessment for practice steps', () => {
  assert.equal(criteriaFor('squat').version, 'squat-tempo-v1'); assert.equal(criteriaFor('squat').kind, 'camera');
  for (const id of ['pushup', 'kneePushup', 'plank']) { assert.equal(criteriaFor(id).kind, 'practice'); assert.match(criteriaFor(id).text, /self-reported/); }
});

test('survey answers map to placement bands, including "not sure"', () => {
  assert.equal(bandOf({ goal: 'squat', abilityKey: 'new' }), 'beginner');
  assert.equal(bandOf({ goal: 'squat', abilityKey: 'comfortable' }), 'advanced');
  assert.equal(bandOf({ goal: 'pushup', abilityKey: 'first' }), 'beginner');
  assert.equal(bandOf({ goal: 'pushup', abilityKey: 'unsure' }), 'unsure');
  assert.equal(bandOf({}), 'beginner');
});

test('different answers give different, valid paths', () => {
  const profiles = [
    { goal: 'squat', abilityKey: 'new', equipment: [], equipmentAnswered: true, minutes: 10, daysPerWeek: 2 },
    { goal: 'squat', abilityKey: 'comfortable', equipment: ['stable support'], equipmentAnswered: true, minutes: 30, daysPerWeek: 4 },
    { goal: 'squat', abilityKey: 'unsure', avoid: ['reverseLunge'], minutes: 20, daysPerWeek: 3 },
    { goal: 'pushup', abilityKey: 'notTried', equipment: ['wall', 'raised surface'], equipmentAnswered: true, daysPerWeek: 3 },
    { goal: 'pushup', abilityKey: 'few', equipment: [], equipmentAnswered: true, daysPerWeek: 5 },
  ];
  const out = profiles.map((s) => { const g = fallbackProgramme(s); const v = validateProgramme(g, s); assert.ok(v.ok, `${JSON.stringify(s)}: ${v.errors.join('; ')}`); assert.ok(validRoute(g)); return g; });
  assert.equal(out[0].start, 'gluteBridge'); assert.equal(out[1].start, 'squat'); assert.equal(out[2].start, 'gluteBridge');
  assert.ok(!ids(out[0]).includes('assistedSquat')); assert.ok(ids(out[1]).includes('assistedSquat')); // needs a stable support
  assert.ok(!ids(out[2]).includes('reverseLunge')); // left out on request
  assert.equal(out[3].start, 'wallPushup'); assert.ok(!ids(out[4]).some((id) => ['wallPushup', 'inclinePushup'].includes(id))); assert.equal(out[4].start, 'pushup');
  assert.notDeepEqual(out[0].nodes.find((n) => n.id === 'squat').practiceTarget, out[1].nodes.find((n) => n.id === 'squat').practiceTarget); // time and level change the prescription
  for (const g of out) assert.ok(g.nodes.filter((n) => n.optional).length <= 1);
});

test('placement: a camera check with three valid squats can move the start; fewer cannot', () => {
  const nodes = fallbackProgramme({ goal: 'squat' }).nodes, s = { goal: 'squat', abilityKey: 'unsure' };
  assert.equal(placeStart(s, nodes, 'squat').start, 'gluteBridge');
  const ok = placeStart(s, nodes, 'squat', { exercise: 'squat', validReps: 3 });
  assert.equal(ok.start, 'squat'); assert.equal(ok.source, 'camera-supported'); assert.deepEqual(ok.notRequired, ['gluteBridge']);
  assert.equal(placeStart(s, nodes, 'squat', { exercise: 'squat', validReps: 2 }).start, 'gluteBridge');
  assert.equal(placeStart({ goal: 'squat', abilityKey: 'comfortable', limitations: ['knees'] }, nodes, 'squat').start, 'gluteBridge');
});

test('validation rejects left-out movements, gating optional nodes, invented support links, oversized targets and broken routes', () => {
  const s = { goal: 'squat', abilityKey: 'new', daysPerWeek: 3 }, g = fallbackProgramme(s);
  assert.ok(validateProgramme(g, s).ok);
  assert.ok(validateProgramme(g, { ...s, avoid: ['splitSquat'] }).errors.some((e) => /leave this movement out/.test(e)));
  const opt = g.nodes.find((n) => n.optional);
  const gating = structuredClone(g); gating.nodes.find((n) => n.id === 'splitSquat').prerequisites.push(opt.id);
  assert.ok(validateProgramme(gating, s).errors.some((e) => /optional node cannot gate/.test(e)));
  const badSupport = structuredClone(g); badSupport.nodes.find((n) => n.optional).supports = 'gluteBridge';
  assert.ok(validateProgramme(badSupport, s).errors.some((e) => /not a catalogue support/.test(e)));
  const big = structuredClone(g); big.nodes[0].practiceTarget = { sets: 9, target: 400, perWeek: 7 };
  assert.ok(validateProgramme(big, s).errors.some((e) => /practice target/.test(e)));
  const route = structuredClone(g); route.route = [g.start, g.goalNode];
  assert.ok(validateProgramme(route, s).errors.some((e) => /route/.test(e)));
  assert.deepEqual(defaultRoute(g), g.route);
  assert.ok(validTarget(defaultTarget('squat', { minutes: 20, daysPerWeek: 3 }), 'squat', { daysPerWeek: 3 }));
});

test('levels are a game score with fixed thresholds', () => {
  assert.deepEqual(levelFor(0), { level: 1, xp: 0, floor: 0, next: 100 });
  assert.equal(levelFor(99).level, 1); assert.equal(levelFor(100).level, 2); assert.equal(levelFor(299).level, 2); assert.equal(levelFor(300).level, 3);
});

test('attributes come only from saved evidence and say "not assessed" without it', () => {
  const now = new Date('2026-10-25T12:00:00Z');
  const none = attributes({ attempts: [], practiceDays: [], survey: {}, now });
  assert.deepEqual(none.map((a) => a.value), [null, null, null]);
  const rep = (down) => ({ counted: true, valid: true, down });
  const attempt = { exercise: 'squat', created_at: '2026-10-25T10:00:00Z', status: 'result', baseline_reps: [rep(0.9), rep(1.0), rep(1.45)], retry_reps: [rep(1.5), rep(1.55), { counted: false, down: 3 }] };
  const a = attributes({ attempts: [attempt], practiceDays: [{ at: '2026-10-23T09:00:00Z' }], survey: { daysPerWeek: 3 }, now, tz: 'Europe/London' });
  const tempo = a.find((x) => x.key === 'tempo'), cons = a.find((x) => x.key === 'consistency'), prac = a.find((x) => x.key === 'practice');
  assert.equal(tempo.value, 60); assert.match(tempo.detail, /3 of 5 timed squats/); // 1.45, 1.5, 1.55 are within 0.15 s of 1.5
  assert.equal(tempo.evidence, 5); assert.ok(cons.value != null);
  assert.equal(prac.value, 67); assert.match(prac.detail, /2 of 3 planned sessions/); // one practice day plus one finished assessment day
  const old = attributes({ attempts: [{ ...attempt, created_at: '2026-08-01T10:00:00Z' }], survey: {}, now });
  assert.equal(old[0].value, null); // outside the 30-day window
});

test('a new version keeps earned progress; the diff says what changes', () => {
  const a = fallbackProgramme({ goal: 'squat', abilityKey: 'new' }), b = fallbackProgramme({ goal: 'squat', abilityKey: 'comfortable', avoid: ['reverseLunge'] });
  const d = diffProgrammes(a, b, [{ node_id: 'squat', verification: 'first_completion', practice_count: 1, xp: 60 }, { node_id: 'reverseLunge', verification: 'none', practice_count: 2, xp: 20 }]);
  assert.ok(d.removed.includes('reverseLunge')); assert.equal(d.start.from, 'gluteBridge'); assert.equal(d.start.to, 'squat');
  assert.deepEqual(d.carried.map((c) => c.nodeId), ['squat']); assert.deepEqual(d.archived.map((c) => c.nodeId), ['reverseLunge']);
});

test('Gemini paths are bounded: a start beyond the answers is pulled back, an invalid plan falls back to the catalogue', async () => {
  const reply = (j) => createCoachAI({ callGemini: async () => ({ candidates: [{ content: { parts: [{ text: JSON.stringify(j) }] } }] }), log: () => {} });
  const t = (sets = 3, target = 8, perWeek = 3) => ({ sets, target, perWeek });
  const plan = { start: 'reverseLunge', goalNode: 'splitSquat', route: ['reverseLunge', 'splitSquat'], rationale: 'Fits.', startReason: 'Here.', emphasis: 'Control.', nodes: [
    { id: 'gluteBridge', exerciseId: 'gluteBridge', why: 'Base.', prerequisites: [], optional: false, practiceTarget: t() },
    { id: 'squat', exerciseId: 'squat', why: 'Camera.', prerequisites: ['gluteBridge'], optional: false, practiceTarget: t() },
    { id: 'reverseLunge', exerciseId: 'reverseLunge', why: 'Next.', prerequisites: ['squat'], optional: false, practiceTarget: t() },
    { id: 'splitSquat', exerciseId: 'splitSquat', why: 'Goal.', prerequisites: ['reverseLunge'], optional: false, practiceTarget: t() },
    { id: 'singleLegBalance', exerciseId: 'singleLegBalance', why: 'Balance.', prerequisites: [], optional: true, supports: 'reverseLunge', practiceTarget: t(2, 20, 3) } ] };
  const ok = await reply(plan).generateProgramme({ survey: { goal: 'squat', abilityKey: 'new', daysPerWeek: 3 } });
  assert.equal(ok.provenance, 'gemini'); assert.equal(ok.graph.start, 'gluteBridge'); // a beginner cannot be started at lunges
  assert.deepEqual(ok.graph.route, ['gluteBridge', 'squat', 'reverseLunge', 'splitSquat']); assert.ok(ok.graph.routeRepaired);
  assert.equal(ok.rationale.emphasis, 'Control.');
  const exp = await reply(plan).generateProgramme({ survey: { goal: 'squat', abilityKey: 'comfortable', daysPerWeek: 3 } });
  assert.equal(exp.graph.start, 'squat'); assert.ok(exp.graph.nodes.find((n) => n.id === 'gluteBridge').notRequired);
  const bad = await reply({ ...plan, nodes: plan.nodes.map((n) => ({ ...n, practiceTarget: t(9, 99, 9) })) }).generateProgramme({ survey: { goal: 'squat', abilityKey: 'new', daysPerWeek: 3, equipment: [], equipmentAnswered: true } });
  assert.equal(bad.provenance, 'catalogue-fallback'); assert.ok(bad.rationale.geminiErrors.some((e) => /practice target/.test(e)));
  assert.ok(validateProgramme(bad.graph, { equipmentAnswered: true, equipment: [] }).ok);
});

test('practice counts once per step per day, in one transaction with the unlock pass', async () => {
  const calls = []; const pool = { query: async (sql, p) => { calls.push({ sql, p }); return { rows: sql.includes('RETURNING') ? [] : [{ graph: { nodes: [] } }] }; }, connect: async () => ({ query: pool.query, release() {} }) };
  const r = await logPractice(pool, { programmeId: '33333333-3333-4333-8333-333333333333', nodeId: 'plank', userId: 'nakki', tz: 'Europe/London', now: new Date('2026-10-25T23:30:00Z') });
  assert.equal(r.logged, false); assert.equal(r.key, 'plank:2026-10-25'); // 23:30 GMT is still the 25th in London after the clocks change
  assert.match(calls[1].sql, /NOT \(practice_workouts \? \$4::text\)/);
});

test('saving a version copies progress for matching steps and supersedes the old one', async () => {
  const calls = []; const prevId = '11111111-1111-4111-8111-111111111111';
  const pool = { connect: async () => ({ release() {}, query: async (sql, p) => { calls.push({ sql, p });
    if (/MAX\(version\)/.test(sql)) return { rows: [{ v: 2 }] };
    if (/status = 'active' ORDER BY version/.test(sql)) return { rows: [{ programme_id: prevId }] };
    if (/SELECT \* FROM spottr_cv.node_progress WHERE programme_id/.test(sql)) return { rows: [{ node_id: 'squat', practice_count: 2, practice_workouts: ['squat:2026-10-24'], practice_log: [], verification: 'first_completion', evidence: [{ attemptId: 'a' }], criteria_version: 'squat-tempo-v1', xp: 70, badges: ['first-completion'] }] };
    if (/INSERT INTO spottr_cv.programme/.test(sql)) return { rows: [{ programme_id: p[0], version: p[2] }] };
    if (/SELECT graph/.test(sql)) return { rows: [{ graph: { nodes: [] } }] };
    return { rows: [] }; } }) };
  const g = fallbackProgramme({ goal: 'squat', abilityKey: 'comfortable' });
  await saveProgramme(pool, 'nakki', { programmeId: '22222222-2222-4222-8222-222222222222', goal: 'squat', catalogVersion: 1, graph: g, rationale: {}, provenance: 'catalogue-fallback' });
  const squatRow = calls.find((c) => /INSERT INTO spottr_cv.node_progress/.test(c.sql) && c.p[1] === 'squat');
  assert.equal(squatRow.p[4], 2); assert.equal(squatRow.p[7], 'first_completion'); assert.equal(squatRow.p[10], 70);
  const bridge = calls.find((c) => /INSERT INTO spottr_cv.node_progress/.test(c.sql) && c.p[1] === 'gluteBridge');
  assert.equal(bridge.p[3], 'not_required'); assert.equal(bridge.p[7], 'none'); // not required is never verified
  assert.ok(calls.some((c) => /SET status = 'superseded'/.test(c.sql))); assert.equal(calls.at(-1).sql, 'COMMIT');
});

test('the map layout is deterministic, uses only real links, and keeps status apart from capability', () => {
  const g = fallbackProgramme({ goal: 'squat', abilityKey: 'new' });
  const a = layout(g, cat, 'h'), b = layout(g, cat, 'h');
  assert.deepEqual(a.pos, b.pos); assert.equal(a.chain[0], 'gluteBridge');
  const v = layout(g, cat, 'v'); assert.ok(v.pos.gluteBridge.y < v.pos.squat.y); // vertical: start at the top
  const e = edgesOf(g); assert.ok(e.every((x) => x.kind === 'support' || g.nodes.find((n) => n.id === x.to).prerequisites.includes(x.from)));
  assert.equal(nodeStatus({}, { availability: 'current', verification: 'none' }, { capability: 'assessable' }).key, 'current');
  assert.equal(nodeStatus({}, { availability: 'available', practice_count: PRACTICE_COMPLETE }, { capability: 'practice-only' }).key, 'practised');
  assert.equal(nodeStatus({}, { availability: 'available', practice_count: PRACTICE_COMPLETE }, { capability: 'assessable' }).key, 'available'); // practice never verifies a camera step
  assert.equal(nodeStatus({}, { availability: 'not_required' }, { capability: 'practice-only' }).key, 'skipped');
});

// Domain logic for the connected coaching journey: the exercise catalogue (mirrored from the native app, same ids and
// prerequisite rules), what the camera can actually assess, programme validation and the catalogue fallback, the
// baseline/retry comparison, node contracts and rewards, and the calculated facts behind session and weekly reports.
// Pure functions only; Gemini never computes a number here, it explains numbers computed here.

export const CATALOG_VERSION = 1;
// id, name, family, level, goal, unit, attribute, support needed, tracking (which camera assessor, if any)
export const CATALOG = [
  { id: 'wallPushup', name: 'Wall push-ups', family: 'push', level: 1, goal: 8, unit: 'reps', attribute: 'strength', support: 'wall', tracking: null, instruction: 'Keep your body straight. Bend your elbows toward the wall, then press away.' },
  { id: 'inclinePushup', name: 'Incline push-ups', family: 'push', level: 2, goal: 8, unit: 'reps', attribute: 'strength', support: 'raised surface', tracking: null, instruction: 'Use a stable raised surface. Keep your body in one line as you lower and press.' },
  { id: 'kneePushup', name: 'Knee push-ups', family: 'push', level: 3, goal: 8, unit: 'reps', attribute: 'strength', support: null, tracking: null, instruction: 'Rest your knees on the floor. Keep shoulders, hips and knees in one line.' },
  { id: 'pushup', name: 'Push-ups', family: 'push', level: 4, goal: 10, unit: 'reps', attribute: 'strength', support: null, tracking: 'pushup', instruction: 'Brace your body. Lower with control and return to extended arms.' },
  { id: 'closeGripPushup', name: 'Close-grip push-ups', family: 'push', level: 5, goal: 6, unit: 'reps', attribute: 'strength', support: null, tracking: null, instruction: 'Place your hands closer together under your chest. Keep elbows close to your sides.' },
  { id: 'gluteBridge', name: 'Glute bridges', family: 'legs', level: 1, goal: 12, unit: 'reps', attribute: 'strength', support: null, tracking: null, instruction: 'Plant your feet, lift your hips with control, then lower without arching your back.' },
  { id: 'squat', name: 'Squats', family: 'legs', level: 2, goal: 12, unit: 'reps', attribute: 'strength', support: null, tracking: 'squat', instruction: 'Sit back to a comfortable depth. Keep your feet planted and return to standing.' },
  { id: 'reverseLunge', name: 'Reverse lunges', family: 'legs', level: 3, goal: 8, unit: 'reps', attribute: 'balance', support: null, tracking: null, instruction: 'Step back, lower with control and return. Count each completed side as one rep.' },
  { id: 'splitSquat', name: 'Split squats', family: 'legs', level: 4, goal: 8, unit: 'reps', attribute: 'strength', support: null, tracking: null, instruction: 'Keep a stable split stance. Lower and rise without stepping. Alternate sides between sets.' },
  { id: 'assistedSquat', name: 'Assisted single-leg squats', family: 'legs', level: 5, goal: 5, unit: 'reps', attribute: 'balance', support: 'stable support', tracking: null, instruction: 'Hold a stable support. Use a comfortable single-leg range and rise with control.' },
  { id: 'deadBug', name: 'Dead bugs', family: 'core', level: 1, goal: 8, unit: 'reps', attribute: 'balance', support: null, tracking: null, instruction: 'Lie on your back. Slowly extend opposite arm and leg, then return. Count each side.' },
  { id: 'plank', name: 'Forearm plank', family: 'core', level: 2, goal: 20, unit: 'seconds', attribute: 'stamina', support: null, tracking: null, instruction: 'Rest on forearms and toes. Keep your body in one line and breathe steadily.' },
  { id: 'sidePlank', name: 'Side plank', family: 'core', level: 3, goal: 15, unit: 'seconds', attribute: 'balance', support: null, tracking: null, instruction: 'Support yourself on one forearm and the side of your feet. Alternate sides between sets.' },
  { id: 'stepJack', name: 'Step jacks', family: 'conditioning', level: 1, goal: 20, unit: 'reps', attribute: 'stamina', support: null, tracking: null, instruction: 'Step one foot out while raising your arms. Return and alternate sides.' },
  { id: 'highKnees', name: 'High knees', family: 'conditioning', level: 2, goal: 30, unit: 'seconds', attribute: 'stamina', support: null, tracking: null, instruction: 'March or jog in place, lifting alternate knees at a pace you can control.' },
  { id: 'mountainClimber', name: 'Mountain climbers', family: 'conditioning', level: 3, goal: 20, unit: 'reps', attribute: 'stamina', support: null, tracking: null, instruction: 'From a high plank, bring one knee forward and return. Alternate and count each knee drive.' },
  { id: 'catCow', name: 'Cat-cow', family: 'mobility', level: 1, goal: 6, unit: 'reps', attribute: 'mobility', support: null, tracking: null, instruction: 'On hands and knees, gently round and lengthen your back. One comfortable cycle is one rep.' },
  { id: 'hipFlexorStretch', name: 'Hip-flexor stretch', family: 'mobility', level: 2, goal: 30, unit: 'seconds', attribute: 'mobility', support: null, tracking: null, instruction: 'Use a half-kneeling stance and gently shift forward. Keep the stretch comfortable; alternate sides.' },
  { id: 'singleLegBalance', name: 'Single-leg stand', family: 'balance', level: 1, goal: 20, unit: 'seconds', attribute: 'balance', support: 'optional support', tracking: null, instruction: 'Stand on one leg near a stable support. Keep your gaze steady and alternate sides.' },
];
export const find = (id) => CATALOG.find((e) => e.id === id) ?? null;
// Supporting prerequisites across families, as in the native SkillGraph.
const SUPPORT = { pushup: ['plank'], closeGripPushup: ['sidePlank'], reverseLunge: ['singleLegBalance'], assistedSquat: ['hipFlexorStretch'], mountainClimber: ['plank'] };
export function prerequisites(id) {
  const e = find(id); if (!e) return [];
  const prev = CATALOG.find((x) => x.family === e.family && x.level === e.level - 1);
  return [...(prev ? [prev.id] : []), ...(SUPPORT[id] ?? [])];
}

// What the camera can judge. Only these two have a measured contract; everything else is practice-only.
export const CONTRACTS = {
  squat: { exerciseId: 'squat', variation: 'standard', version: 'squat-tempo-v1', metric: 'down', label: 'lowering time', unit: 's', target: 1.5, tolerance: 0.15,
    evidence: 'three counted reps with the lowering phase measured, hips and knees in frame', unableWhen: 'fewer than three counted reps, hips or knees out of frame, or the retry moves through much less range than the baseline',
    pass: 'median lowering time within 0.15 s of the 1.5 s target over three counted reps' },
  pushup: { exerciseId: 'pushup', variation: 'standard', version: 'pushup-cadence-v1', metric: 'secs', label: 'rep time', unit: 's', target: 2.0, tolerance: 0.25,
    evidence: 'three counted reps with the rep time measured, body line and elbow in frame', unableWhen: 'fewer than three counted reps or tracking lost', pass: 'median rep time within 0.25 s of the 2.0 s target over three counted reps' },
};
export const capability = (exerciseId) => (CONTRACTS[find(exerciseId)?.tracking] ? 'assessable' : 'practice-only');
export const contractFor = (exerciseId) => CONTRACTS[find(exerciseId)?.tracking] ?? null;

// ---------- programme ----------
export const PROGRAMME_LIMITS = { minNodes: 4, maxNodes: 6, maxOptional: 1 };
const EQUIPMENT_FOR = { wall: 'wall', 'raised surface': 'raised surface', 'stable support': 'stable support', 'optional support': null };

// A generated graph: { goal: 'squat'|'pushup', nodes: [{ id, exerciseId, why, prerequisites: [nodeIds], optional, notRequired }], start, goalNode }.
// Returns { ok, errors }. Every rule here is one Gemini could break: unknown ids, invented links, cycles, an unreachable start.
export function validateProgramme(graph, survey = {}) {
  const errors = [];
  if (!graph || !Array.isArray(graph.nodes)) return { ok: false, errors: ['graph.nodes missing'] };
  const nodes = graph.nodes, ids = new Set(nodes.map((n) => n.id));
  if (ids.size !== nodes.length) errors.push('duplicate node ids');
  if (nodes.length < PROGRAMME_LIMITS.minNodes || nodes.length > PROGRAMME_LIMITS.maxNodes) errors.push(`expected ${PROGRAMME_LIMITS.minNodes} to ${PROGRAMME_LIMITS.maxNodes} nodes, got ${nodes.length}`);
  if (nodes.filter((n) => n.optional).length > PROGRAMME_LIMITS.maxOptional) errors.push('more than one optional branch');
  const equipment = new Set(survey.equipment ?? []);
  for (const n of nodes) {
    const e = find(n.exerciseId);
    if (!e) { errors.push(`unknown exercise ${n.exerciseId}`); continue; }
    if (n.assessable != null && n.assessable !== (capability(e.id) === 'assessable')) errors.push(`${n.id}: assessable flag does not match capability`);
    const need = e.support ? EQUIPMENT_FOR[e.support] : null;
    if (need && equipment.size && !equipment.has(need)) errors.push(`${n.id}: needs ${need}, not in equipment`);
    for (const p of n.prerequisites ?? []) {
      if (!ids.has(p)) { errors.push(`${n.id}: prerequisite ${p} not in programme`); continue; }
      const pe = nodes.find((x) => x.id === p);
      const allowed = prerequisites(e.id).includes(pe.exerciseId) || (pe && find(pe.exerciseId)?.family === e.family && find(pe.exerciseId).level < e.level);
      if (!allowed) errors.push(`${n.id}: ${p} is not an allowed progression link`);
    }
  }
  // acyclic and reachable
  const seen = new Set(), stack = new Set();
  const visit = (id) => { if (stack.has(id)) { errors.push('cycle through ' + id); return; } if (seen.has(id)) return; stack.add(id); for (const p of nodes.find((n) => n.id === id)?.prerequisites ?? []) visit(p); stack.delete(id); seen.add(id); };
  for (const n of nodes) visit(n.id);
  const start = nodes.find((n) => n.id === graph.start);
  if (!start) errors.push('start node missing');
  else if ((start.prerequisites ?? []).some((p) => !nodes.find((n) => n.id === p)?.notRequired)) errors.push('start node has unmet prerequisites inside the programme');
  if (!nodes.find((n) => n.id === graph.goalNode)) errors.push('goal node missing');
  else if (start) { // goal reachable by progressing from the start; nodes with no prerequisites are available from the outset
    const reach = new Set([start.id, ...nodes.filter((n) => !(n.prerequisites ?? []).length).map((n) => n.id)]); let grew = true;
    while (grew) { grew = false; for (const n of nodes) if (!reach.has(n.id) && (n.prerequisites ?? []).length && (n.prerequisites ?? []).every((p) => reach.has(p) || nodes.find((x) => x.id === p)?.notRequired)) { reach.add(n.id); grew = true; } }
    if (!reach.has(graph.goalNode)) errors.push('goal node not reachable from the start');
  }
  return { ok: errors.length === 0, errors };
}

// Deterministic programme from the catalogue, used when generation fails validation twice and as the first placement.
export function fallbackProgramme(survey = {}) {
  const goal = survey.goal === 'pushup' ? 'pushup' : 'squat';
  const chain = goal === 'pushup' ? ['wallPushup', 'inclinePushup', 'kneePushup', 'pushup', 'closeGripPushup'] : ['gluteBridge', 'squat', 'reverseLunge', 'splitSquat', 'assistedSquat'];
  const support = goal === 'pushup' ? 'plank' : 'hipFlexorStretch';
  const nodes = chain.map((exerciseId, i) => ({ id: exerciseId, exerciseId, why: i === 0 ? 'The foundation of this progression.' : `Builds on ${find(chain[i - 1]).name.toLowerCase()}.`, prerequisites: i ? [chain[i - 1]] : [], optional: false, assessable: capability(exerciseId) === 'assessable', notRequired: false }));
  nodes.push({ id: support, exerciseId: support, why: goal === 'pushup' ? 'Plank supports push-ups: a steady body line.' : 'Hip mobility supports deeper, steadier squats.', prerequisites: [], optional: true, assessable: false, notRequired: false });
  const placement = placeStart(survey, nodes, goal);
  for (const n of nodes) n.notRequired = placement.notRequired.includes(n.id);
  return { goal, catalogVersion: CATALOG_VERSION, nodes, start: placement.start, goalNode: chain[chain.length - 1], rationale: { source: 'catalogue-fallback', text: placement.reason } };
}

// Starting node from the survey and any history: beginners start at the foundation; someone who already does the assessable
// movement starts there and earlier nodes are marked not required (never verified).
export function placeStart(survey = {}, nodes, goal = survey.goal === 'pushup' ? 'pushup' : 'squat') {
  const assessable = goal === 'pushup' ? 'pushup' : 'squat', chainIds = nodes.filter((n) => !n.optional).map((n) => n.id);
  const ability = survey.ability ?? 'beginner';
  if (ability === 'beginner' || survey.limitations?.length) return { start: chainIds[0], notRequired: [], reason: ability === 'beginner' ? 'Starting at the foundation of the progression.' : 'A stated limitation keeps the start at the foundation; it can be moved after a check with a coach.' };
  const idx = Math.max(0, chainIds.indexOf(assessable));
  return { start: chainIds[idx], notRequired: chainIds.slice(0, idx), reason: `${ability === 'advanced' ? 'Experienced' : 'Some experience'} with this movement: starting at ${find(assessable).name.toLowerCase()}, with earlier steps marked not required for this starting point.` };
}

// ---------- comparison (coach -> retry -> verify) ----------
const median = (a) => { const s = [...a].sort((x, y) => x - y); const m = s.length >> 1; return s.length ? (s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2) : null; };
export const MIN_VALID = 3;
// The counter's rep records name the phases tDown / tUp; stored attempt reps name them down / up. Both are accepted.
const FIELD = { down: 'tDown', up: 'tUp', secs: 'secs' };
export const metricValue = (r, metric) => (Number.isFinite(r?.[metric]) ? r[metric] : Number.isFinite(r?.[FIELD[metric]]) ? r[FIELD[metric]] : null);
// reps: [{ counted, valid, down|tDown, up|tUp, secs, travel, depth }]; contract: see CONTRACTS. Never cherry-picks: medians over all valid reps.
export function compare(baseline, retry, contract) {
  const pick = (reps) => reps.filter((r) => r.counted && r.valid !== false && metricValue(r, contract.metric) != null);
  const b = pick(baseline), r = pick(retry);
  const out = { metric: contract.metric, target: contract.target, tolerance: contract.tolerance, unit: contract.unit, baselineN: b.length, retryN: r.length, contractVersion: contract.version };
  if (b.length < MIN_VALID || r.length < MIN_VALID) return { ...out, classification: 'unable', reason: 'fewer than three valid reps in a phase' };
  const v = (x) => metricValue(x, contract.metric);
  const bErr = median(b.map((x) => Math.abs(v(x) - contract.target))), rErr = median(r.map((x) => Math.abs(v(x) - contract.target)));
  const bRange = median(b.map((x) => x.travel).filter(Number.isFinite)), rRange = median(r.map((x) => x.travel).filter(Number.isFinite));
  const comparableRange = bRange == null || rRange == null ? null : rRange >= 0.85 * bRange;
  Object.assign(out, { baselineError: round(bErr), retryError: round(rErr), baselineMedian: round(median(b.map(v))), retryMedian: round(median(r.map(v))), baselineRange: round(bRange), retryRange: round(rRange), comparableRange, baselineMeets: bErr <= contract.tolerance });
  if (comparableRange === false) return { ...out, classification: 'unable', reason: 'the retry moved through much less range than the baseline; a shorter movement is not a tempo adjustment' };
  const diff = bErr - rErr; // positive: the retry is closer to the target
  const noise = contract.tolerance / 2;  // provisional noise tolerance: half the pass tolerance (see docs/COACH.md)
  const classification = Math.abs(diff) <= noise ? 'similar' : diff > 0 ? 'closer' : 'further';
  return { ...out, classification, noiseTolerance: noise, retryMeets: rErr <= contract.tolerance };
}
const round = (v) => (v == null ? null : Math.round(v * 100) / 100);

// Deterministic cue when Gemini is unavailable or invalid: names the target and the direction of the baseline error.
export function deterministicCue(contract, baseline) {
  const b = baseline.filter((r) => r.counted && metricValue(r, contract.metric) != null);
  const med = median(b.map((r) => metricValue(r, contract.metric)));
  if (med == null) return { action: 'request_better_view', text: 'I could not time those reps. Step back so your hips and knees stay in view, then try three more.' };
  if (Math.abs(med - contract.target) <= contract.tolerance) return { action: 'maintain_target', text: `Your ${contract.label} is already about ${contract.target} s. Keep exactly that rhythm for three more.` };
  const slower = med < contract.target;
  return { action: 'cue_target', text: slower ? `Take longer on the way ${contract.metric === 'down' ? 'down' : 'through each rep'}: count to ${Math.round(contract.target)} as you lower, aiming for about ${contract.target} s.` : `Lower a little quicker and more evenly, aiming for about ${contract.target} s instead of ${med.toFixed(1)} s.` };
}

// ---------- node contracts and rewards ----------
export const XP = { practice: 10, firstCompletion: 50, consistent: 100 };
const dayOf = (iso, tz) => new Date(iso).toLocaleDateString('en-CA', { timeZone: tz });
// attempts: stored coaching attempts for this node (with outcome). An attempt qualifies when its retry (or baseline, if it
// already met the target) has at least three valid reps with median error within tolerance.
export function evaluateNode(contract, attempts, tz = 'UTC') {
  const qualifying = [];
  for (const a of attempts) {
    const o = a.outcome; if (!o || o.classification === 'unable') continue;
    if (o.retryMeets || (o.baselineMeets && o.classification !== 'further')) qualifying.push({ attemptId: a.attemptId, workoutId: a.workoutId, at: a.createdAt, kind: o.retryMeets ? 'retry' : 'baseline' });
  }
  const days = new Set(qualifying.map((q) => dayOf(q.at, tz)));
  return { firstCompletion: qualifying.length >= 1, consistent: days.size >= 2, qualifying, trainingDays: days.size, criteriaVersion: contract.version };
}
// Idempotent reward computation: what the progress row should look like given the evidence, independent of how often it runs.
export function progressFor(contract, attempts, practiceCount, tz = 'UTC') {
  const ev = contract ? evaluateNode(contract, attempts, tz) : { firstCompletion: false, consistent: false, qualifying: [], trainingDays: 0, criteriaVersion: null };
  const verification = ev.consistent ? 'consistent' : ev.firstCompletion ? 'first_completion' : 'none';
  const badges = [...(ev.firstCompletion ? ['first-completion'] : []), ...(ev.consistent ? ['two-day-consistency'] : [])];
  const xp = practiceCount * XP.practice + (ev.firstCompletion ? XP.firstCompletion : 0) + (ev.consistent ? XP.consistent : 0);
  return { verification, badges, xp, evidence: ev.qualifying, criteriaVersion: ev.criteriaVersion, trainingDays: ev.trainingDays };
}

// ---------- reports ----------
// Calculated facts for one workout. Every fact has an id Gemini must cite; nothing here is generated.
export function sessionFacts({ workout, reps = [], attempts = [], predictions = [], tz = 'UTC' }) {
  const counted = reps.filter((r) => r.counted), facts = [], timeline = [];
  const f = (id, text, value = null) => { facts.push({ id, text, value }); return id; };
  const durationS = workout.ended_at && workout.started_at ? Math.round((Date.parse(workout.ended_at) - Date.parse(workout.started_at)) / 1000) : null;
  f('duration', durationS == null ? 'Recorded workout still open' : `Recorded workout duration ${Math.floor(durationS / 60)}:${String(durationS % 60).padStart(2, '0')}`, durationS);
  f('exercise', `Exercise: ${workout.exercise} (${workout.variation}), source ${workout.source}`, workout.exercise);
  f('reps', `${counted.length} counted reps, ${reps.length - counted.length} attempts not counted`, counted.length);
  const downs = counted.map((r) => r.down_secs).filter(Number.isFinite);
  if (downs.length) f('lowering', `Median lowering time ${median(downs).toFixed(2)} s over ${downs.length} reps`, round(median(downs)));
  const good = counted.filter((r) => r.good).length; f('form', `${good} of ${counted.length} counted reps with no form fault`, good);
  for (const a of attempts) {
    const o = a.outcome;
    f(`attempt:${a.attemptId}`, o ? `Coaching attempt (${a.exercise}): cue "${a.cue?.text ?? 'none'}"; baseline median ${o.baselineMedian} s, retry median ${o.retryMedian} s against ${o.target} s; result ${o.classification}` : `Coaching attempt ${a.status}`, o?.classification ?? a.status);
    timeline.push({ at: a.createdAt, kind: 'attempt', text: `Coaching attempt: ${o?.classification ?? a.status}` });
  }
  const obs = predictions.filter((p) => p.state === 'observed');
  if (predictions.length) f('forecasts', `${predictions.length} tempo forecasts recorded in shadow mode, ${obs.length} resolved, ${obs.filter((p) => p.outcome === 1).length} with a departure`, predictions.length);
  for (const r of counted) timeline.push({ at: r.measured_at, kind: 'rep', text: `Rep ${r.rep_n}: lowering ${r.down_secs ?? '–'} s, ${r.good ? 'clean' : (r.faults ?? []).join(', ') || 'fault'}` });
  for (const p of predictions.filter((p) => p.action === 'cue')) timeline.push({ at: p.delivered_at ?? p.emitted_at, kind: 'cue', text: 'Predictive cue delivered' });
  timeline.sort((a, b) => Date.parse(a.at) - Date.parse(b.at));
  f('biometrics', 'No heart-rate or respiration readings were recorded for this session', null);
  return { facts, timeline, version: 'session-v1', tz };
}

// Calendar week boundaries in the user's timezone (weeks start on Monday). Returns ISO dates (YYYY-MM-DD).
export function weekBounds(dateISO, tz = 'UTC') {
  const local = new Date(dateISO).toLocaleDateString('en-CA', { timeZone: tz }); // YYYY-MM-DD in tz
  const d = new Date(local + 'T00:00:00Z'), dow = (d.getUTCDay() + 6) % 7; // Monday = 0
  const start = new Date(d); start.setUTCDate(d.getUTCDate() - dow);
  const toISO = (x) => x.toISOString().slice(0, 10), plus = (x, n) => { const y = new Date(x); y.setUTCDate(x.getUTCDate() + n); return y; };
  return { start: toISO(start), end: toISO(plus(start, 7)), prevStart: toISO(plus(start, -7)) };
}
// Facts for the most recent completed week against the one before. sessions: [{ workout, reps }] with started_at; dates are
// compared in the user's timezone. Never divides by a zero baseline; "no recorded workout" is never "inactive".
export function weeklyFacts({ current, previous = null, attempts = [], nodeProgress = [], goals = [], period, tz = 'UTC' }) {
  const facts = [], f = (id, text, value = null) => { facts.push({ id, text, value }); return id; };
  const summarise = (sessions) => {
    const counted = sessions.flatMap((s) => s.reps.filter((r) => r.counted));
    const days = new Set(sessions.map((s) => dayOf(s.workout.started_at, tz)));
    const secs = sessions.reduce((t, s) => t + (s.workout.ended_at ? (Date.parse(s.workout.ended_at) - Date.parse(s.workout.started_at)) / 1000 : 0), 0);
    const byEx = {}; for (const s of sessions) byEx[s.workout.exercise] = (byEx[s.workout.exercise] ?? 0) + s.reps.filter((r) => r.counted).length;
    const downs = counted.map((r) => r.down_secs).filter(Number.isFinite);
    return { sessions: sessions.length, days: days.size, minutes: Math.round(secs / 60), reps: counted.length, byExercise: byEx, medianLowering: downs.length ? round(median(downs)) : null, loweringN: downs.length };
  };
  const cur = summarise(current), prev = previous ? summarise(previous) : null;
  f('coverage', `Recorded training activity ${period.start} to ${period.end} (${tz}); ${cur.sessions} recorded workouts on ${cur.days} days, ${cur.minutes} min. Days without a recorded workout are not known to be inactive.`, cur);
  f('reps', `${cur.reps} counted reps: ${Object.entries(cur.byExercise).map(([k, v]) => `${v} ${k}`).join(', ') || 'none'}`, cur.reps);
  if (prev) {
    const cmp = (k, label) => prev[k] === 0 && cur[k] === 0 ? `${label} unchanged at 0` : prev[k] === 0 ? `${label} ${cur[k]} this week; none recorded the week before (no percentage from a zero baseline)` : `${label} ${cur[k]} against ${prev[k]} the week before (${cur[k] - prev[k] >= 0 ? '+' : ''}${cur[k] - prev[k]})`;
    f('vs_sessions', cmp('sessions', 'Workouts'), cur.sessions - prev.sessions); f('vs_reps', cmp('reps', 'Counted reps'), cur.reps - prev.reps); f('vs_days', cmp('days', 'Training days'), cur.days - prev.days);
    if (cur.medianLowering != null && prev.medianLowering != null) f('vs_lowering', `Median squat lowering ${cur.medianLowering} s this week against ${prev.medianLowering} s (same tracker version, camera sets only)`, round(cur.medianLowering - prev.medianLowering));
  } else f('baseline_week', 'No earlier week is recorded: this is a baseline report', null);
  const done = attempts.filter((a) => a.outcome && a.outcome.classification !== 'unable');
  f('coaching', `${attempts.length} coaching attempts, ${done.filter((a) => a.outcome.classification === 'closer').length} closer to target after the cue, ${done.filter((a) => a.outcome.classification === 'similar').length} similar, ${done.filter((a) => a.outcome.classification === 'further').length} further, ${attempts.length - done.length} unable to assess`, attempts.length);
  const verified = nodeProgress.filter((n) => n.verification !== 'none');
  f('milestones', verified.length ? `Verified milestones: ${verified.map((n) => `${n.node_id} (${n.verification.replace('_', ' ')})`).join(', ')}` : 'No verified milestones yet; practice is logged separately from verification', verified.length);
  for (const g of goals) f(`goal:${g.id}`, `Accepted goal "${g.text}": ${g.progress ?? 'no progress recorded this week'}`, g.progress ?? null);
  f('biometrics', 'No heart-rate or respiration readings were recorded this week', null);
  return { facts, summary: { current: cur, previous: prev }, version: 'weekly-v1' };
}

// Goals Gemini may propose: bounded kinds, measurable, tied to programme nodes or supported metrics.
export const GOAL_KINDS = new Set(['practice_node', 'repeat_assessment', 'metric_target', 'practice_preparation']);
export function validateGoals(goals, programme, contract = null) {
  const errors = [], ids = new Set(programme?.nodes?.map((n) => n.id) ?? []);
  if (!Array.isArray(goals) || goals.length < 1 || goals.length > 3) errors.push('expected one to three goals');
  for (const g of goals ?? []) {
    if (!GOAL_KINDS.has(g.kind)) errors.push(`goal kind ${g.kind} not allowed`);
    if (g.nodeId && !ids.has(g.nodeId)) errors.push(`goal references node ${g.nodeId} not in the programme`);
    if (!Number.isFinite(g.target) || g.target <= 0 || g.target > 14) errors.push('goal target must be a count between 1 and 14');
    if (typeof g.text !== 'string' || g.text.length > 160) errors.push('goal text missing or too long');
    if (g.kind === 'metric_target' && !contract) errors.push('metric goal without a supported metric');
  }
  return { ok: errors.length === 0, errors };
}

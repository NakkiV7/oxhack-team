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
// Capability inside this app. Squats have the full coach -> retry -> verify loop on the squat page ('assessable'). Push-ups
// are counted by the camera on the push-up page, which has no programme-linked assessment yet ('counting'). Everything else
// is practice the person logs ('practice-only'). Capability is separate from progress.
export const capability = (exerciseId) => { const t = find(exerciseId)?.tracking; return t === 'squat' ? 'assessable' : t === 'pushup' ? 'counting' : 'practice-only'; };
export const CAPABILITY_TEXT = {
  assessable: { badge: 'Camera assessment', detail: 'The squat page times your lowering phase, coaches one change, and checks a retry against a fixed target. Passing it verifies this step.' },
  counting: { badge: 'Camera rep counting', detail: 'The push-up page counts reps and checks body line, but it is not linked to this path yet, so it cannot verify this step. Log your practice here.' },
  'practice-only': { badge: 'Practice log', detail: 'Automated assessment for this movement is not available yet. You log practice yourself; it completes the step but is never shown as AI-verified.' },
};
export const contractFor = (exerciseId) => CONTRACTS[find(exerciseId)?.tracking] ?? null;
export const PRACTICE_COMPLETE = 3; // practice logged on this many different days completes a practice step (never AI verification)
// Versioned completion criteria for any catalogue exercise.
export function criteriaFor(exerciseId) {
  if (capability(exerciseId) === 'assessable') { const c = contractFor(exerciseId); return { version: c.version, kind: 'camera', text: `First completion: ${c.pass}. Consistency: the same result on a second day.` }; }
  return { version: 'practice-v1', kind: 'practice', text: `Log practice on ${PRACTICE_COMPLETE} different days to complete this step. Logged practice is self-reported.` };
}

// ---------- survey ----------
// Concrete self-report options per goal. Each maps to a placement band; nothing here is a strength or fitness score.
export const ABILITY = {
  squat: [
    { key: 'new', label: "I'm new to squats", band: 'beginner' },
    { key: 'control', label: 'I can squat, but want help with control', band: 'intermediate' },
    { key: 'comfortable', label: 'I can do a comfortable set', band: 'advanced' },
    { key: 'unsure', label: "I'm not sure", band: 'unsure' },
  ],
  pushup: [
    { key: 'notTried', label: "I haven't tried recently", band: 'beginner' },
    { key: 'first', label: "I'm working towards my first standard push-up", band: 'beginner' },
    { key: 'few', label: 'I can do a few', band: 'intermediate' },
    { key: 'comfortable', label: 'I can do a comfortable set', band: 'advanced' },
    { key: 'unsure', label: "I'm not sure", band: 'unsure' },
  ],
};
export const EQUIPMENT_OPTIONS = [
  { key: 'wall', label: 'A clear wall', hint: 'for wall push-ups' },
  { key: 'raised surface', label: 'A sturdy raised surface', hint: 'counter, table edge or sofa arm' },
  { key: 'stable support', label: 'Something stable to hold', hint: 'chair back or rail' },
];
// Movements a person may choose to leave out of their path. The goal's own camera movement is never offered.
export const AVOIDABLE = { squat: ['gluteBridge', 'reverseLunge', 'splitSquat', 'assistedSquat', 'hipFlexorStretch', 'singleLegBalance'], pushup: ['wallPushup', 'inclinePushup', 'kneePushup', 'closeGripPushup', 'plank', 'sidePlank'] };
export const goalOf = (survey = {}) => (survey.goal === 'pushup' ? 'pushup' : 'squat');
export const bandOf = (survey = {}) => ABILITY[goalOf(survey)].find((a) => a.key === survey.abilityKey)?.band ?? survey.ability ?? 'beginner';
const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));

// Practice prescription per node, from the catalogue goal, the time available and the placement band. Gemini may propose
// different numbers inside validTarget's bounds; it may not exceed them.
export function defaultTarget(exerciseId, survey = {}) {
  const e = find(exerciseId), band = bandOf(survey), minutes = survey.minutes ?? 20;
  const scale = band === 'advanced' ? 1 : band === 'intermediate' ? 0.8 : 0.6;
  return { sets: minutes <= 10 ? 2 : 3, target: Math.max(e.unit === 'seconds' ? 10 : 3, Math.round(e.goal * scale)), unit: e.unit, perWeek: clamp(Math.round(survey.daysPerWeek ?? 3), 1, 6) };
}
export function validTarget(t, exerciseId, survey = {}) {
  const e = find(exerciseId); if (!e || !t) return false;
  const maxPerWeek = clamp(Math.round(survey.daysPerWeek ?? 6), 1, 6);
  return Number.isInteger(t.sets) && t.sets >= 1 && t.sets <= 4 && Number.isInteger(t.target) && t.target >= 1 && t.target <= Math.ceil(e.goal * 1.5)
    && (t.unit == null || t.unit === e.unit) && Number.isInteger(t.perWeek) && t.perWeek >= 1 && t.perWeek <= maxPerWeek;
}

// ---------- programme ----------
export const PROGRAMME_LIMITS = { minNodes: 4, maxNodes: 6, maxOptional: 1 };
const EQUIPMENT_FOR = { wall: 'wall', 'raised surface': 'raised surface', 'stable support': 'stable support', 'optional support': null };

// A generated graph: { goal: 'squat'|'pushup', nodes: [{ id, exerciseId, why, prerequisites: [nodeIds], optional, supports?,
// notRequired, practiceTarget? }], start, goalNode, route? }. Optional nodes are side branches: they never gate another node,
// and `supports` names the node they help (a catalogue support link). Returns { ok, errors }. Every rule here is one Gemini
// could break: unknown ids, invented links, cycles, an unreachable goal, equipment or movements the person ruled out.
const equipmentAnswered = (survey) => Array.isArray(survey.equipment) && (survey.equipmentAnswered || survey.equipment.length > 0);
export function validateProgramme(graph, survey = {}) {
  const errors = [];
  if (!graph || !Array.isArray(graph.nodes)) return { ok: false, errors: ['graph.nodes missing'] };
  const nodes = graph.nodes, ids = new Set(nodes.map((n) => n.id));
  if (ids.size !== nodes.length) errors.push('duplicate node ids');
  if (nodes.length < PROGRAMME_LIMITS.minNodes || nodes.length > PROGRAMME_LIMITS.maxNodes) errors.push(`expected ${PROGRAMME_LIMITS.minNodes} to ${PROGRAMME_LIMITS.maxNodes} nodes, got ${nodes.length}`);
  if (nodes.filter((n) => n.optional).length > PROGRAMME_LIMITS.maxOptional) errors.push('more than one optional branch');
  const equipment = new Set(survey.equipment ?? []), avoid = new Set(survey.avoid ?? []);
  for (const n of nodes) {
    const e = find(n.exerciseId);
    if (!e) { errors.push(`unknown exercise ${n.exerciseId}`); continue; }
    if (n.id !== n.exerciseId) errors.push(`${n.id}: node id must equal its exercise id`);
    if (n.assessable != null && n.assessable !== (capability(e.id) === 'assessable')) errors.push(`${n.id}: assessable flag does not match capability`);
    const need = e.support ? EQUIPMENT_FOR[e.support] : null;
    if (need && equipmentAnswered(survey) && !equipment.has(need)) errors.push(`${n.id}: needs ${need}, not in equipment`);
    if (avoid.has(e.id)) errors.push(`${n.id}: the person asked to leave this movement out`);
    if (n.practiceTarget != null && !validTarget(n.practiceTarget, e.id, survey)) errors.push(`${n.id}: practice target outside the allowed range`);
    if (n.optional && nodes.some((x) => (x.prerequisites ?? []).includes(n.id))) errors.push(`${n.id}: an optional node cannot gate another node`);
    if (n.supports != null) {
      const target = nodes.find((x) => x.id === n.supports);
      if (!target) errors.push(`${n.id}: supports ${n.supports}, which is not in the programme`);
      else if (!prerequisites(target.exerciseId).includes(e.id)) errors.push(`${n.id}: is not a catalogue support for ${n.supports}`);
    }
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
  if (graph.route != null && !validRoute(graph)) errors.push('recommended route is not a path from the start to the goal');
  return { ok: errors.length === 0, errors };
}

// The recommended route: start -> goal following prerequisite links (each step's node lists the previous one).
export function validRoute(graph) {
  const r = graph.route, byId = Object.fromEntries(graph.nodes.map((n) => [n.id, n]));
  if (!Array.isArray(r) || r[0] !== graph.start || r[r.length - 1] !== graph.goalNode || new Set(r).size !== r.length) return false;
  return r.every((id, i) => byId[id] && (i === 0 || (byId[id].prerequisites ?? []).includes(r[i - 1])));
}
export function defaultRoute(graph) {
  const byId = Object.fromEntries(graph.nodes.map((n) => [n.id, n])), route = [graph.start];
  for (let guard = 0; guard < 12 && route[route.length - 1] !== graph.goalNode; guard++) {
    const cur = route[route.length - 1];
    const next = graph.nodes.filter((n) => !n.optional && (n.prerequisites ?? []).includes(cur)).sort((a, b) => (find(a.exerciseId)?.level ?? 0) - (find(b.exerciseId)?.level ?? 0))[0];
    if (!next) break;
    route.push(next.id);
  }
  return route[route.length - 1] === graph.goalNode ? route : [graph.start];
}

// Deterministic programme from the catalogue: used when Gemini is off or its plan fails validation twice. It honours the
// same answers (equipment, movements to leave out, time, placement) so the fallback is still a fit, just not a written one.
const CHAINS = { pushup: ['wallPushup', 'inclinePushup', 'kneePushup', 'pushup', 'closeGripPushup'], squat: ['gluteBridge', 'squat', 'reverseLunge', 'splitSquat', 'assistedSquat'] };
export function availableExercise(id, survey = {}) {
  const e = find(id); if (!e) return false;
  if ((survey.avoid ?? []).includes(id) && id !== goalOf(survey)) return false;
  const need = e.support ? EQUIPMENT_FOR[e.support] : null;
  return !(need && equipmentAnswered(survey) && !(survey.equipment ?? []).includes(need));
}
export function fallbackProgramme(survey = {}, check = null) {
  const goal = goalOf(survey), chain = CHAINS[goal].filter((id) => availableExercise(id, survey));
  const nodes = chain.map((exerciseId, i) => ({ id: exerciseId, exerciseId, why: i === 0 ? 'The first step of this progression with the space and equipment you have.' : `Builds on ${find(chain[i - 1]).name.toLowerCase()}.`, prerequisites: i ? [chain[i - 1]] : [], optional: false, assessable: capability(exerciseId) === 'assessable', notRequired: false }));
  // Supports from the catalogue: the first available becomes the optional branch; more are added as prerequisites only when
  // the chain is too short for a useful path.
  const supports = chain.flatMap((id) => (SUPPORT[id] ?? []).map((s) => ({ s, of: id }))).filter(({ s }) => availableExercise(s, survey) && !chain.includes(s));
  const opt = supports.shift();
  for (const { s, of } of supports) { if (nodes.length + (opt ? 1 : 0) >= PROGRAMME_LIMITS.minNodes) break; nodes.push({ id: s, exerciseId: s, why: `Supports ${find(of).name.toLowerCase()}.`, prerequisites: [], optional: false, assessable: false, notRequired: false }); nodes.find((n) => n.id === of).prerequisites.push(s); }
  if (opt) nodes.push({ id: opt.s, exerciseId: opt.s, why: `Optional: ${find(opt.s).name.toLowerCase()} supports ${find(opt.of).name.toLowerCase()}.`, prerequisites: [], optional: true, supports: opt.of, assessable: false, notRequired: false });
  for (const n of nodes) n.practiceTarget = defaultTarget(n.exerciseId, survey);
  const placement = placeStart(survey, nodes, goal, check);
  for (const n of nodes) n.notRequired = placement.notRequired.includes(n.id);
  const graph = { goal, catalogVersion: CATALOG_VERSION, nodes, start: placement.start, goalNode: chain[chain.length - 1], placementSource: placement.source };
  graph.route = defaultRoute(graph);
  return { ...graph, rationale: { source: 'catalogue-fallback', text: placement.reason, startReason: placement.reason, emphasis: defaultEmphasis(survey), placementSource: placement.source } };
}
export function defaultEmphasis(survey = {}) {
  return { learn: 'Learn the movement pattern before adding volume.', consistency: 'Turn up on your planned days; steady practice beats big sessions.', improve: 'Refine control on the movement you already have.' }[survey.focus] ?? 'Build the movement step by step at a pace you can repeat.';
}

// Where the path starts. Self-report places beginners and "not sure" at the foundation and people with experience at the
// camera movement; a recent camera check with three valid reps of the goal movement also allows starting there. Earlier
// steps on the main chain become "not required for this starting point" (never verified). allowedStarts bounds Gemini.
export function placeStart(survey = {}, nodes, goal = goalOf(survey), check = null) {
  const family = find(goal)?.family;
  const chainIds = nodes.filter((n) => !n.optional && find(n.exerciseId)?.family === family).sort((a, b) => find(a.exerciseId).level - find(b.exerciseId).level).map((n) => n.id);
  const band = bandOf(survey), at = (idx, reason, source) => ({ start: chainIds[idx], notRequired: chainIds.slice(0, idx), reason, source, allowedStarts: chainIds.slice(0, idx + 1) });
  const idx = Math.max(0, chainIds.indexOf(goal));
  if (survey.limitations?.length) return at(0, 'A stated limitation keeps the start at the foundation.', 'self-reported');
  if (check && check.exercise === goal && check.validReps >= 3) return at(idx, `Your camera check recorded ${check.validReps} valid ${find(goal).name.toLowerCase()}, so the path starts there; earlier steps are not required for this starting point.`, 'camera-supported');
  if (band === 'beginner' || band === 'unsure') return at(0, band === 'unsure' ? "You weren't sure, so the path starts at the foundation; a camera check can move you on." : 'Starting at the foundation of the progression.', 'self-reported');
  return at(idx, `${band === 'advanced' ? 'You can do a comfortable set' : 'You have some experience'}, so the path starts at ${find(goal).name.toLowerCase()}; earlier steps are not required for this starting point.`, 'self-reported');
}

// What a new version changes, for the review before saving. progress: rows of the current version.
export function diffProgrammes(oldGraph, newGraph, progress = []) {
  const o = new Set((oldGraph?.nodes ?? []).map((n) => n.id)), n = new Set(newGraph.nodes.map((x) => x.id));
  const done = progress.filter((p) => p.verification !== 'none' || (p.practice_count ?? 0) > 0);
  return {
    added: [...n].filter((id) => !o.has(id)), removed: [...o].filter((id) => !n.has(id)), kept: [...n].filter((id) => o.has(id)),
    start: { from: oldGraph?.start ?? null, to: newGraph.start }, goal: { from: oldGraph?.goalNode ?? null, to: newGraph.goalNode },
    carried: done.filter((p) => n.has(p.node_id)).map((p) => ({ nodeId: p.node_id, verification: p.verification, practice: p.practice_count, xp: p.xp })),
    archived: done.filter((p) => !n.has(p.node_id)).map((p) => ({ nodeId: p.node_id, verification: p.verification, practice: p.practice_count, xp: p.xp })),
  };
}

// ---------- game progression and measured attributes ----------
// Programme level is a game score from XP, never a fitness rating. Level L starts at 50·L·(L-1) XP.
export function levelFor(xp = 0) { let L = 1; while (xp >= 50 * L * (L + 1)) L++; return { level: L, xp, floor: 50 * L * (L - 1), next: 50 * L * (L + 1) }; }
const inWindow = (iso, now, days) => Date.parse(iso) >= now.getTime() - days * 86400e3 && Date.parse(iso) <= now.getTime();
// Three transparent attributes from saved records only. attempts: coaching_attempt rows; practiceDays: [{ at }] from the
// practice log. A value is null ("not assessed yet") until there is enough evidence; there is no flattering default.
export function attributes({ attempts = [], practiceDays = [], survey = {}, now = new Date(), tz = 'UTC' }) {
  const timed = [];
  for (const a of attempts) {
    if (!inWindow(a.created_at ?? a.createdAt, now, 30)) continue;
    const c = contractFor(a.exercise); if (!c || c.metric !== 'down') continue;
    for (const r of [...(a.baseline_reps ?? a.baselineReps ?? []), ...(a.retry_reps ?? a.retryReps ?? [])]) { const v = metricValue(r, 'down'); if (r.counted && r.valid !== false && v != null) timed.push({ v, target: c.target, tol: c.tolerance }); }
  }
  const out = [];
  const inRange = timed.filter((x) => Math.abs(x.v - x.target) <= x.tol).length;
  out.push({ key: 'tempo', label: 'Tempo', value: timed.length >= 3 ? Math.round((100 * inRange) / timed.length) : null, evidence: timed.length,
    detail: timed.length >= 3 ? `${inRange} of ${timed.length} timed squats were within ${timed[0].tol} s of the ${timed[0].target} s lowering target` : `Needs 3 timed squats from a camera assessment (${timed.length} so far)`,
    how: 'Share of squats timed in camera assessments over the last 30 days whose lowering phase was within the target tolerance. Baseline and retry reps both count; uncounted reps do not.', scope: 'last 30 days' });
  const med = median(timed.map((x) => x.v)), steady = med ? timed.filter((x) => Math.abs(x.v - med) <= 0.1 * med).length : 0;
  out.push({ key: 'consistency', label: 'Consistency', value: timed.length >= 5 ? Math.round((100 * steady) / timed.length) : null, evidence: timed.length,
    detail: timed.length >= 5 ? `${steady} of ${timed.length} timed squats were within 10% of your own median lowering time (${round(med)} s)` : `Needs 5 timed squats (${timed.length} so far)`,
    how: 'Share of timed squats over the last 30 days within ±10% of your own median lowering time. It measures repeatability, not speed.', scope: 'last 30 days' });
  const week = weekBounds(now.toISOString(), tz), planned = Number.isInteger(survey.daysPerWeek) ? survey.daysPerWeek : null;
  const days = new Set([...practiceDays.map((p) => p.at), ...attempts.filter((a) => (a.status === 'result')).map((a) => a.created_at ?? a.createdAt)].filter(Boolean).map((at) => dayOf(at, tz)).filter((d) => d >= week.start && d < week.end));
  out.push({ key: 'practice', label: 'Practice', value: planned ? Math.min(100, Math.round((100 * days.size) / planned)) : null, evidence: days.size,
    detail: planned ? `${days.size} of ${planned} planned sessions this week` : 'Set sessions per week in your path to track this',
    how: 'Days this calendar week with logged practice or a completed camera assessment, against the sessions per week you chose. Logged practice is self-reported.', scope: 'this week' });
  return out;
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
export const dayOf = (iso, tz) => new Date(iso).toLocaleDateString('en-CA', { timeZone: tz });
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

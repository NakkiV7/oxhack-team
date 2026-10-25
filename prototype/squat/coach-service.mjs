// Application services for the coaching journey: the pieces the HTTP routes and the weekly job share. Facts are computed
// here from stored records; Gemini narrates afterwards and its text is stored apart from the facts.
import { createHash } from 'node:crypto';
import * as coach from './coach.mjs';
import * as store from './coach-store.mjs';

export const DEFAULT_TZ = 'Europe/London';

export async function ensureProfile(pool, user) {
  return (await store.getProfile(pool, user)) ?? store.upsertProfile(pool, user, { timezone: DEFAULT_TZ, survey: {}, goals: [], preferences: {} });
}
export async function programmeView(pool, user) {
  const p = await store.getActiveProgramme(pool, user);
  if (!p) return null;
  const progress = await store.listNodeProgress(pool, p.programme_id);
  return { ...p, progress };
}

// Session report: facts and timeline from the stored workout, reps, attempts and forecasts; saved once; narrative on request.
export async function sessionReport({ pool, ai, user, workoutId, narrate = false }) {
  const data = await store.workoutWithReps(pool, workoutId);
  if (!data) return null;
  const profile = await ensureProfile(pool, user);
  const attempts = data.attempts.map((a) => ({ attemptId: a.attempt_id, exercise: a.exercise, status: a.status, cue: a.cue, outcome: a.outcome, createdAt: a.created_at }));
  const { facts, timeline, version } = coach.sessionFacts({ workout: data.workout, reps: data.reps, attempts, predictions: data.predictions, tz: profile.timezone });
  let saved = await store.getSessionReport(pool, workoutId);
  let narrative = saved?.narrative ?? null;
  if (narrate && !narrative && ai) narrative = await ai.narrate('session', facts);
  saved = await store.saveSessionReport(pool, user, { workoutId, version, facts, timeline, narrative });
  const reps = data.reps.map((r) => ({ n: r.rep_n, counted: r.counted, good: r.good, down: r.down_secs, up: r.up_secs, secs: r.secs, faults: r.faults ?? [], at: r.measured_at }));
  return { workout: data.workout, facts, timeline, narrative: saved.narrative, attempts: data.attempts, predictions: data.predictions, reps, version };
}

// Weekly review for the most recently completed calendar week (or a given Monday). Idempotent by user, period and input
// fingerprint; concurrent calls share one row; late data makes an older ready report stale and yields a new version.
// periodStart: a Monday (YYYY-MM-DD) or 'current' for the week in progress; default is the most recently completed week.
export async function generateWeekly({ pool, ai, user, periodStart = null, now = new Date() }) {
  const profile = await ensureProfile(pool, user), tz = profile.timezone || DEFAULT_TZ;
  const thisWeek = coach.weekBounds(now.toISOString(), tz);
  const bounds = periodStart === 'current' ? thisWeek : periodStart ? coach.weekBounds(periodStart + 'T12:00:00Z', 'UTC') : { start: thisWeek.prevStart, end: thisWeek.start, prevStart: coach.weekBounds(thisWeek.prevStart + 'T12:00:00Z', 'UTC').prevStart };
  const period = { start: bounds.start, end: bounds.end, prevStart: bounds.prevStart };
  const utc = (d) => new Date(d + 'T00:00:00Z').toISOString(); // calendar boundaries in the user's zone are approximated at UTC midnight for the prototype
  const current = await store.workoutsBetween(pool, { startISO: utc(period.start), endISO: utc(period.end), exercise: null, source: 'camera' });
  const previous = await store.workoutsBetween(pool, { startISO: utc(period.prevStart), endISO: utc(period.start), exercise: null, source: 'camera' });
  const attempts = (await store.listAttempts(pool, user, { since: utc(period.start), limit: 200 })).filter((a) => a.created_at < new Date(utc(period.end)));
  const programme = await programmeView(pool, user);
  const nodeProgress = programme?.progress ?? [];
  const goals = (profile.goals ?? []).map((g) => ({ ...g, progress: null }));
  const { facts, summary, version } = coach.weeklyFacts({ current, previous: previous.length || current.length ? previous : null, attempts, nodeProgress, goals, period, tz });
  if (periodStart === 'current') facts.unshift({ id: 'in_progress', text: `Week in progress: recorded up to ${now.toISOString().slice(0, 16).replace('T', ' ')} UTC, not a completed week`, value: null });
  const synthetic = [...current, ...previous].filter((s) => s.workout.client === 'demo-seed').length;
  if (synthetic) facts.unshift({ id: 'synthetic', text: `${synthetic} of these sets are synthetic sample history for the demo account, not real recordings`, value: synthetic });
  const fingerprint = createHash('sha256').update(JSON.stringify({ version, period, w: current.map((s) => [s.workout.workout_id, s.reps.length]), p: previous.map((s) => [s.workout.workout_id, s.reps.length]), a: attempts.map((a) => [a.attempt_id, a.status]), n: nodeProgress.map((n) => [n.node_id, n.verification, n.practice_count]), g: goals.map((g) => g.id) })).digest('hex');
  const existing = await store.findWeeklyReport(pool, user, { periodStart: period.start, fingerprint });
  if (existing && existing.status === 'ready') return { report: existing, generated: false };
  const { row, claimed } = await store.claimWeeklyReport(pool, user, { reportId: crypto.randomUUID(), periodStart: period.start, periodEnd: period.end, comparisonStart: period.prevStart, timezone: tz, cutoffAt: now.toISOString(), fingerprint });
  if (!claimed) return { report: row, generated: false };
  try {
    const research = await store.listResearch(pool, user);
    const refs = [];
    for (const r of research.slice(0, 6)) refs.push(await store.getResearch(pool, r.source_id));
    const contract = coach.contractFor(programme?.goal === 'pushup' ? 'pushup' : 'squat');
    const narrative = ai ? await ai.weeklyReview(facts, programme, contract, refs) : null;
    const goalsOut = narrative?.goals ?? defaultGoals(programme, summary);
    const report = await store.finishWeeklyReport(pool, row.report_id, { status: 'ready', facts: { items: facts, summary }, narrative: narrative ? { headline: narrative.headline, insights: narrative.insights, provenance: narrative.provenance, generationId: narrative.generationId, goalErrors: narrative.goalErrors ?? null } : null, proposedGoals: goalsOut, researchRefs: refs.map((r) => ({ sourceId: r.source_id, title: r.title, access: r.access })), modelVersion: narrative?.generationId?.split(':')[0] ?? null });
    return { report, generated: true };
  } catch (e) {
    await store.finishWeeklyReport(pool, row.report_id, { status: 'failed', facts: { items: facts, summary }, narrative: { error: e.message }, proposedGoals: null, researchRefs: [] });
    throw e;
  }
}
// Deterministic goals when Gemini is off or invalid: practise the current node, repeat the assessment, both measurable.
export function defaultGoals(programme, summary) {
  const cur = programme?.graph?.nodes?.find((n) => n.id === programme.graph.start) ?? null;
  const goals = [];
  if (cur) goals.push({ id: 'g1', kind: 'practice_node', text: `Practise ${coach.find(cur.exerciseId)?.name.toLowerCase() ?? cur.id} in two recorded sessions`, nodeId: cur.id, target: 2, factIDs: ['coverage'] });
  if (cur && coach.capability(cur.exerciseId) === 'assessable') goals.push({ id: 'g2', kind: 'repeat_assessment', text: `Repeat the ${coach.find(cur.exerciseId).name.toLowerCase()} tempo assessment once to check consistency`, nodeId: cur.id, target: 1, factIDs: ['coaching'] });
  if (!goals.length) goals.push({ id: 'g1', kind: 'practice_preparation', text: 'Record one practice session', target: 1, factIDs: ['coverage'] });
  return goals;
}

export const sha256 = (buf) => createHash('sha256').update(buf).digest('hex');

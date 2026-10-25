// Persistence for the coaching journey on Tiger Data (schema in ../shared/db/004_coaching.sql). Every write is keyed by a
// stable id and safe to repeat; an assessment and the progress it earns are saved in one transaction.
import { PRACTICE_COMPLETE, capability, dayOf } from './coach.mjs';
export { PRACTICE_COMPLETE };
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const uid = (u) => { if (typeof u !== 'string' || !/^[a-z0-9_-]{1,64}$/i.test(u)) throw new Error('bad user id'); return u; };
const j = (v) => (v == null ? null : JSON.stringify(v)); // SQL NULL for absent values, so COALESCE can fill them later

export async function getProfile(pool, userId) { return (await pool.query('SELECT * FROM spottr_cv.profile WHERE user_id = $1', [uid(userId)])).rows[0] ?? null; }
export async function upsertProfile(pool, userId, { timezone, survey, goals, preferences }) {
  const r = await pool.query(`INSERT INTO spottr_cv.profile (user_id, timezone, survey, goals, preferences) VALUES ($1, COALESCE($2, 'Europe/London'), COALESCE($3::jsonb, '{}'), COALESCE($4::jsonb, '[]'), COALESCE($5::jsonb, '{}'))
    ON CONFLICT (user_id) DO UPDATE SET timezone = COALESCE($2, spottr_cv.profile.timezone), survey = COALESCE($3::jsonb, spottr_cv.profile.survey), goals = COALESCE($4::jsonb, spottr_cv.profile.goals), preferences = COALESCE($5::jsonb, spottr_cv.profile.preferences), updated_at = clock_timestamp() RETURNING *`,
    [uid(userId), timezone ?? null, survey == null ? null : j(survey), goals == null ? null : j(goals), preferences == null ? null : j(preferences)]);
  return r.rows[0];
}

export async function getActiveProgramme(pool, userId) { return (await pool.query("SELECT * FROM spottr_cv.programme WHERE user_id = $1 AND status = 'active' ORDER BY version DESC LIMIT 1", [uid(userId)])).rows[0] ?? null; }
// A new programme supersedes the active one; earlier versions and their rows are kept untouched. Progress for every step
// that appears in both versions (practice, verification, evidence, XP, badges) is copied into the new version, so a new
// path never loses earned progress; steps that leave the path keep their record in the earlier version.
export async function saveProgramme(pool, userId, { programmeId, goal, catalogVersion, graph, rationale, provenance }) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const v = (await client.query('SELECT COALESCE(MAX(version), 0) + 1 AS v FROM spottr_cv.programme WHERE user_id = $1', [uid(userId)])).rows[0].v;
    const prev = (await client.query("SELECT programme_id FROM spottr_cv.programme WHERE user_id = $1 AND status = 'active' ORDER BY version DESC LIMIT 1", [userId])).rows[0];
    const carried = prev ? Object.fromEntries((await client.query('SELECT * FROM spottr_cv.node_progress WHERE programme_id = $1', [prev.programme_id])).rows.map((r) => [r.node_id, r])) : {};
    await client.query("UPDATE spottr_cv.programme SET status = 'superseded' WHERE user_id = $1 AND status = 'active'", [userId]);
    const row = (await client.query("INSERT INTO spottr_cv.programme (programme_id, user_id, version, goal, catalog_version, graph, rationale, provenance, status) VALUES ($1, $2, $3, $4, $5, $6::jsonb, $7::jsonb, $8, 'active') RETURNING *",
      [programmeId, userId, v, goal, catalogVersion, j(graph), j(rationale), provenance])).rows[0];
    for (const n of graph.nodes) {
      const availability = n.notRequired ? 'not_required' : n.id === graph.start ? 'current' : (n.prerequisites ?? []).length === 0 ? 'available' : 'locked';
      const c = carried[n.id];
      await client.query(`INSERT INTO spottr_cv.node_progress (programme_id, node_id, user_id, availability, practice_count, practice_workouts, practice_log, verification, evidence, criteria_version, xp, badges, completed_at, verified_at)
        VALUES ($1, $2, $3, $4, $5, $6::jsonb, $7::jsonb, $8, $9::jsonb, $10, $11, $12::jsonb, $13, $14) ON CONFLICT DO NOTHING`,
        [programmeId, n.id, userId, availability, c?.practice_count ?? 0, j(c?.practice_workouts ?? []), j(c?.practice_log ?? []), c?.verification ?? 'none', j(c?.evidence ?? []), c?.criteria_version ?? null, c?.xp ?? 0, j(c?.badges ?? []), c?.completed_at ?? null, c?.verified_at ?? null]);
    }
    await unlockDependents(client, programmeId);
    await client.query('COMMIT'); return row;
  } catch (e) { await client.query('ROLLBACK').catch(() => {}); throw e; } finally { client.release(); }
}
// Every node row the person has across all versions: the basis for XP, achievements and practice history, so refining the
// path never lowers the level or hides an earned milestone. Per step, the best row counts once.
const RANK = { none: 0, first_completion: 1, consistent: 2 };
export async function allProgress(pool, userId) {
  const rows = (await pool.query('SELECT np.*, p.version FROM spottr_cv.node_progress np JOIN spottr_cv.programme p USING (programme_id) WHERE np.user_id = $1', [uid(userId)])).rows;
  const best = {};
  for (const r of rows) { const b = best[r.node_id]; if (!b || RANK[r.verification] > RANK[b.verification] || (RANK[r.verification] === RANK[b.verification] && r.xp > b.xp)) best[r.node_id] = r; }
  const practice = new Map(); for (const r of rows) for (const e of r.practice_log ?? []) practice.set(e.key, e);
  const xp = Object.values(best).reduce((t, r) => t + (r.xp ?? 0), 0);
  const achievements = Object.values(best).filter((r) => r.verification !== 'none').map((r) => ({ nodeId: r.node_id, verification: r.verification, verifiedAt: r.verified_at ?? r.completed_at, version: r.version, badges: r.badges, evidence: r.evidence }));
  const completedPractice = Object.values(best).filter((r) => capability(r.node_id) !== 'assessable' && r.practice_count >= PRACTICE_COMPLETE).map((r) => r.node_id);
  return { xp, achievements, completedPractice, practiceDays: [...practice.values()] };
}
// The latest placement check: a camera attempt run from the survey (node 'placement-check') in the last 7 days.
export async function latestCheck(pool, userId) {
  const a = (await pool.query("SELECT * FROM spottr_cv.coaching_attempt WHERE user_id = $1 AND node_id = 'placement-check' AND created_at > now() - interval '7 days' ORDER BY created_at DESC LIMIT 1", [uid(userId)])).rows[0];
  if (!a) return null;
  const valid = (a.baseline_reps ?? []).filter((r) => r.counted && r.valid !== false && Number.isFinite(r.down));
  const downs = valid.map((r) => r.down).sort((x, y) => x - y);
  return { attemptId: a.attempt_id, exercise: a.exercise, at: a.created_at, validReps: valid.length, medianLowering: downs.length ? downs[downs.length >> 1] : null, status: a.status };
}
export async function listNodeProgress(pool, programmeId) { return (await pool.query('SELECT * FROM spottr_cv.node_progress WHERE programme_id = $1', [programmeId])).rows; }
// A node counts as done for unlocking when it is verified, not required, or practice-only with enough logged practice.
export async function unlockDependents(client, programmeId) {
  const prog = (await client.query('SELECT graph FROM spottr_cv.programme WHERE programme_id = $1', [programmeId])).rows[0]?.graph;
  const rows = (await client.query('SELECT node_id, verification, availability, practice_count FROM spottr_cv.node_progress WHERE programme_id = $1', [programmeId])).rows;
  const byId = Object.fromEntries(rows.map((r) => [r.node_id, r])), nodes = prog?.nodes ?? [];
  const done = new Set(nodes.filter((n) => { const r = byId[n.id]; return r && (r.verification !== 'none' || r.availability === 'not_required' || (!n.assessable && r.practice_count >= PRACTICE_COMPLETE)); }).map((n) => n.id));
  for (const n of nodes) if ((n.prerequisites ?? []).length && n.prerequisites.every((p) => done.has(p))) await client.query("UPDATE spottr_cv.node_progress SET availability = 'available', updated_at = clock_timestamp() WHERE programme_id = $1 AND node_id = $2 AND availability = 'locked'", [programmeId, n.id]);
  return done;
}
// Practice is counted once per step per calendar day (in the person's timezone): logging again the same day, refreshing,
// or retrying the request changes nothing and awards nothing. Practice on enough days completes a practice-only step and
// unlocks what depends on it, without ever marking it verified. Returns { node, logged } (logged false = already counted).
export async function logPractice(pool, { programmeId, nodeId, userId, tz = 'UTC', now = new Date() }) {
  const key = `${nodeId}:${dayOf(now.toISOString(), tz)}`;
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const row = (await client.query(`UPDATE spottr_cv.node_progress SET practice_count = practice_count + 1, practice_workouts = practice_workouts || to_jsonb($4::text),
        practice_log = practice_log || jsonb_build_array(jsonb_build_object('key', $4::text, 'at', $5::text)), xp = xp + 10,
        completed_at = CASE WHEN practice_count + 1 >= ${PRACTICE_COMPLETE} THEN COALESCE(completed_at, clock_timestamp()) ELSE completed_at END, updated_at = clock_timestamp()
      WHERE programme_id = $1 AND node_id = $2 AND user_id = $3 AND NOT (practice_workouts ? $4::text) RETURNING *`, [programmeId, nodeId, uid(userId), key, now.toISOString()])).rows[0] ?? null;
    if (row) await unlockDependents(client, programmeId);
    await client.query('COMMIT');
    return { node: row ?? (await pool.query('SELECT * FROM spottr_cv.node_progress WHERE programme_id = $1 AND node_id = $2', [programmeId, nodeId])).rows[0] ?? null, logged: !!row, key };
  } catch (e) { await client.query('ROLLBACK').catch(() => {}); throw e; } finally { client.release(); }
}

export async function getAttempt(pool, attemptId) { return (await pool.query('SELECT * FROM spottr_cv.coaching_attempt WHERE attempt_id = $1', [attemptId])).rows[0] ?? null; }
export async function listAttempts(pool, userId, { exercise = null, nodeId = null, programmeId = null, since = null, limit = 50 } = {}) {
  const r = await pool.query(`SELECT * FROM spottr_cv.coaching_attempt WHERE user_id = $1 AND ($2::text IS NULL OR exercise = $2) AND ($3::text IS NULL OR node_id = $3) AND ($4::uuid IS NULL OR programme_id = $4) AND ($5::timestamptz IS NULL OR created_at >= $5)
    ORDER BY created_at DESC LIMIT $6`, [uid(userId), exercise, nodeId, programmeId, since, limit]);
  return r.rows;
}
// Upsert of the attempt snapshot. A finished attempt (result or cancelled) is never moved back to an earlier status, so a
// late or duplicate callback cannot advance or rewind it.
const FINAL = new Set(['result', 'cancelled']);
export async function saveAttempt(pool, userId, a, client = pool) {
  if (!UUID.test(a.attemptId ?? '') || !UUID.test(a.workoutId ?? '')) throw new Error('attempt and workout ids required');
  const r = await client.query(`INSERT INTO spottr_cv.coaching_attempt (attempt_id, user_id, workout_id, programme_id, node_id, exercise, variation, contract_version, status, target, baseline_reps, retry_reps, cue, outcome, explanation, interventions)
    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10::jsonb, $11::jsonb, $12::jsonb, $13::jsonb, $14::jsonb, $15::jsonb, $16::jsonb)
    ON CONFLICT (attempt_id) DO UPDATE SET status = CASE WHEN spottr_cv.coaching_attempt.status IN ('result', 'cancelled') THEN spottr_cv.coaching_attempt.status ELSE EXCLUDED.status END,
      target = COALESCE(spottr_cv.coaching_attempt.target, EXCLUDED.target), baseline_reps = EXCLUDED.baseline_reps, retry_reps = EXCLUDED.retry_reps,
      cue = COALESCE(spottr_cv.coaching_attempt.cue, EXCLUDED.cue), outcome = COALESCE(spottr_cv.coaching_attempt.outcome, EXCLUDED.outcome), explanation = COALESCE(EXCLUDED.explanation, spottr_cv.coaching_attempt.explanation),
      interventions = EXCLUDED.interventions, updated_at = clock_timestamp()
    WHERE spottr_cv.coaching_attempt.user_id = $2 RETURNING *`,
    [a.attemptId, uid(userId), a.workoutId, a.programmeId ?? null, a.nodeId ?? null, a.exercise, a.variation, a.contractVersion, FINAL.has(a.status) || STATUSES.has(a.status) ? a.status : 'setup',
      j(a.target), j(a.baselineReps ?? []), j(a.retryReps ?? []), j(a.cue), j(a.outcome), j(a.explanation), j(a.interventions ?? [])]);
  return r.rows[0] ?? null;
}
const STATUSES = new Set(['setup', 'baseline', 'preparing_cue', 'cue_ready', 'ready_to_retry', 'retry', 'verifying', 'result', 'paused', 'cancelled']);

// Save a finished attempt and the node progress it earns in one transaction. progress: the full desired row (from
// coach.progressFor), so repeating the call yields the same row and never re-awards.
export async function saveAttemptAndProgress(pool, userId, attempt, progress) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const saved = await saveAttempt(pool, userId, attempt, client);
    let node = null;
    if (progress && attempt.programmeId && attempt.nodeId) {
      node = (await client.query(`UPDATE spottr_cv.node_progress SET verification = $4, evidence = $5::jsonb, criteria_version = $6, xp = $7, badges = $8::jsonb,
          completed_at = CASE WHEN $4 <> 'none' THEN COALESCE(completed_at, clock_timestamp()) ELSE completed_at END,
          verified_at = CASE WHEN $4 = 'consistent' THEN COALESCE(verified_at, clock_timestamp()) ELSE verified_at END,
          availability = CASE WHEN availability = 'locked' THEN availability ELSE availability END, updated_at = clock_timestamp()
        WHERE programme_id = $1 AND node_id = $2 AND user_id = $3 RETURNING *`,
        [attempt.programmeId, attempt.nodeId, userId, progress.verification, j(progress.evidence), progress.criteriaVersion, progress.xp, j(progress.badges)])).rows[0] ?? null;
      if (node && node.verification !== 'none') await unlockDependents(client, attempt.programmeId);
    }
    await client.query('COMMIT'); return { attempt: saved, node };
  } catch (e) { await client.query('ROLLBACK').catch(() => {}); throw e; } finally { client.release(); }
}

// Reads for reports: workouts with their reps and the stored forecasts in a period, for one user's workouts. Workouts carry
// no user id yet (the stream predates profiles), so a client tag on the workout note ties them: note 'user:<id>' or any
// workout from the camera on this machine when the id is the local user.
export async function workoutsBetween(pool, { startISO, endISO, exercise = null, source = null }) {
  const w = (await pool.query(`SELECT * FROM spottr_cv.workout WHERE started_at >= $1 AND started_at < $2 AND ($3::text IS NULL OR exercise = $3) AND ($4::text IS NULL OR source = $4) ORDER BY started_at`, [startISO, endISO, exercise, source])).rows;
  const out = [];
  for (const workout of w) out.push({ workout, reps: (await pool.query('SELECT * FROM spottr_cv.rep WHERE workout_id = $1 ORDER BY measured_at', [workout.workout_id])).rows });
  return out;
}
export async function workoutWithReps(pool, workoutId) {
  if (!UUID.test(workoutId ?? '')) return null;
  const workout = (await pool.query('SELECT * FROM spottr_cv.workout WHERE workout_id = $1', [workoutId])).rows[0];
  if (!workout) return null;
  const reps = (await pool.query('SELECT * FROM spottr_cv.rep WHERE workout_id = $1 ORDER BY measured_at', [workoutId])).rows;
  const predictions = (await pool.query('SELECT p.*, o.state, o.outcome, o.onset_offset, o.lead_secs FROM spottr_cv.prediction p LEFT JOIN spottr_cv.prediction_outcome o USING (prediction_id) WHERE p.workout_id = $1 ORDER BY p.rep_n', [workoutId])).rows;
  const attempts = (await pool.query('SELECT * FROM spottr_cv.coaching_attempt WHERE workout_id = $1 ORDER BY created_at', [workoutId])).rows;
  return { workout, reps, predictions, attempts };
}

export async function getSessionReport(pool, workoutId) { return (await pool.query('SELECT * FROM spottr_cv.session_report WHERE workout_id = $1', [workoutId])).rows[0] ?? null; }
export async function saveSessionReport(pool, userId, { workoutId, version, facts, timeline, narrative }) {
  return (await pool.query(`INSERT INTO spottr_cv.session_report (workout_id, user_id, version, facts, timeline, narrative) VALUES ($1, $2, $3, $4::jsonb, $5::jsonb, $6::jsonb)
    ON CONFLICT (workout_id) DO UPDATE SET facts = EXCLUDED.facts, timeline = EXCLUDED.timeline, narrative = COALESCE(EXCLUDED.narrative, spottr_cv.session_report.narrative) RETURNING *`, [workoutId, uid(userId), version, j(facts), j(timeline), j(narrative)])).rows[0];
}

export async function listWeeklyReports(pool, userId) { return (await pool.query('SELECT report_id, period_start, period_end, status, version, created_at, updated_at, input_fingerprint FROM spottr_cv.weekly_report WHERE user_id = $1 ORDER BY period_start DESC, version DESC', [uid(userId)])).rows; }
export async function getWeeklyReport(pool, reportId) { return (await pool.query('SELECT * FROM spottr_cv.weekly_report WHERE report_id = $1', [reportId])).rows[0] ?? null; }
export async function findWeeklyReport(pool, userId, { periodStart, fingerprint }) { return (await pool.query('SELECT * FROM spottr_cv.weekly_report WHERE user_id = $1 AND period_start = $2 AND input_fingerprint = $3 ORDER BY version DESC LIMIT 1', [uid(userId), periodStart, fingerprint])).rows[0] ?? null; }
// Claim generation for a period: returns the existing row when the same inputs were already generated (or are being
// generated), otherwise inserts a 'generating' row. Older versions for the period with a different fingerprint become stale.
export async function claimWeeklyReport(pool, userId, { reportId, periodStart, periodEnd, comparisonStart, timezone, cutoffAt, fingerprint }) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const existing = (await client.query('SELECT * FROM spottr_cv.weekly_report WHERE user_id = $1 AND period_start = $2 AND input_fingerprint = $3 ORDER BY version DESC LIMIT 1 FOR UPDATE', [uid(userId), periodStart, fingerprint])).rows[0];
    if (existing && existing.status !== 'failed') { await client.query('COMMIT'); return { row: existing, claimed: false }; }
    await client.query("UPDATE spottr_cv.weekly_report SET status = 'stale', updated_at = clock_timestamp() WHERE user_id = $1 AND period_start = $2 AND input_fingerprint <> $3 AND status = 'ready'", [userId, periodStart, fingerprint]);
    const v = (await client.query('SELECT COALESCE(MAX(version), 0) + 1 AS v FROM spottr_cv.weekly_report WHERE user_id = $1 AND period_start = $2', [userId, periodStart])).rows[0].v;
    const row = (await client.query(`INSERT INTO spottr_cv.weekly_report (report_id, user_id, period_start, period_end, comparison_start, timezone, cutoff_at, input_fingerprint, status, version) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 'generating', $9) RETURNING *`,
      [reportId, userId, periodStart, periodEnd, comparisonStart, timezone, cutoffAt, fingerprint, v])).rows[0];
    await client.query('COMMIT'); return { row, claimed: true };
  } catch (e) { await client.query('ROLLBACK').catch(() => {}); throw e; } finally { client.release(); }
}
export async function finishWeeklyReport(pool, reportId, { status, facts, narrative, proposedGoals, researchRefs, modelVersion }) {
  return (await pool.query(`UPDATE spottr_cv.weekly_report SET status = $2, facts = $3::jsonb, narrative = $4::jsonb, proposed_goals = $5::jsonb, research_refs = $6::jsonb, model_version = $7, updated_at = clock_timestamp() WHERE report_id = $1 RETURNING *`,
    [reportId, status, j(facts), j(narrative), j(proposedGoals), j(researchRefs ?? []), modelVersion ?? null])).rows[0];
}

export async function getResearch(pool, sourceId) { return (await pool.query('SELECT * FROM spottr_cv.research_source WHERE source_id = $1', [sourceId])).rows[0] ?? null; }
export async function listResearch(pool, owner) { return (await pool.query("SELECT source_id, owner, origin, title, authors, year, url, doi, access, created_at FROM spottr_cv.research_source WHERE owner = $1 OR owner = 'shared' ORDER BY created_at DESC", [owner])).rows; }
export async function saveResearch(pool, s) {
  return (await pool.query(`INSERT INTO spottr_cv.research_source (source_id, owner, origin, title, authors, year, url, doi, access, content_hash, findings, grounding) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11::jsonb, $12::jsonb)
    ON CONFLICT (source_id) DO NOTHING RETURNING *`, [s.sourceId, s.owner, s.origin, s.title, s.authors ?? null, s.year ?? null, s.url ?? null, s.doi ?? null, s.access, s.contentHash ?? null, j(s.findings), j(s.grounding)])).rows[0] ?? await getResearch(pool, s.sourceId);
}

// Live computer-vision telemetry into Tiger Data (PostgreSQL + TimescaleDB): one row per analysed frame (~30 a second),
// one per rep, one per workout, plus the continuous aggregates the pages read back. Shared by the squat and push-up
// prototypes. No dependencies of its own: callers pass their pg Pool class so each prototype uses its own install.
import { existsSync, readFileSync } from 'node:fs';
import { readdir, readFile } from 'node:fs/promises';
import { rootCertificates } from 'node:tls';

export const DB_DIR = new URL('./db/', import.meta.url);
export const EXERCISES = new Set(['squat', 'pushup']);
export const SIGNALS = ['travel', 'depth', 'lean', 'knees', 'balance', 'elbow', 'body_line', 'hip_drop']; // NULL = not judged
export const LIMITS = { frames: 900, reps: 100 }; // one batch a second; 900 frames is 30 s of backlog
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

// Strict TLS always: chain and hostname are verified against the system roots (the team's service has a public CA).
// TIGER_CA_CERT may add an operator-verified root; nothing is ever learned from the server. ssl* URL parameters are
// dropped because pg lets them override the explicit ssl object below.
export async function createPool({ Pool, url = process.env.TIGER_DATABASE_URL || process.env.TIGER_DB_ADDRESS, env = process.env } = {}) {
  if (!url) throw new Error('TIGER_DATABASE_URL is not set');
  let u;
  try { u = new URL(url); } catch { throw new Error('Invalid Tiger connection URL'); }
  if (!['postgres:', 'postgresql:'].includes(u.protocol) || !u.hostname) throw new Error('Invalid Tiger connection URL');
  if (env.NODE_TLS_REJECT_UNAUTHORIZED === '0' || (env.PGSSLMODE && env.PGSSLMODE !== 'verify-full')) throw new Error('TLS verification must stay on');
  for (const k of [...u.searchParams.keys()]) if (/^ssl/i.test(k)) u.searchParams.delete(k);
  const ssl = { rejectUnauthorized: true };
  if (env.TIGER_CA_CERT) {
    if (!existsSync(env.TIGER_CA_CERT)) throw new Error('TIGER_CA_CERT file not found');
    ssl.ca = [...rootCertificates, readFileSync(env.TIGER_CA_CERT, 'utf8')];
  }
  const pool = new Pool({ connectionString: u.toString(), max: 3, connectionTimeoutMillis: 8000, statement_timeout: 20000, ssl });
  pool.on('error', () => {});
  return pool;
}

// Continuous aggregates cannot be created inside a transaction, so each file is sent chunk by chunk (split marker).
export const splitChunks = (sql) => sql.split(/^-- split\s*$/m).map((c) => c.trim()).filter(Boolean);
export async function migrate(pool, dir = DB_DIR) {
  const files = (await readdir(dir)).filter((f) => f.endsWith('.sql')).sort();
  for (const f of files) for (const chunk of splitChunks(await readFile(new URL(f, dir), 'utf8'))) await pool.query(chunk);
  return files;
}

const num = (v) => (typeof v === 'number' && Number.isFinite(v) ? v : null);
const iso = (ms) => (Number.isFinite(ms) && ms > 1e12 && ms < 4e12 ? new Date(ms).toISOString() : null); // epoch ms only
const text = (v, max = 64) => (typeof v === 'string' && v ? v.slice(0, max) : null);
const signals = (o) => Object.fromEntries(SIGNALS.map((s) => [s, num(o[s])]));

// One batch from a page: { workoutId, exercise, start?, end?, frames[], reps[] }. Returns a clean copy or throws.
export function validateBatch(b) {
  if (!b || typeof b !== 'object' || !UUID.test(b.workoutId ?? '') || !EXERCISES.has(b.exercise)) throw new Error('Bad telemetry batch');
  const frames = (Array.isArray(b.frames) ? b.frames : []).slice(-LIMITS.frames)
    .map((f) => ({ measured_at: iso(f.at), clock_ms: Math.max(0, Math.round(num(f.ms) ?? 0)), state: text(f.state) ?? 'unknown', view: text(f.view), ...signals(f) }))
    .filter((f) => f.measured_at);
  const reps = (Array.isArray(b.reps) ? b.reps : []).slice(-LIMITS.reps)
    .map((r) => ({
      measured_at: iso(r.at), rep_n: Math.round(num(r.n) ?? -1), counted: !!r.counted, good: !!r.good, secs: num(r.secs), down_secs: num(r.downSecs), up_secs: num(r.upSecs), issue: text(r.issue, 200),
      faults: (Array.isArray(r.faults) ? r.faults : []).filter((x) => typeof x === 'string').map((x) => x.slice(0, 64)).slice(0, 10),
      ...signals(r),
    }))
    .filter((r) => r.measured_at && r.rep_n >= 0);
  const start = b.start && typeof b.start === 'object'
    ? { variation: text(b.start.variation) ?? 'standard', source: b.start.source === 'video' ? 'video' : 'camera', client: text(b.start.client) ?? 'web', started_at: iso(Date.parse(b.start.startedAt)) ?? new Date().toISOString(), note: text(b.start.note, 200) }
    : null;
  const end = b.end && typeof b.end === 'object' ? { ended_at: iso(Date.parse(b.end.endedAt)) ?? new Date().toISOString() } : null;
  // Forecast records from the page's forecaster (see squat/hrt.mjs) and the outcomes that later point at them.
  const ACTIONS = new Set(['cue', 'silent', 'suppressed']), MODES = new Set(['shadow', 'coaching']), PROV = new Set(['live', 'video', 'synthetic']);
  const forecasts = (Array.isArray(b.forecasts) ? b.forecasts : []).slice(-LIMITS.reps).map((f) => ({
    prediction_id: UUID.test(f.predictionId ?? '') ? f.predictionId.toLowerCase() : null, rep_n: Math.round(num(f.repN) ?? 0), model_run: text(f.modelRun, 120), target_id: text(f.targetId),
    label_version: text(f.labelVersion), feature_version: text(f.featureVersion), policy_version: text(f.policyVersion), horizon: Math.round(num(f.horizon) ?? 0),
    cutoff_at: iso(Date.parse(f.cutoffAt)), emitted_at: iso(Date.parse(f.emittedAt)), features: f.features && typeof f.features === 'object' ? f.features : {},
    probability: num(f.probability), threshold: num(f.threshold), action: ACTIONS.has(f.action) ? f.action : null, suppressed_reason: text(f.suppressedReason),
    delivered_at: f.deliveredAt ? iso(Date.parse(f.deliveredAt)) : null, latency_ms: num(f.latencyMs), mode: MODES.has(f.mode) ? f.mode : null, provenance: PROV.has(f.provenance) ? f.provenance : null,
  })).filter((f) => f.prediction_id && f.rep_n > 0 && f.model_run && f.target_id && f.label_version && f.feature_version && f.policy_version && f.horizon > 0 && f.cutoff_at && f.emitted_at && f.probability != null && f.probability >= 0 && f.probability <= 1 && f.action && f.mode && f.provenance);
  const outcomes = (Array.isArray(b.outcomes) ? b.outcomes : []).slice(-LIMITS.reps).map((o) => ({
    prediction_id: UUID.test(o.predictionId ?? '') ? o.predictionId.toLowerCase() : null, label_version: text(o.labelVersion), state: o.state === 'observed' || o.state === 'excluded' ? o.state : null,
    outcome: o.outcome === 0 || o.outcome === 1 ? o.outcome : null, exclusion_reason: text(o.exclusionReason), onset_offset: num(o.onsetOffset) == null ? null : Math.round(o.onsetOffset), lead_secs: num(o.leadSecs),
    future_reps: Array.isArray(o.futureReps) ? o.futureReps.slice(0, 4) : [], observed_at: iso(Date.parse(o.observedAt)), coached: !!o.coached,
  })).filter((o) => o.prediction_id && o.label_version && o.state && o.observed_at && ((o.state === 'observed') === (o.outcome != null)));
  return { workoutId: b.workoutId.toLowerCase(), exercise: b.exercise, start, end, frames, reps, forecasts, outcomes };
}

const cols = (prefix) => SIGNALS.map((s) => prefix + s).join(', ');
const FRAME_SQL = `INSERT INTO spottr_cv.frame (measured_at, workout_id, exercise, clock_ms, state, view, ${cols('')})
  SELECT f.measured_at, $2::uuid, $3, f.clock_ms, f.state, f.view, ${cols('f.')}
  FROM jsonb_to_recordset($1::jsonb) AS f(measured_at timestamptz, clock_ms integer, state text, view text, ${SIGNALS.map((s) => s + ' real').join(', ')})
  ON CONFLICT DO NOTHING`;
const REP_SQL = `INSERT INTO spottr_cv.rep (measured_at, workout_id, exercise, rep_n, counted, good, secs, down_secs, up_secs, issue, faults, ${cols('')})
  SELECT r.measured_at, $2::uuid, $3, r.rep_n, r.counted, r.good, r.secs, r.down_secs, r.up_secs, r.issue, coalesce(r.faults, '{}'), ${cols('r.')}
  FROM jsonb_to_recordset($1::jsonb) AS r(measured_at timestamptz, rep_n integer, counted boolean, good boolean, secs real, down_secs real, up_secs real, issue text, faults text[], ${SIGNALS.map((s) => s + ' real').join(', ')})
  ON CONFLICT DO NOTHING`;
const FORECAST_SQL = `INSERT INTO spottr_cv.prediction (prediction_id, workout_id, exercise, rep_n, model_run, target_id, label_version, feature_version, policy_version, horizon, cutoff_at, emitted_at,
    features, probability, threshold, action, suppressed_reason, delivered_at, latency_ms, mode, provenance)
  SELECT f.prediction_id, $2::uuid, $3, f.rep_n, f.model_run, f.target_id, f.label_version, f.feature_version, f.policy_version, f.horizon, f.cutoff_at, f.emitted_at,
    f.features, f.probability, f.threshold, f.action, f.suppressed_reason, f.delivered_at, f.latency_ms, f.mode, f.provenance
  FROM jsonb_to_recordset($1::jsonb) AS f(prediction_id uuid, rep_n integer, model_run text, target_id text, label_version text, feature_version text, policy_version text, horizon integer,
    cutoff_at timestamptz, emitted_at timestamptz, features jsonb, probability real, threshold real, action text, suppressed_reason text, delivered_at timestamptz, latency_ms real, mode text, provenance text)
  ON CONFLICT DO NOTHING`; // a forecast is written once and never updated
const OUTCOME_SQL = `INSERT INTO spottr_cv.prediction_outcome (prediction_id, label_version, state, outcome, exclusion_reason, onset_offset, lead_secs, future_reps, observed_at, coached)
  SELECT o.prediction_id, o.label_version, o.state, o.outcome, o.exclusion_reason, o.onset_offset, o.lead_secs, o.future_reps, o.observed_at, o.coached
  FROM jsonb_to_recordset($1::jsonb) AS o(prediction_id uuid, label_version text, state text, outcome smallint, exclusion_reason text, onset_offset smallint, lead_secs real, future_reps jsonb, observed_at timestamptz, coached boolean)
  WHERE EXISTS (SELECT 1 FROM spottr_cv.prediction p WHERE p.prediction_id = o.prediction_id AND p.workout_id = $2::uuid)
  ON CONFLICT DO NOTHING`; // an outcome is added once; a later model never rewrites an earlier forecast's outcome

// One batch = at most four statements. Replays are harmless: every row has a natural key.
export async function ingest(pool, raw) {
  const b = validateBatch(raw);
  const out = { frames: 0, reps: 0, forecasts: 0, outcomes: 0 };
  if (b.start) await pool.query('INSERT INTO spottr_cv.workout (workout_id, exercise, variation, source, client, started_at, note) VALUES ($1, $2, $3, $4, $5, $6, $7) ON CONFLICT (workout_id) DO NOTHING',
    [b.workoutId, b.exercise, b.start.variation, b.start.source, b.start.client, b.start.started_at, b.start.note]);
  if (b.frames.length) out.frames = (await pool.query(FRAME_SQL, [JSON.stringify(b.frames), b.workoutId, b.exercise])).rowCount;
  if (b.reps.length) out.reps = (await pool.query(REP_SQL, [JSON.stringify(b.reps), b.workoutId, b.exercise])).rowCount;
  if (b.forecasts.length) out.forecasts = (await pool.query(FORECAST_SQL, [JSON.stringify(b.forecasts), b.workoutId, b.exercise])).rowCount;
  if (b.outcomes.length) out.outcomes = (await pool.query(OUTCOME_SQL, [JSON.stringify(b.outcomes), b.workoutId])).rowCount;
  if (b.end) await pool.query('UPDATE spottr_cv.workout SET ended_at = $2 WHERE workout_id = $1 AND ended_at IS NULL', [b.workoutId, b.end.ended_at]);
  return out;
}

// What the page's Tiger card shows: how much is stored, how fast it arrives, what columnstore did to it, and how fast the
// continuous aggregates answer. The two rollup reads are timed separately so the card can print real query latency.
export async function status(pool, workoutId) {
  const wid = UUID.test(workoutId ?? '') ? workoutId.toLowerCase() : null;
  const timed = async (sql, params) => { const t = performance.now(); const r = await pool.query(sql, params); return { rows: r.rows, ms: Math.round((performance.now() - t) * 10) / 10 }; };
  const [counts, rate, comp, series, tempo] = await Promise.all([
    pool.query('SELECT (SELECT count(*) FROM spottr_cv.frame)::int AS frames, (SELECT count(*) FROM spottr_cv.rep)::int AS reps, (SELECT count(*) FROM spottr_cv.workout)::int AS workouts'),
    pool.query("SELECT count(*)::int AS n FROM spottr_cv.frame WHERE measured_at > now() - interval '10 seconds'"),
    pool.query("SELECT total_chunks::int AS chunks, number_compressed_chunks::int AS compressed, before_compression_total_bytes::bigint AS before, after_compression_total_bytes::bigint AS after FROM hypertable_columnstore_stats('spottr_cv.frame')"),
    wid ? timed("SELECT extract(epoch FROM bucket)::bigint * 1000 AS t, frames::int, max_travel, min_depth, min_elbow FROM spottr_cv.frame_1s WHERE workout_id = $1 AND bucket > now() - interval '90 seconds' ORDER BY bucket", [wid]) : { rows: [], ms: null },
    wid ? timed('SELECT extract(epoch FROM bucket)::bigint * 1000 AS t, reps::int, good_reps::int, avg_secs, max_secs, avg_depth, min_elbow FROM spottr_cv.rep_1m WHERE workout_id = $1 ORDER BY bucket', [wid]) : { rows: [], ms: null },
  ]);
  const c = comp.rows[0] ?? {};
  const before = Number(c.before ?? 0), after = Number(c.after ?? 0);
  return {
    ...counts.rows[0], rate: rate.rows[0].n / 10,
    chunks: c.chunks ?? 0, compressedChunks: c.compressed ?? 0, bytesBefore: before, bytesAfter: after,
    ratio: before && after ? Math.round((1 - after / before) * 1000) / 10 : null, // percent saved on the compressed chunks
    rollupMs: series.ms, tempoMs: tempo.ms, series: series.rows, tempo: tempo.rows,
  };
}

// Every forecast of a workout with its outcome, for the post-set review and the evidence timeline. Values come from the
// stored rows, never from the page's memory.
export async function review(pool, workoutId) {
  if (!UUID.test(workoutId ?? '')) return [];
  const { rows } = await pool.query(`SELECT p.prediction_id, p.rep_n, p.model_run, p.target_id, p.horizon, p.probability, p.threshold, p.action, p.suppressed_reason, p.mode, p.provenance,
      p.cutoff_at, p.emitted_at, p.delivered_at, p.latency_ms, p.features, o.state, o.outcome, o.exclusion_reason, o.onset_offset, o.lead_secs, o.future_reps, o.observed_at, o.coached
    FROM spottr_cv.prediction p LEFT JOIN spottr_cv.prediction_outcome o USING (prediction_id) WHERE p.workout_id = $1 ORDER BY p.rep_n`, [workoutId.toLowerCase()]);
  return rows;
}

// Register the deployed model once (the artifact and the evaluation summary it shipped with). Replays are ignored.
export async function registerModel(pool, artifact, results = null) {
  if (!artifact?.modelRun) return 0;
  const metrics = results?.dev ? { status: results.status, dev: results.dev.ablations?.full ?? null, policy: results.dev.policies?.full ?? null, test: results.test?.probability?.full ?? null } : null;
  const r = await pool.query(`INSERT INTO spottr_cv.model_run (model_run, git_commit, dataset_sha256, label_version, feature_version, policy_version, hyperparameters, metrics, artifact, status)
    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) ON CONFLICT (model_run) DO NOTHING`,
    [artifact.modelRun, results?.gitCommit ?? null, artifact.trainedOn?.datasetSha256 ?? null, artifact.labelVersion, artifact.featureVersion, artifact.policyVersion,
      JSON.stringify({ lambda: artifact.lambda, threshold: artifact.threshold, horizon: artifact.horizon, minReps: artifact.minReps }), metrics ? JSON.stringify(metrics) : null, JSON.stringify(artifact), artifact.status]);
  return r.rowCount;
}

// Convert every closed frame chunk to columnstore now; the policy does the same a minute after a chunk closes.
export async function compress(pool) {
  const { rows } = await pool.query("SELECT show_chunks('spottr_cv.frame', older_than => now())::text AS chunk");
  for (const { chunk } of rows) await pool.query('CALL convert_to_columnstore($1::regclass, if_not_columnstore => true)', [chunk]); // a procedure, so one CALL per chunk
  return { converted: rows.length };
}

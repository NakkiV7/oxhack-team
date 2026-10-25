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
      measured_at: iso(r.at), rep_n: Math.round(num(r.n) ?? -1), counted: !!r.counted, good: !!r.good, secs: num(r.secs), issue: text(r.issue, 200),
      faults: (Array.isArray(r.faults) ? r.faults : []).filter((x) => typeof x === 'string').map((x) => x.slice(0, 64)).slice(0, 10),
      ...signals(r),
    }))
    .filter((r) => r.measured_at && r.rep_n >= 0);
  const start = b.start && typeof b.start === 'object'
    ? { variation: text(b.start.variation) ?? 'standard', source: b.start.source === 'video' ? 'video' : 'camera', client: text(b.start.client) ?? 'web', started_at: iso(Date.parse(b.start.startedAt)) ?? new Date().toISOString() }
    : null;
  const end = b.end && typeof b.end === 'object' ? { ended_at: iso(Date.parse(b.end.endedAt)) ?? new Date().toISOString() } : null;
  return { workoutId: b.workoutId.toLowerCase(), exercise: b.exercise, start, end, frames, reps };
}

const cols = (prefix) => SIGNALS.map((s) => prefix + s).join(', ');
const FRAME_SQL = `INSERT INTO spottr_cv.frame (measured_at, workout_id, exercise, clock_ms, state, view, ${cols('')})
  SELECT f.measured_at, $2::uuid, $3, f.clock_ms, f.state, f.view, ${cols('f.')}
  FROM jsonb_to_recordset($1::jsonb) AS f(measured_at timestamptz, clock_ms integer, state text, view text, ${SIGNALS.map((s) => s + ' real').join(', ')})
  ON CONFLICT DO NOTHING`;
const REP_SQL = `INSERT INTO spottr_cv.rep (measured_at, workout_id, exercise, rep_n, counted, good, secs, issue, faults, ${cols('')})
  SELECT r.measured_at, $2::uuid, $3, r.rep_n, r.counted, r.good, r.secs, r.issue, coalesce(r.faults, '{}'), ${cols('r.')}
  FROM jsonb_to_recordset($1::jsonb) AS r(measured_at timestamptz, rep_n integer, counted boolean, good boolean, secs real, issue text, faults text[], ${SIGNALS.map((s) => s + ' real').join(', ')})
  ON CONFLICT DO NOTHING`;

// One batch = at most four statements. Replays are harmless: every row has a natural key.
export async function ingest(pool, raw) {
  const b = validateBatch(raw);
  const out = { frames: 0, reps: 0 };
  if (b.start) await pool.query('INSERT INTO spottr_cv.workout (workout_id, exercise, variation, source, client, started_at) VALUES ($1, $2, $3, $4, $5, $6) ON CONFLICT (workout_id) DO NOTHING',
    [b.workoutId, b.exercise, b.start.variation, b.start.source, b.start.client, b.start.started_at]);
  if (b.frames.length) out.frames = (await pool.query(FRAME_SQL, [JSON.stringify(b.frames), b.workoutId, b.exercise])).rowCount;
  if (b.reps.length) out.reps = (await pool.query(REP_SQL, [JSON.stringify(b.reps), b.workoutId, b.exercise])).rowCount;
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

// Convert every closed frame chunk to columnstore now; the policy does the same a minute after a chunk closes.
export async function compress(pool) {
  const { rows } = await pool.query("SELECT show_chunks('spottr_cv.frame', older_than => now())::text AS chunk");
  for (const { chunk } of rows) await pool.query('CALL convert_to_columnstore($1::regclass, if_not_columnstore => true)', [chunk]); // a procedure, so one CALL per chunk
  return { converted: rows.length };
}

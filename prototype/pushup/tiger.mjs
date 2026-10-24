// Tiger Data access for rep history. Database operations accept a pool so offline tests never connect.
import { existsSync, readFileSync } from 'node:fs';
import { readdir, readFile } from 'node:fs/promises';
import { rootCertificates } from 'node:tls';
import { createHash } from 'node:crypto';

export const SOURCES = ['mock', 'real'];

// Rows from the app carry their own measured_at. Rows in the CSV have a date and a rep number but no clock time; reps are spaced 5 s apart from midnight UTC.
export function repTime(row) {
  return new Date(Date.parse(`${row.date}T00:00:00Z`) + (row.rep - 1) * 5000).toISOString();
}

// TIGER_DB_ADDRESS is accepted as an alias for TIGER_DATABASE_URL (the name the team's gateway uses).
// An explicit authenticated CA file (TIGER_CA_CERT) augments normal roots; full verification stays on.
export const trustRoots = (caPem) => [...rootCertificates, caPem];
export async function createPool(url = process.env.TIGER_DATABASE_URL || process.env.TIGER_DB_ADDRESS, { env = process.env, Pool } = {}) {
  if (!url) throw new Error('TIGER_DATABASE_URL is not set. Put it in pushup/.env (gitignored).');
  let parsed;
  try { parsed = new URL(url); } catch { throw new Error('Invalid Tiger connection URL'); }
  if (!['postgres:', 'postgresql:'].includes(parsed.protocol)) throw new Error('Invalid Tiger connection URL');
  if (!parsed.hostname || /%2f/i.test(parsed.hostname)) throw new Error('TLS requires an explicit network hostname');
  if ((env.PGSSLMODE && env.PGSSLMODE !== 'verify-full') || env.NODE_TLS_REJECT_UNAUTHORIZED === '0') throw new Error('TLS verification must remain enabled');
  for (const [key, value] of parsed.searchParams) {
    const lower = key.toLowerCase();
    if ((lower.startsWith('ssl') && !(key === 'sslmode' && value === 'verify-full')) || ['uselibpqcompat', 'host', 'hostaddr'].includes(lower)) throw new Error('TLS URL overrides are not supported; use TIGER_CA_CERT for an authenticated CA');
  }
  parsed.searchParams.delete('sslmode');
  const config = { connectionString: parsed.toString(), max: 2, connectionTimeoutMillis: 8000, statement_timeout: 30000, ssl: { rejectUnauthorized: true } };
  // Trust additional roots only when explicitly supplied by the operator; never learn a CA from the server.
  if (env.TIGER_CA_CERT) {
    if (!existsSync(env.TIGER_CA_CERT)) throw new Error('Configured Tiger CA file is unavailable');
    config.ssl.ca = trustRoots(readFileSync(env.TIGER_CA_CERT, 'utf8'));
  }
  if (!Pool) ({ Pool } = (await import('pg')).default);
  const pool = new Pool(config);
  pool.on('error', () => {});
  return pool;
}

export const splitChunks = (sql) => sql.split(/^-- split\s*$/m).map((c) => c.trim()).filter(Boolean);

export async function migrate(pool, dir = new URL('./db/', import.meta.url)) {
  const files = (await readdir(dir)).filter((f) => f.endsWith('.sql')).sort();
  for (const f of files) for (const chunk of splitChunks(await readFile(new URL(f, dir), 'utf8'))) await pool.query(chunk);
  return files;
}

const workoutUUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const conflict = () => Object.assign(new Error('Workout snapshot conflicts with stored content'), { code: 'workout_conflict' });
const insertSQL = (real) => `INSERT INTO pushup.rep (measured_at, user_id, session, rep, elbow, body_line, seconds, counted, label, source${real ? ', workout_id' : ''})
       SELECT s.measured_at, $2, s.session, s.rep, s.elbow, s.body_line, s.seconds, s.counted, s.label, $3${real ? ', $4::uuid' : ''}
       FROM jsonb_to_recordset($1::jsonb) AS s(measured_at timestamptz, session integer, rep integer, elbow double precision,
         body_line double precision, seconds double precision, counted boolean, label text)
       ${real ? '' : 'ON CONFLICT DO NOTHING'}`;

// Mock CSV imports retain their synthetic spacing. Real snapshots require observed times and an immutable receipt.
export async function insertReps(pool, rows, { userId, source, workoutId, contentHash }) {
  if (!SOURCES.includes(source)) throw new Error(`source must be one of ${SOURCES.join(', ')}`);
  if (typeof userId !== 'string' || !userId.trim() || userId.length > 128) throw new Error('userId is required');
  if (source === 'real' && (!workoutUUID.test(workoutId ?? '') || !/^[a-f0-9]{64}$/.test(contentHash ?? '') || !Array.isArray(rows) || rows.length < 1 || rows.length > 500)) throw new Error('Invalid real workout snapshot identity or size');
  const payload = rows.map((r) => {
    if (source === 'real' && (typeof r.measured_at !== 'string' || !Number.isFinite(Date.parse(r.measured_at)))) throw new Error('Actual observation time is required');
    return { measured_at: source === 'real' ? new Date(r.measured_at).toISOString() : r.measured_at ?? repTime(r), session: r.session, rep: r.rep, elbow: r.elbow, body_line: r.body_line,
      seconds: r.seconds, counted: !!r.counted, label: r.label };
  });
  if (source === 'mock') {
    let added = 0;
    for (let i = 0; i < payload.length; i += 500) added += (await pool.query(insertSQL(false), [JSON.stringify(payload.slice(i, i + 500)), userId, source])).rowCount;
    return added;
  }
  workoutId = workoutId.toLowerCase();
  // Bind the HTTP digest and the rows, so even internal callers cannot reuse a receipt for changed measurements.
  const hash = createHash('sha256').update(JSON.stringify({ workoutId, userId, source, contentHash, rows: payload })).digest('hex');
  const client = await pool.connect();
  let discard;
  try {
    await client.query('BEGIN');
    const receipt = await client.query('INSERT INTO pushup.workout_receipt (user_id, workout_id, content_hash, rep_count) VALUES ($1, $2, $3, $4) ON CONFLICT (user_id, workout_id) DO NOTHING RETURNING content_hash', [userId, workoutId, hash, payload.length]);
    if (!receipt.rowCount) {
      const { rows: existing } = await client.query('SELECT content_hash, rep_count FROM pushup.workout_receipt WHERE user_id = $1 AND workout_id = $2', [userId, workoutId]);
      if (existing[0]?.content_hash !== hash || existing[0]?.rep_count !== payload.length) throw conflict();
      await client.query('COMMIT');
      return 0;
    }
    const result = await client.query(insertSQL(true), [JSON.stringify(payload), userId, source, workoutId]);
    if (result.rowCount !== payload.length) throw conflict();
    await client.query('COMMIT');
    return result.rowCount;
  } catch (error) {
    try { await client.query('ROLLBACK'); } catch (rollbackError) { discard = rollbackError; }
    if (error.code === '23505') throw conflict();
    throw error;
  } finally { client.release(discard); }
}

// Same row shape profile.mjs expects from the CSV. `sources` filters mock vs real.
export async function readReps(pool, { userId, sources = SOURCES }) {
  const res = await pool.query(
    `SELECT session, rep, elbow, body_line, seconds, counted, label, source, workout_id
     FROM pushup.rep WHERE user_id = $1 AND source = ANY($2::text[]) ORDER BY measured_at`,
    [userId, sources],
  );
  return res.rows;
}

// Per-session trend from the continuous aggregate, plus any rows newer than its last refresh.
export async function sessionStats(pool, { userId }) {
  const res = await pool.query(
    `SELECT day, session, source, reps, good_reps, round(good_elbow::numeric, 1) AS good_elbow,
            round(good_body_line::numeric, 1) AS good_body_line, round(avg_seconds::numeric, 1) AS avg_seconds
     FROM pushup.session_stats WHERE user_id = $1 ORDER BY day, session`,
    [userId],
  );
  return res.rows;
}

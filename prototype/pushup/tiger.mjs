// Tiger Data (Postgres + TimescaleDB) access for rep history. Takes a `pool` (pg.Pool or anything with
// .query), so tests can pass a fake and nothing here opens a connection by itself.
import { existsSync, readFileSync } from 'node:fs';
import { readdir, readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { rootCertificates } from 'node:tls';

export const SOURCES = ['mock', 'real'];

// Rows from the app carry their own measured_at. Rows in the CSV have a date and a rep number but no clock time; reps are spaced 5 s apart from midnight UTC.
export function repTime(row) {
  return new Date(Date.parse(`${row.date}T00:00:00Z`) + (row.rep - 1) * 5000).toISOString();
}

// TIGER_DB_ADDRESS is accepted as an alias for TIGER_DATABASE_URL (the name the team's gateway uses).
// Tiger has served certificates signed by its own CA (ca.timescale.com, not publicly trusted) and, later, by a public
// CA. An optional CA file (TIGER_CA_CERT, default certs/tiger-ca.pem) is trusted IN ADDITION to Node's normal roots,
// so either chain verifies and full verification stays on.
export const trustRoots = (caPem) => [...rootCertificates, caPem];
export async function createPool(url = process.env.TIGER_DATABASE_URL || process.env.TIGER_DB_ADDRESS) {
  if (!url) throw new Error('TIGER_DATABASE_URL is not set. Put it in pushup/.env (gitignored).');
  const { default: pg } = await import('pg');
  const caFile = process.env.TIGER_CA_CERT || fileURLToPath(new URL('./certs/tiger-ca.pem', import.meta.url));
  const config = { connectionString: url, max: 2, connectionTimeoutMillis: 8000, statement_timeout: 30000 };
  if (existsSync(caFile)) {
    // pg lets sslmode in the URL override the ssl option, so drop it and pass ssl explicitly.
    const u = new URL(url);
    u.searchParams.delete('sslmode');
    config.connectionString = u.toString();
    config.ssl = { ca: trustRoots(readFileSync(caFile, 'utf8')), rejectUnauthorized: true };
  }
  const pool = new pg.Pool(config);
  pool.on('error', () => {});
  return pool;
}

export const splitChunks = (sql) => sql.split(/^-- split\s*$/m).map((c) => c.trim()).filter(Boolean);

export async function migrate(pool, dir = new URL('./db/', import.meta.url)) {
  const files = (await readdir(dir)).filter((f) => f.endsWith('.sql')).sort();
  for (const f of files) for (const chunk of splitChunks(await readFile(new URL(f, dir), 'utf8'))) await pool.query(chunk);
  return files;
}

// Idempotent: a rep that is already stored (same time, user, session, rep) is skipped. Returns rows added.
export async function insertReps(pool, rows, { userId, source }) {
  if (!SOURCES.includes(source)) throw new Error(`source must be one of ${SOURCES.join(', ')}`);
  if (!userId) throw new Error('userId is required');
  const payload = rows.map((r) => ({
    measured_at: r.measured_at ?? repTime(r), session: r.session, rep: r.rep, elbow: r.elbow, body_line: r.body_line,
    seconds: r.seconds, counted: !!r.counted, label: r.label,
  }));
  let added = 0;
  for (let i = 0; i < payload.length; i += 500) {
    const res = await pool.query(
      `INSERT INTO pushup.rep (measured_at, user_id, session, rep, elbow, body_line, seconds, counted, label, source)
       SELECT s.measured_at, $2, s.session, s.rep, s.elbow, s.body_line, s.seconds, s.counted, s.label, $3
       FROM jsonb_to_recordset($1::jsonb) AS s(measured_at timestamptz, session integer, rep integer, elbow double precision,
         body_line double precision, seconds double precision, counted boolean, label text)
       ON CONFLICT DO NOTHING`,
      [JSON.stringify(payload.slice(i, i + 500)), userId, source],
    );
    added += res.rowCount;
  }
  return added;
}

// Same row shape profile.mjs expects from the CSV. `sources` filters mock vs real.
export async function readReps(pool, { userId, sources = SOURCES }) {
  const res = await pool.query(
    `SELECT session, rep, elbow, body_line, seconds, counted, label, source
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

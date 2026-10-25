import test from 'node:test';
import assert from 'node:assert/strict';
import { readdir, readFile } from 'node:fs/promises';
import { validateBatch, ingest, createPool, splitChunks, DB_DIR, LIMITS } from '../../shared/tiger-stream.mjs';

const WID = '0b9d3f2e-1c4a-4e8b-9f3a-2b6c7d8e9f01';
const T = 1_800_000_000_000; // an epoch in ms
const fakePool = () => {
  const calls = [];
  return { calls, query: async (sql, params) => { calls.push({ sql, params }); return { rowCount: /jsonb/.test(sql) ? JSON.parse(params[0]).length : 1, rows: [] }; } };
};

test('validateBatch rejects bad ids and exercises and cleans every number', () => {
  assert.throws(() => validateBatch({ workoutId: 'nope', exercise: 'squat' }));
  assert.throws(() => validateBatch({ workoutId: WID, exercise: 'deadlift' }));
  const b = validateBatch({ workoutId: WID.toUpperCase(), exercise: 'squat',
    frames: [{ at: T, ms: 12.6, state: 'down', travel: 0.31, depth: NaN, lean: '12' }, { at: 'bad', ms: 1 }],
    reps: [{ at: T + 500, n: 1, counted: true, good: false, secs: 1.2, faults: ['Deeper', 7] }, { at: T + 600, n: -3 }] });
  assert.equal(b.workoutId, WID);
  assert.equal(b.frames.length, 1);
  assert.deepEqual([b.frames[0].clock_ms, b.frames[0].travel, b.frames[0].depth, b.frames[0].lean, b.frames[0].elbow], [13, 0.31, null, null, null]);
  assert.equal(b.reps.length, 1);
  assert.deepEqual(b.reps[0].faults, ['Deeper']);
  assert.equal(b.start, null);
});

test('batches keep only the newest rows past the cap', () => {
  const frames = Array.from({ length: LIMITS.frames + 50 }, (_, i) => ({ at: T + i, ms: i }));
  const b = validateBatch({ workoutId: WID, exercise: 'pushup', frames });
  assert.equal(b.frames.length, LIMITS.frames);
  assert.equal(b.frames.at(-1).clock_ms, LIMITS.frames + 49);
});

test('ingest sends the workout row, one frame insert, one rep insert and the end mark', async () => {
  const pool = fakePool();
  const out = await ingest(pool, { workoutId: WID, exercise: 'squat',
    start: { variation: 'standard', source: 'camera', client: 'squat-web', startedAt: '2026-10-25T03:00:00Z' }, end: { endedAt: '2026-10-25T03:01:00Z' },
    frames: [{ at: T, ms: 0, state: 'standing' }, { at: T + 33, ms: 33, state: 'standing' }], reps: [{ at: T + 1000, n: 1, counted: true, good: true, secs: 1.5 }] });
  assert.deepEqual(out, { frames: 2, reps: 1 });
  assert.deepEqual(pool.calls.map((c) => c.sql.trim().split(/\s+/).slice(0, 3).join(' ')),
    ['INSERT INTO spottr_cv.workout', 'INSERT INTO spottr_cv.frame', 'INSERT INTO spottr_cv.rep', 'UPDATE spottr_cv.workout SET']);
  assert.equal(pool.calls[0].params[3], 'camera');
  assert.equal(pool.calls[1].params[1], WID);
  assert.equal(JSON.parse(pool.calls[2].params[0])[0].secs, 1.5);
});

test('an empty batch touches nothing', async () => {
  const pool = fakePool();
  assert.deepEqual(await ingest(pool, { workoutId: WID, exercise: 'squat' }), { frames: 0, reps: 0 });
  assert.equal(pool.calls.length, 0);
});

test('createPool keeps TLS verification on and strips ssl overrides from the URL', async () => {
  let cfg;
  const Pool = class { constructor(c) { cfg = c; } on() {} };
  await createPool({ Pool, url: 'postgres://u:p@db.example.com:5432/tsdb?sslmode=require', env: {} });
  assert.equal(cfg.ssl.rejectUnauthorized, true);
  assert.ok(!cfg.connectionString.includes('sslmode'));
  await assert.rejects(createPool({ Pool, url: 'postgres://u:p@db.example.com/tsdb', env: { NODE_TLS_REJECT_UNAUTHORIZED: '0' } }));
  await assert.rejects(createPool({ Pool, url: 'postgres://u:p@db.example.com/tsdb', env: { PGSSLMODE: 'disable' } }));
  await assert.rejects(createPool({ Pool, url: 'mysql://x', env: {} }));
  await assert.rejects(createPool({ Pool, url: 'postgres://u:p@db.example.com/tsdb', env: { TIGER_CA_CERT: '/nonexistent.pem' } }));
  await assert.rejects(createPool({ Pool, url: '', env: {} }));
});

test('migration files split into statements that start with SQL', async () => {
  const files = (await readdir(DB_DIR)).filter((f) => f.endsWith('.sql')).sort();
  assert.deepEqual(files, ['001_cv_stream.sql', '002_cv_rollups.sql']);
  for (const f of files) {
    const chunks = splitChunks(await readFile(new URL(f, DB_DIR), 'utf8'));
    assert.ok(chunks.length >= 1, f);
    for (const c of chunks) assert.match(c, /^(--[^\n]*\n|\n)*(BEGIN|CREATE|ALTER|SELECT|CALL)\b/, `${f}: ${c.slice(0, 40)}`);
  }
});

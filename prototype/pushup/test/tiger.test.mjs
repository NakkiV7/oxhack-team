import test from 'node:test';
import assert from 'node:assert/strict';
import { repTime, splitChunks, insertReps, readReps, migrate, trustRoots, createPool } from '../tiger.mjs';

const fakePool = (rowCount = 0, rows = []) => {
  const calls = [];
  return { calls, query: async (sql, params) => (calls.push({ sql, params }), { rowCount, rows }) };
};
const row = { session: 1, date: '2026-10-01', rep: 3, elbow: 64, body_line: 171, seconds: 3.5, counted: 1, label: 'good' };

test('rep time is the date plus 5 s per rep', () => {
  assert.equal(repTime({ date: '2026-10-01', rep: 1 }), '2026-10-01T00:00:00.000Z');
  assert.equal(repTime({ date: '2026-10-01', rep: 3 }), '2026-10-01T00:00:10.000Z');
});

test('the continuous aggregate migration is sent as separate queries', () => {
  assert.equal(splitChunks('A;\n-- split\nB;\n').length, 2);
  assert.equal(splitChunks('BEGIN;\nX;\nCOMMIT;').length, 1);
});

test('insertReps sends rows as JSON with user and source, and counts what was added', async () => {
  const pool = fakePool(1);
  assert.equal(await insertReps(pool, [row], { userId: 'azhar', source: 'mock' }), 1);
  const [{ sql, params }] = pool.calls;
  assert.match(sql, /ON CONFLICT DO NOTHING/);
  assert.equal(params[1], 'azhar');
  assert.equal(params[2], 'mock');
  assert.deepEqual(JSON.parse(params[0])[0], { measured_at: '2026-10-01T00:00:10.000Z', session: 1, rep: 3, elbow: 64, body_line: 171, seconds: 3.5, counted: true, label: 'good' });
});

test('insertReps rejects an unknown source or missing user without querying', async () => {
  const pool = fakePool();
  await assert.rejects(insertReps(pool, [row], { userId: 'a', source: 'fake' }), /source/);
  await assert.rejects(insertReps(pool, [row], { userId: '', source: 'mock' }), /userId/);
  assert.equal(pool.calls.length, 0);
});

test('readReps filters by user and source', async () => {
  const pool = fakePool(0, [{ label: 'good' }]);
  assert.deepEqual(await readReps(pool, { userId: 'azhar', sources: ['real'] }), [{ label: 'good' }]);
  assert.deepEqual(pool.calls[0].params, ['azhar', ['real']]);
});

test('migrate runs every db/*.sql file, one query per chunk', async () => {
  const pool = fakePool();
  const files = await migrate(pool);
  assert.deepEqual(files, ['001_pushup_reps.sql', '002_session_stats.sql', '003_label_values.sql', '004_immutable_workouts.sql']);
  assert.equal(pool.calls.length, 5);
});

test('a pinned CA is trusted in addition to the normal roots, not instead of them', () => {
  const roots = trustRoots('PINNED');
  assert.equal(roots.at(-1), 'PINNED');
  assert.ok(roots.length > 50);
});

const workoutId = '5bc9a693-1b37-4401-b382-5a5c9b185b0e';
const real = { ...row, measured_at: '2026-10-24T12:00:03.500Z', counted: true };
const scope = { userId: 'synthetic', source: 'real', workoutId, contentHash: 'a'.repeat(64) };

// A transactional database boundary: receipt ownership and committed row state remain observable.
function transactionalPool({ failInsert = false, failRollback = false } = {}) {
  let receipts = new Map(), stored = [], discarded = false;
  const pool = { async query(sql, params) {
    if (!sql.includes('INSERT INTO pushup.rep')) throw Error('Unexpected direct query');
    if (failInsert) throw Error('synthetic write failed');
    const incoming = JSON.parse(params[0]).map(r => ({ ...r, userId: params[1], source: params[2], workoutId: params[3] }));
    for (const r of incoming) if (!stored.some(old => old.userId === r.userId && old.measured_at === r.measured_at && old.session === r.session && old.rep === r.rep)) stored.push(r);
    return { rowCount: incoming.length };
  }, get rows() { return stored; }, get receipts() { return receipts; }, get discarded() { return discarded; }, async connect() {
    let nextReceipts, nextRows;
    return { async query(sql, params = []) {
      if (sql === 'BEGIN') { nextReceipts = new Map(receipts); nextRows = [...stored]; return {}; }
      if (sql === 'COMMIT') { receipts = nextReceipts; stored = nextRows; return {}; }
      if (sql === 'ROLLBACK') { if (failRollback) throw Error('rollback failed'); return {}; }
      if (sql.startsWith('INSERT INTO pushup.workout_receipt')) {
        const [user, id, hash, count] = params, key = user + ':' + id;
        if (nextReceipts.has(key)) return { rowCount: 0, rows: [] };
        nextReceipts.set(key, { content_hash: hash, rep_count: count });
        return { rowCount: 1, rows: [{ content_hash: hash }] };
      }
      if (sql.startsWith('SELECT content_hash')) return { rows: [nextReceipts.get(params[0] + ':' + params[1])].filter(Boolean) };
      if (sql.includes('INSERT INTO pushup.rep')) {
        if (failInsert) throw Error('synthetic write failed');
        const rows = JSON.parse(params[0]).map(r => ({ ...r, userId: params[1], source: params[2], workoutId: params[3] }));
        nextRows.push(...rows); return { rowCount: rows.length };
      }
      throw Error('Unexpected database operation');
    }, release(error) { discarded = !!error; } };
  } };
  return pool;
}

test('real snapshots preserve observation times, replay exactly and reject changed content atomically', async () => {
  const pool = transactionalPool();
  assert.equal(await insertReps(pool, [real], scope), 1);
  assert.equal(pool.rows[0].measured_at, real.measured_at);
  assert.equal(pool.rows[0].workoutId, workoutId);
  assert.equal(await insertReps(pool, [structuredClone(real)], { ...scope }), 0);
  for (const [rows, options] of [[[real], { ...scope, contentHash: 'b'.repeat(64) }], [[{ ...real, elbow: 80 }], scope], [[{ ...real, measured_at: '2026-10-24T12:00:04.000Z' }], scope]]) {
    await assert.rejects(insertReps(pool, rows, options), error => error.code === 'workout_conflict');
  }
  assert.equal(pool.rows.length, 1);
  assert.equal(pool.receipts.size, 1);
  assert.equal(pool.rows[0].elbow, 64);
});

test('real write failure rolls back both receipt and reps, and failed rollback discards the client', async () => {
  for (const failRollback of [false, true]) {
    const pool = transactionalPool({ failInsert: true, failRollback });
    await assert.rejects(insertReps(pool, [real], scope), /synthetic write failed/);
    assert.equal(pool.rows.length, 0);
    assert.equal(pool.receipts.size, 0);
    assert.equal(pool.discarded, failRollback);
  }
});

test('different owners have independent immutable receipt scopes', async () => {
  const pool = transactionalPool();
  assert.equal(await insertReps(pool, [real], scope), 1);
  assert.equal(await insertReps(pool, [real], { ...scope, userId: 'another-owner' }), 1);
  assert.equal(pool.receipts.size, 2);
});

test('real writes require a bounded UUID snapshot and actual observation dates before acquiring a connection', async () => {
  const pool = { connect() { throw Error('must not connect'); } };
  for (const [rows, options] of [[[real], { ...scope, workoutId: undefined }], [[real], { ...scope, contentHash: undefined }], [[{ ...real, measured_at: undefined }], scope], [[{ ...real, measured_at: 'invalid' }], scope], [Array(501).fill(real), scope]]) {
    await assert.rejects(insertReps(pool, rows, options), error => /snapshot|observation/i.test(error.message));
  }
});

test('Tiger pool defaults to verified TLS and rejects URL and environment verification downgrades', async () => {
  class Pool { constructor(options) { this.options = options; } on() {} }
  const good = await createPool('postgresql://synthetic:synthetic@localhost/example?sslmode=verify-full', { env: {}, Pool });
  assert.equal(good.options.ssl.rejectUnauthorized, true);
  assert.equal(new URL(good.options.connectionString).searchParams.has('sslmode'), false);
  const plain = await createPool('postgresql://synthetic:synthetic@localhost/example', { env: {}, Pool });
  assert.equal(plain.options.ssl.rejectUnauthorized, true);
  for (const query of ['sslmode=disable', 'sslmode=no-verify', 'ssl=false', 'sslrootcert=untrusted', 'sslcert=client', 'sslkey=private', 'uselibpqcompat=true', 'sslmode=verify-ca']) {
    await assert.rejects(createPool('postgresql://synthetic:synthetic@localhost/example?' + query, { env: {}, Pool }), /TLS/);
  }
  for (const env of [{ PGSSLMODE: 'disable' }, { PGSSLMODE: 'no-verify' }, { NODE_TLS_REJECT_UNAUTHORIZED: '0' }]) {
    await assert.rejects(createPool('postgresql://synthetic:synthetic@localhost/example', { env, Pool }), /TLS/);
  }
});

// A PostgreSQL Unix-domain connection bypasses TLS entirely even when pg receives ssl options.
test('Tiger rejects Unix socket and missing-host routes that bypass the verified TLS transport', async () => {
  class Pool { constructor(options) { this.options = options; } on() {} }
  for (const url of ['postgresql:///example', 'postgresql://%2Ftmp/example', 'postgresql://localhost/example?host=/tmp', 'postgresql://localhost/example?hostaddr=127.0.0.1']) {
    await assert.rejects(createPool(url, { env: {}, Pool }), /TLS/);
  }
});

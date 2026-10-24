import test from 'node:test';
import assert from 'node:assert/strict';
import { repTime, splitChunks, insertReps, readReps, migrate, trustRoots } from '../tiger.mjs';

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

test('insertReps keeps a row\'s own measured_at when it has one', async () => {
  const pool = fakePool(1);
  await insertReps(pool, [{ ...row, measured_at: '2026-10-24T12:00:00.000Z' }], { userId: 'a', source: 'real' });
  assert.equal(JSON.parse(pool.calls[0].params[0])[0].measured_at, '2026-10-24T12:00:00.000Z');
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
  assert.deepEqual(files, ['001_pushup_reps.sql', '002_session_stats.sql', '003_label_values.sql']);
  assert.equal(pool.calls.length, 4);
});

test('a pinned CA is trusted in addition to the normal roots, not instead of them', () => {
  const roots = trustRoots('PINNED');
  assert.equal(roots.at(-1), 'PINNED');
  assert.ok(roots.length > 50);
});

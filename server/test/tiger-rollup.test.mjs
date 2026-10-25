import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';
import { createTigerStore } from '../src/tiger.mjs';

const installationID = 'f17e0000-0000-4000-8000-000000000101';
const workoutID = 'f17e0000-0000-4000-8000-000000000102';
const date = seconds => `2000-01-01T00:00:${seconds}Z`;
const record = {
  id: workoutID, date: date('00'), sets: [], loggedSets: [], telemetry: [
    { sessionID: workoutID, sentAt: date('02'), heartRate: { value: 1, date: date('00.500') }, accelerationG: { value: 0, date: date('01') }, rotationRadiansPerSecond: { value: 0, date: date('01') } },
    { sessionID: workoutID, sentAt: date('05'), heartRate: { value: 3, date: date('04.500') }, accelerationG: { value: 2, date: date('04.500') } },
    { sessionID: workoutID, sentAt: date('07'), heartRate: { value: 5, date: date('05') } },
    { sessionID: workoutID, sentAt: date('16'), heartRate: { value: 7, date: date('15') } },
    { sessionID: workoutID, sentAt: date('17'), heartRate: { value: 1, date: date('00.500') } }
  ]
};

async function database(t) {
  const pg = new PGlite();
  t.after(() => pg.close());
  // Execute the real migration in PostgreSQL, omitting only unavailable Timescale
  // extension/hypertable calls. This validates SQL, not Timescale partitioning.
  const migration = await readFile(new URL('../migrations/001_workouts.sql', import.meta.url), 'utf8');
  await pg.exec(migration.replace('CREATE EXTENSION IF NOT EXISTS timescaledb;', '')
    .replace(/^SELECT create_hypertable\([^\n]+\);$/m, ''));
  const pool = { query: (sql, values) => pg.query(sql, values), connect: async () => ({ query: (sql, values) => pg.query(sql, values), release() {} }) };
  return { pg, pool, store: createTigerStore({ installationID, pool }) };
}

function compact(result) {
  return result.buckets.map(row => [new Date(row.bucket).toISOString(), row.kind, row.observedSamples, row.mean, row.min, row.max,
    new Date(row.firstMeasuredAt).toISOString(), new Date(row.lastMeasuredAt).toISOString(), row.unit, row.source]);
}

test('PostgreSQL rollups keep observed counts, metric units, original timestamps and empty gaps after replay', async t => {
  const { store, pg, pool } = await database(t);
  const first = await store.ingest({ installationID, record });
  assert.equal(first.replayed, false);
  assert.deepEqual((await store.read(workoutID)).record, record);
  assert.equal((await store.ingest({ installationID, record })).replayed, true);
  await assert.rejects(store.ingest({ installationID, record: { ...record, date: date('01') } }), error => error.status === 409);
  assert.equal((await pg.query('SELECT count(*)::integer AS n FROM spottr_gateway.scalar_sample')).rows[0].n, 7);
  // Same workout under another owner, and another workout under this owner,
  // must never contaminate either the aggregates or observation counts.
  const foreign = createTigerStore({ installationID: workoutID, pool });
  await foreign.ingest({ installationID: workoutID, record: { ...record, telemetry: [{ sessionID: workoutID, sentAt: date('02'), heartRate: { value: 100, date: date('01') } }] } });
  await store.ingest({ installationID, record: { ...record, id: installationID, telemetry: [{ sessionID: installationID, sentAt: date('02'), heartRate: { value: 200, date: date('01') } }] } });
  const result = await store.rollups({ workoutID, from: date('00'), to: date('16'), bucketSeconds: 5 });
  assert.equal(result.bucketSeconds, 5);
  assert.equal(result.from, date('00'));
  assert.equal(result.to, date('16'));
  assert.deepEqual(compact(result), [
    [date('00.000'), 'accelerationMagnitude', 2, 1, 0, 2, date('01.000'), date('04.500'), 'g', 'apple_watch'],
    [date('00.000'), 'heartRate', 2, 2, 1, 3, date('00.500'), date('04.500'), 'bpm', 'apple_watch'],
    [date('00.000'), 'rotationMagnitude', 1, 0, 0, 0, date('01.000'), date('01.000'), 'rad/s', 'apple_watch'],
    [date('05.000'), 'heartRate', 1, 5, 5, 5, date('05.000'), date('05.000'), 'bpm', 'apple_watch'],
    [date('15.000'), 'heartRate', 1, 7, 7, 7, date('15.000'), date('15.000'), 'bpm', 'apple_watch']
  ]);
  const minute = await store.rollups({ workoutID, from: date('00'), to: date('16'), bucketSeconds: 60 });
  assert.deepEqual(compact(minute).find(row => row[1] === 'heartRate'), [date('00.000'), 'heartRate', 4, 4, 1, 7, date('00.500'), date('15.000'), 'bpm', 'apple_watch']);
  const partial = await store.rollups({ workoutID, from: date('01'), to: date('05'), bucketSeconds: 5 });
  assert.deepEqual(compact(partial).find(row => row[1] === 'heartRate'), [date('00.000'), 'heartRate', 1, 3, 3, 3, date('04.500'), date('04.500'), 'bpm', 'apple_watch']);
  assert.deepEqual((await store.rollups({ workoutID, from: date('10'), to: date('15'), bucketSeconds: 5 })).buckets, []);
});

test('rollups validate finite bounds before database access and enforce workout ownership', async t => {
  let queries = 0;
  const store = createTigerStore({ installationID, pool: { query: async () => { queries++; throw Error('must not query'); } } });
  const query = { workoutID, from: date('00'), to: date('16'), bucketSeconds: 5 };
  for (const invalid of [
    { ...query, bucketSeconds: 0 }, { ...query, bucketSeconds: 1 }, { ...query, bucketSeconds: '5' },
    { ...query, bucketSeconds: 5.5 }, { ...query, bucketSeconds: Infinity }, { ...query, extra: true },
    { ...query, from: 'invalid' }, { ...query, to: date('00') }, { ...query, to: '2000-01-02T00:00:01Z' }
  ]) await assert.rejects(store.rollups(invalid), error => error.status === 422);
  assert.equal(queries, 0);
  const db = await database(t);
  await db.store.ingest({ installationID, record });
  const foreign = createTigerStore({ installationID: workoutID, pool: db.pool });
  await assert.rejects(foreign.rollups(query), error => error.status === 404);
});

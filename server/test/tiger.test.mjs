import assert from 'node:assert/strict';
import test from 'node:test';
import { createTigerStore } from '../src/tiger.mjs';
import { createGateway } from '../src/gateway.mjs';
import { once } from 'node:events';
import { spawnSync } from 'node:child_process';

const installationID = '5aa3804a-58e8-49fb-876f-5751ac9cbaca';
const workoutID = '5c69ed48-c98e-4b4e-8e21-78d246743535';
const record = {
  id: workoutID, date: '2026-10-24T10:00:00Z', sets: [], loggedSets: [],
  telemetry: [{ sessionID: workoutID, sentAt: '2026-10-24T10:01:00Z', heartRate: { value: 110, date: '2026-10-24T10:00:59Z' }, accelerationG: { value: 1.1, date: '2026-10-24T10:01:00Z' }, rotationRadiansPerSecond: { value: 0.4, date: '2026-10-24T10:01:00Z' } }]
};

function database() {
  let stored = null;
  const samples = [];
  const operations = [];
  const client = {
    async query(text, values) {
      operations.push(text);
      if (text.includes('INSERT INTO spottr_gateway.workout')) {
        if (stored) return { rows: [] };
        stored = { installation_id: values[0], workout_id: values[1], payload_sha256: values[2], record: JSON.parse(values[3]) };
        return { rows: [{ workout_id: values[1] }] };
      }
      if (text.includes('INSERT INTO spottr_gateway.scalar_sample')) { samples.push(...JSON.parse(values[0])); return { rows: [] }; }
      if (text.includes('FROM spottr_gateway.scalar_sample')) return { rows: samples.filter(sample => sample.measured_at >= values[2] && sample.measured_at < values[3]).map(sample => ({ measuredAt: sample.measured_at, sentAt: sample.sent_at, kind: sample.kind, value: sample.value, unit: sample.unit, source: sample.source })) };
      if (text.includes('SELECT') && text.includes('spottr_gateway.workout')) return { rows: stored && stored.installation_id === values[0] && stored.workout_id === values[1] ? [stored] : [] };
      return { rows: [] };
    },
    release() { operations.push('release'); }
  };
  return { pool: { connect: async () => client, query: client.query }, samples, operations };
}

test('Tiger writes one immutable session snapshot and timestamped observed scalar samples atomically', async () => {
  const db = database();
  const store = createTigerStore({ pool: db.pool, installationID });
  const first = await store.ingest({ installationID, record });
  assert.equal(first.replayed, false);
  assert.equal(first.workoutID, workoutID);
  assert.match(first.sha256, /^[a-f0-9]{64}$/);
  assert.deepEqual(db.samples.map(sample => [sample.kind, sample.value, sample.unit]), [['heartRate', 110, 'bpm'], ['accelerationMagnitude', 1.1, 'g'], ['rotationMagnitude', 0.4, 'rad/s']]);
  assert.equal(db.samples[0].measured_at, record.telemetry[0].heartRate.date);
  assert.equal(db.operations[0], 'BEGIN');
  assert.equal(db.operations.at(-2), 'COMMIT');
  assert.equal(db.operations.at(-1), 'release');
  assert.equal((await store.ingest({ installationID, record })).replayed, true);
  assert.equal(db.samples.length, 3);
  await assert.rejects(store.ingest({ installationID, record: { ...record, date: '2026-10-24T11:00:00Z' } }), error => error.status === 409);
  assert.deepEqual((await store.read(workoutID)).record, record);
});

test('Tiger rejects foreign installations, invalid units, unknown fields and foreign telemetry before database access', async () => {
  let connections = 0;
  const store = createTigerStore({ installationID, pool: { connect: async () => { connections += 1; throw Error('must not connect'); } } });
  await assert.rejects(store.ingest({ installationID: workoutID, record }), error => error.status === 403);
  const invalid = [
    { ...record, extra: true },
    { ...record, date: 'not-a-date' },
    { ...record, telemetry: [{ ...record.telemetry[0], sessionID: installationID }] },
    { ...record, telemetry: [{ ...record.telemetry[0], heartRate: { value: 301, date: record.date } }] },
    { ...record, telemetry: [{ ...record.telemetry[0], accelerationG: { value: Number.POSITIVE_INFINITY, date: record.date } }] },
    { ...record, loggedSets: [{ id: installationID, exerciseID: 'plank', reps: 10, seconds: 0, source: 'manual', reason: 'target' }] }
  ];
  for (const candidate of invalid) await assert.rejects(store.ingest({ installationID, record: candidate }), error => error.status === 422);
  assert.equal(connections, 0);
});

test('authenticated workout HTTP ingestion and readback are independent of Gemini configuration', async t => {
  const db = database();
  const server = createGateway({ env: { SPOTTR_GATEWAY_TOKEN: 'owner-token', SPOTTR_INSTALLATION_ID: installationID, TIGER_DATABASE_URL: 'postgresql://unused.example/test' }, pool: db.pool });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(() => new Promise(resolve => server.close(resolve)));
  const origin = `http://127.0.0.1:${server.address().port}`;
  const send = body => fetch(`${origin}/v1/workouts`, { method: 'POST', headers: { authorization: 'Bearer owner-token', 'content-type': 'application/json' }, body: JSON.stringify(body) });
  const first = await send({ installationID, record });
  assert.equal(first.status, 201);
  assert.equal((await first.json()).replayed, false);
  assert.equal((await send({ installationID, record })).status, 200);
  assert.equal((await send({ installationID: workoutID, record })).status, 403);
  const restored = await fetch(`${origin}/v1/workouts/${workoutID}`, { headers: { authorization: 'Bearer owner-token' } });
  assert.equal(restored.status, 200);
  assert.deepEqual((await restored.json()).record, record);
  const telemetry = await fetch(`${origin}/v1/workouts/${workoutID}/telemetry?from=2026-10-24T10:00:59Z&to=2026-10-24T10:01:00Z`, { headers: { authorization: 'Bearer owner-token' } });
  assert.equal(telemetry.status, 200);
  assert.equal((await telemetry.json()).samples.length, 1);
  assert.equal((await fetch(`${origin}/v1/workouts/${workoutID}`)).status, 401);
});

test('Tiger telemetry query returns observed scalar timestamps and rejects unbounded intervals', async () => {
  const db = database();
  const store = createTigerStore({ pool: db.pool, installationID });
  await store.ingest({ installationID, record });
  const result = await store.telemetry({ workoutID, from: '2026-10-24T10:00:59Z', to: '2026-10-24T10:01:00Z' });
  assert.deepEqual(result.samples.map(sample => [sample.kind, sample.value]), [['heartRate', 110]]);
  assert.equal(result.samples[0].measuredAt, record.telemetry[0].heartRate.date);
  await assert.rejects(store.telemetry({ workoutID, from: record.date, to: '2026-10-26T10:00:00Z' }), error => error.status === 422);
});

test('migration command refuses absent configuration before connecting', () => {
  const result = spawnSync(process.execPath, ['src/migrate.mjs'], { cwd: new URL('../', import.meta.url), env: { PATH: process.env.PATH }, encoding: 'utf8' });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /TIGER_DATABASE_URL must be configured/);
});

test('database failures roll back the full session and never expose driver errors over HTTP', async t => {
  const operations = [];
  const client = {
    async query(text) {
      operations.push(text);
      if (text.includes('INSERT INTO spottr_gateway.workout')) return { rows: [{ workout_id: workoutID }] };
      if (text.includes('INSERT INTO spottr_gateway.scalar_sample')) throw Error('postgres://private-password@secret-host');
      return { rows: [] };
    }, release() { operations.push('release'); }
  };
  const server = createGateway({ env: { SPOTTR_GATEWAY_TOKEN: 'owner-token', SPOTTR_INSTALLATION_ID: installationID, TIGER_DATABASE_URL: 'postgresql://unused.example/test' }, pool: { connect: async () => client } });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(() => new Promise(resolve => server.close(resolve)));
  const response = await fetch(`http://127.0.0.1:${server.address().port}/v1/workouts`, { method: 'POST', headers: { authorization: 'Bearer owner-token', 'content-type': 'application/json' }, body: JSON.stringify({ installationID, record }) });
  assert.equal(response.status, 503);
  assert.deepEqual(await response.json(), { error: { code: 'database_unavailable', message: 'The workout database is unavailable.' } });
  assert.deepEqual(operations.slice(-2), ['ROLLBACK', 'release']);
  assert.equal(operations.includes('COMMIT'), false);
});

test('failed rollback discards the broken PostgreSQL connection', async () => {
  let releasedError;
  const client = {
    async query(text) {
      if (text === 'BEGIN') return { rows: [] };
      throw Error('connection interrupted');
    }, release(error) { releasedError = error; }
  };
  const store = createTigerStore({ installationID, pool: { connect: async () => client } });
  await assert.rejects(store.ingest({ installationID, record }));
  assert.ok(releasedError instanceof Error);
});

test('retained Watch readings are inserted once per sensor kind and observation time', async () => {
  const db = database();
  const store = createTigerStore({ pool: db.pool, installationID });
  const sharedTime = '2026-10-24T10:00:59Z';
  const first = {
    ...record.telemetry[0], heartRate: { value: 110, date: sharedTime },
    accelerationG: { value: 1.1, date: sharedTime }, rotationRadiansPerSecond: { value: 0.4, date: sharedTime }
  };
  const repeated = {
    ...first, sentAt: '2026-10-24T10:01:01Z', heartRate: { value: 110, date: '2026-10-24T10:00:59.000Z' },
    accelerationG: { value: 1.1, date: '2026-10-24T10:00:59+00:00' }, rotationRadiansPerSecond: { value: 0.4, date: '2026-10-24T10:00:59.0000Z' }
  };
  const fresh = { sessionID: workoutID, sentAt: '2026-10-24T10:01:02Z', heartRate: { value: 110, date: '2026-10-24T10:01:01Z' } };
  const snapshot = { ...record, telemetry: [first, repeated, fresh] };
  await store.ingest({ installationID, record: snapshot });
  assert.deepEqual(db.samples.map(sample => [sample.kind, sample.value, sample.measured_at]), [
    ['heartRate', 110, sharedTime], ['accelerationMagnitude', 1.1, sharedTime], ['rotationMagnitude', 0.4, sharedTime],
    ['heartRate', 110, fresh.heartRate.date]
  ]);
  assert.equal(db.samples[0].sent_at, first.sentAt);
  assert.deepEqual((await store.read(workoutID)).record, snapshot);
});


test('Tiger preserves actual rest intervals while accepting legacy sets without them', async () => {
  const set = { id: '3d861a67-a632-4dca-a64a-4b7c75137d67', exercise: 'squat', number: 1, reps: 1, target: 12, activeSeconds: 8, source: 'camera', reason: 'voluntary', repDurations: [2.5], restSecondsBefore: 47.25 };
  const db = database();
  const store = createTigerStore({ pool: db.pool, installationID });
  await store.ingest({ installationID, record: { ...record, sets: [set] } });
  assert.equal((await store.read(workoutID)).record.sets[0].restSecondsBefore, 47.25);
  const legacy = { ...set }; delete legacy.restSecondsBefore;
  const second = createTigerStore({ pool: database().pool, installationID });
  await second.ingest({ installationID, record: { ...record, sets: [legacy] } });
  await assert.rejects(createTigerStore({ pool: database().pool, installationID }).ingest({ installationID, record: { ...record, sets: [{ ...set, restSecondsBefore: -1 }] } }), error => error.status === 422);
});

test('Tiger round-trips ordered manual plan metadata and a 730-second observed hold without changing legacy records', async () => {
  const loggedSets = [
    { id: 'f17e0000-0000-4000-8000-000000000011', exerciseID: 'squat', reps: 8, seconds: 0, source: 'manual', reason: 'target', number: 1, target: 12, activeSeconds: 17.5, restSecondsBefore: 47.25, reserve: 3, quantityOrigin: 'selfReport' },
    { id: 'f17e0000-0000-4000-8000-000000000012', exerciseID: 'plank', reps: 0, seconds: 730, source: 'manual', reason: 'voluntary', number: 2, target: 20, activeSeconds: 730, restSecondsBefore: 0, reserve: null, quantityOrigin: 'activeTimer' },
    { id: 'f17e0000-0000-4000-8000-000000000013', exerciseID: 'plank', reps: 0, seconds: 30, source: 'manual', reason: 'voluntary' },
    { id: 'f17e0000-0000-4000-8000-000000000014', exerciseID: 'squat', reps: 4, seconds: 0, source: 'camera', reason: 'voluntary', number: null, target: null, activeSeconds: null, restSecondsBefore: null, reserve: null, quantityOrigin: null }
  ];
  const snapshot = { ...record, loggedSets };
  const store = createTigerStore({ pool: database().pool, installationID });
  await store.ingest({ installationID, record: snapshot });
  const restored = (await store.read(workoutID)).record;
  assert.deepEqual(restored, snapshot);
  assert.equal(restored.loggedSets[1].seconds, 730);
  assert.equal(restored.loggedSets[1].target, 20);
  assert.equal(Object.hasOwn(restored.loggedSets[2], 'activeSeconds'), false);
  assert.equal((await store.ingest({ installationID, record: snapshot })).replayed, true);
});

test('Tiger rejects invalid manual origins, timer claims, quantities and metadata before database access', async () => {
  const hold = { id: 'f17e0000-0000-4000-8000-000000000015', exerciseID: 'plank', reps: 0, seconds: 730, source: 'manual', reason: 'voluntary', number: 1, target: 20, activeSeconds: 730, quantityOrigin: 'activeTimer' };
  const reps = { ...hold, exerciseID: 'squat', reps: 8, seconds: 0, target: 12, activeSeconds: 17.5, quantityOrigin: 'selfReport' };
  const invalid = [
    { ...hold, quantityOrigin: 'invented' }, { ...hold, source: 'camera' },
    { ...reps, source: 'camera' }, { ...reps, quantityOrigin: 'activeTimer' },
    { ...hold, activeSeconds: undefined }, { ...hold, activeSeconds: null }, { ...hold, activeSeconds: 729.9 },
    { ...hold, reps: 1 }, { ...reps, seconds: 1 }, { ...hold, reserve: 0 },
    { ...hold, quantityOrigin: 'selfReport' }, { ...hold, quantityOrigin: undefined }, { ...hold, quantityOrigin: null },
    { ...hold, seconds: 86400.1, activeSeconds: 86400.1 },
    { ...reps, number: 0 }, { ...reps, number: 11 }, { ...reps, number: 1.5 },
    { ...reps, target: 0 }, { ...reps, target: 201 }, { ...hold, target: 601 }, { ...hold, target: 1.5 },
    { ...reps, reserve: -1 }, { ...reps, reserve: 4 }, { ...reps, reserve: 1.5 },
    { ...reps, activeSeconds: -1 }, { ...reps, activeSeconds: 86400.1 }, { ...reps, activeSeconds: Infinity },
    { ...reps, restSecondsBefore: -1 }, { ...reps, restSecondsBefore: Infinity },
    { ...hold, seconds: NaN, activeSeconds: NaN }, { ...reps, extra: 'unknown' }
  ];
  let connections = 0;
  const store = createTigerStore({ installationID, pool: { connect: async () => { connections += 1; throw Error('must not connect'); } } });
  for (const set of invalid) await assert.rejects(store.ingest({ installationID, record: { ...record, loggedSets: [set] } }), error => error.status === 422);
  assert.equal(connections, 0);
});

test('Tiger accepts explicit metadata bounds while keeping self-reported holds at 600 seconds', async () => {
  const loggedSets = [
    { id: 'f17e0000-0000-4000-8000-000000000016', exerciseID: 'plank', reps: 0, seconds: 86400, source: 'manual', reason: 'voluntary', number: 10, target: 600, activeSeconds: 86400, quantityOrigin: 'activeTimer' },
    { id: 'f17e0000-0000-4000-8000-000000000017', exerciseID: 'plank', reps: 0, seconds: 600, source: 'manual', reason: 'target', target: 600, quantityOrigin: 'selfReport' },
    { id: 'f17e0000-0000-4000-8000-000000000018', exerciseID: 'squat', reps: 200, seconds: 0, source: 'manual', reason: 'target', number: 10, target: 200, activeSeconds: 0, restSecondsBefore: 86401, reserve: 0, quantityOrigin: 'selfReport' }
  ];
  const store = createTigerStore({ pool: database().pool, installationID });
  await store.ingest({ installationID, record: { ...record, loggedSets } });
  const restored = (await store.read(workoutID)).record.loggedSets;
  assert.deepEqual(restored, loggedSets);
  assert.equal(Object.hasOwn(restored[1], 'activeSeconds'), false);
});

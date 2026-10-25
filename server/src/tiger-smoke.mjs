import assert from 'node:assert/strict';
import { Pool } from 'pg';
import { createTigerStore } from './tiger.mjs';

export const TIGER_SMOKE_IDS = Object.freeze({
  installationID: 'f17e0000-0000-4000-8000-000000000001',
  workoutID: 'f17e0000-0000-4000-8000-000000000002',
  setID: 'f17e0000-0000-4000-8000-000000000003'
});

class SmokeError extends Error {
  constructor(code) { super(code); this.code = code; }
}

function requireCheck(condition, code) {
  if (!condition) throw new SmokeError(code);
}

function fixtureRecord() {
  const sessionID = TIGER_SMOKE_IDS.workoutID;
  const heartRate = { value: 1, date: '2000-01-01T00:00:00Z' };
  return {
    id: sessionID, date: '2000-01-01T00:00:00Z', sets: [],
    loggedSets: [{ id: TIGER_SMOKE_IDS.setID, exerciseID: 'squat', reps: 1, seconds: 0, source: 'manual', reason: 'voluntary' }],
    telemetry: [
      { sessionID, sentAt: '2000-01-01T00:00:02Z', heartRate, accelerationG: { value: 0, date: '2000-01-01T00:00:01Z' }, rotationRadiansPerSecond: { value: 0, date: '2000-01-01T00:00:01Z' } },
      { sessionID, sentAt: '2000-01-01T00:00:03Z', heartRate, accelerationG: { value: 0, date: '2000-01-01T00:00:02Z' } },
      { sessionID, sentAt: '2000-01-01T00:00:04Z' }
    ]
  };
}

async function measure(action) {
  const started = performance.now();
  const value = await action();
  return { value, ms: performance.now() - started };
}

function rollupValues(result) {
  return result.buckets.map(row => [new Date(row.bucket).toISOString(), row.kind, row.observedSamples, row.mean, row.min, row.max,
    new Date(row.firstMeasuredAt).toISOString(), new Date(row.lastMeasuredAt).toISOString(), row.unit, row.source]);
}

async function verifyDatabase(pool) {
  const result = await pool.query(`SELECT current_setting('server_version_num')::integer AS postgres_version_num,
    (SELECT extversion FROM pg_extension WHERE extname = 'timescaledb') AS timescale_version,
    (SELECT ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid()) AS tls`);
  const details = result.rows[0];
  requireCheck(details?.postgres_version_num >= 140000, 'postgres_version_unsupported');
  const version = /^(\d+)\.(\d+)/.exec(details.timescale_version ?? '');
  requireCheck(version && (Number(version[1]) > 2 || Number(version[1]) === 2 && Number(version[2]) >= 18), 'timescale_version_unsupported');
  requireCheck(details.tls === true, 'tls_required');
  const schema = await pool.query("SELECT count(*)::integer AS hypertables FROM timescaledb_information.hypertables WHERE hypertable_schema = 'spottr_gateway' AND hypertable_name = 'scalar_sample'");
  requireCheck(schema.rows[0]?.hypertables === 1, 'hypertable_missing');
}

export async function runTigerSmoke({ pool }) {
  const environment = await measure(() => verifyDatabase(pool));
  const record = fixtureRecord();
  const { installationID, workoutID } = TIGER_SMOKE_IDS;
  const store = createTigerStore({ pool, installationID });
  const initial = await measure(() => store.ingest({ installationID, record }));
  const replay = await measure(() => store.ingest({ installationID, record }));
  assert.equal(replay.value.replayed, true);
  assert.equal(replay.value.sha256, initial.value.sha256);
  const conflict = await measure(() => assert.rejects(store.ingest({ installationID, record: { ...record, loggedSets: [{ ...record.loggedSets[0], reps: 2 }] } }), error => error.status === 409));
  const readback = await measure(() => store.read(workoutID));
  assert.equal(readback.value.installationID, installationID);
  assert.equal(readback.value.sha256, initial.value.sha256);
  assert.deepEqual(readback.value.record, record);
  const full = await measure(() => store.telemetry({ workoutID, from: record.date, to: '2000-01-01T00:00:03Z' }));
  assert.deepEqual(full.value.samples.map(sample => [sample.kind, new Date(sample.measuredAt).toISOString(), sample.value, sample.unit, sample.source]), [
    ['heartRate', '2000-01-01T00:00:00.000Z', 1, 'bpm', 'apple_watch'],
    ['accelerationMagnitude', '2000-01-01T00:00:01.000Z', 0, 'g', 'apple_watch'],
    ['rotationMagnitude', '2000-01-01T00:00:01.000Z', 0, 'rad/s', 'apple_watch'],
    ['accelerationMagnitude', '2000-01-01T00:00:02.000Z', 0, 'g', 'apple_watch']
  ]);
  const window = await measure(() => store.telemetry({ workoutID, from: '2000-01-01T00:00:01Z', to: '2000-01-01T00:00:02Z' }));
  assert.deepEqual(window.value.samples.map(sample => sample.kind), ['accelerationMagnitude', 'rotationMagnitude']);
  const gap = await measure(() => store.telemetry({ workoutID, from: '2000-01-01T00:00:02.500Z', to: '2000-01-01T00:00:03Z' }));
  assert.equal(gap.value.samples.length, 0);
  const rollup5s = await measure(() => store.rollups({ workoutID, from: record.date, to: '2000-01-01T00:00:03Z', bucketSeconds: 5 }));
  assert.deepEqual(rollupValues(rollup5s.value), [
    ['2000-01-01T00:00:00.000Z', 'accelerationMagnitude', 2, 0, 0, 0, '2000-01-01T00:00:01.000Z', '2000-01-01T00:00:02.000Z', 'g', 'apple_watch'],
    ['2000-01-01T00:00:00.000Z', 'heartRate', 1, 1, 1, 1, '2000-01-01T00:00:00.000Z', '2000-01-01T00:00:00.000Z', 'bpm', 'apple_watch'],
    ['2000-01-01T00:00:00.000Z', 'rotationMagnitude', 1, 0, 0, 0, '2000-01-01T00:00:01.000Z', '2000-01-01T00:00:01.000Z', 'rad/s', 'apple_watch']
  ]);
  const rollup60s = await measure(() => store.rollups({ workoutID, from: record.date, to: '2000-01-01T00:00:03Z', bucketSeconds: 60 }));
  assert.deepEqual(rollupValues(rollup60s.value), rollupValues(rollup5s.value));
  const rollupWindow = await measure(() => store.rollups({ workoutID, from: '2000-01-01T00:00:01Z', to: '2000-01-01T00:00:02Z', bucketSeconds: 5 }));
  assert.deepEqual(rollupValues(rollupWindow.value), [
    ['2000-01-01T00:00:00.000Z', 'accelerationMagnitude', 1, 0, 0, 0, '2000-01-01T00:00:01.000Z', '2000-01-01T00:00:01.000Z', 'g', 'apple_watch'],
    ['2000-01-01T00:00:00.000Z', 'rotationMagnitude', 1, 0, 0, 0, '2000-01-01T00:00:01.000Z', '2000-01-01T00:00:01.000Z', 'rad/s', 'apple_watch']
  ]);
  const rollupGap = await measure(() => store.rollups({ workoutID, from: '2000-01-01T00:00:02.500Z', to: '2000-01-01T00:00:03Z', bucketSeconds: 5 }));
  assert.deepEqual(rollupGap.value.buckets, []);
  return {
    fixtureIDs: TIGER_SMOKE_IDS,
    counts: { environmentChecks: 4, created: initial.value.replayed ? 0 : 1, replays: initial.value.replayed ? 2 : 1, conflicts: 1, readbacks: 1, scalarRows: full.value.samples.length, windowRows: window.value.samples.length, gapRows: gap.value.samples.length,
      rollupRows5s: rollup5s.value.buckets.length, rollupRows60s: rollup60s.value.buckets.length, rollupWindowRows: rollupWindow.value.buckets.length, rollupGapRows: rollupGap.value.buckets.length },
    timingsMs: { environment: environment.ms, ingest: initial.ms, replay: replay.ms, conflict: conflict.ms, readback: readback.ms, fullWindow: full.ms, halfOpenWindow: window.ms, gapWindow: gap.ms,
      rollup5s: rollup5s.ms, rollup60s: rollup60s.ms, rollupWindow: rollupWindow.ms, rollupGap: rollupGap.ms }
  };
}

export async function tigerSmokeCommand({ args = process.argv.slice(2), env = process.env, createPool = config => new Pool(config) } = {}) {
  if (args.length !== 1 || args[0] !== '--allow-live-synthetic') return { exitCode: 1, error: { code: 'explicit_opt_in_required' } };
  if (!env.TIGER_DATABASE_URL) return { exitCode: 1, error: { code: 'missing_configuration' } };
  if (env.SPOTTR_INSTALLATION_ID?.toLowerCase() === TIGER_SMOKE_IDS.installationID) return { exitCode: 1, error: { code: 'fixture_scope_collision' } };
  let pool;
  try {
    let url;
    try { url = new URL(env.TIGER_DATABASE_URL); } catch { throw new SmokeError('strict_tls_required'); }
    requireCheck(['postgres:', 'postgresql:'].includes(url.protocol) && Boolean(url.hostname)
      && url.searchParams.getAll('sslmode').length === 1 && url.searchParams.get('sslmode') === 'verify-full'
      && !url.searchParams.has('ssl') && env.NODE_TLS_REJECT_UNAUTHORIZED !== '0'
      && process.env.NODE_TLS_REJECT_UNAUTHORIZED !== '0', 'strict_tls_required');
    pool = createPool({ connectionString: env.TIGER_DATABASE_URL, max: 1, connectionTimeoutMillis: 5000, statement_timeout: 10000, query_timeout: 12000 });
    pool.on?.('error', () => {});
    return { exitCode: 0, ...await runTigerSmoke({ pool }) };
  } catch (error) {
    return { exitCode: 1, error: { code: error instanceof SmokeError ? error.code : 'database_smoke_failed' } };
  } finally { if (pool) await pool.end().catch(() => {}); }
}

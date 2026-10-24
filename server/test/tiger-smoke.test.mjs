import assert from 'node:assert/strict';
import test from 'node:test';
import { runTigerSmoke, tigerSmokeCommand, TIGER_SMOKE_IDS } from '../src/tiger-smoke.mjs';
import { spawnSync } from 'node:child_process';

function database({ tls = true, timescaleVersion = '2.18.0', postgresVersion = 170000, hypertables = 1 } = {}) {
  const snapshots = new Map();
  const samples = [];
  const statements = [];
  let ended = 0;
  const query = async (sql, values = []) => {
    statements.push({ sql, values });
    if (sql.includes("current_setting('server_version_num')")) return { rows: [{ postgres_version_num: postgresVersion, timescale_version: timescaleVersion, tls }] };
    if (sql.includes('timescaledb_information.hypertables')) return { rows: [{ hypertables }] };
    const key = `${values[0]}:${values[1]}`;
    if (sql.startsWith('INSERT INTO spottr_gateway.workout')) {
      if (snapshots.has(key)) return { rows: [] };
      snapshots.set(key, { record: JSON.parse(values[3]), payload_sha256: values[2] });
      return { rows: [{ workout_id: values[1] }] };
    }
    if (sql.includes('INSERT INTO spottr_gateway.scalar_sample')) {
      samples.push(...JSON.parse(values[0]).map(sample => ({ ...sample, installationID: values[1], workoutID: values[2] })));
      return { rows: [] };
    }
    if (sql.includes('FROM spottr_gateway.workout')) return { rows: snapshots.has(key) ? [snapshots.get(key)] : [] };
    if (sql.includes('FROM spottr_gateway.scalar_sample')) return { rows: samples.filter(sample => sample.installationID === values[0] && sample.workoutID === values[1] && Date.parse(sample.measured_at) >= Date.parse(values[2]) && Date.parse(sample.measured_at) < Date.parse(values[3])).map(sample => ({ measuredAt: new Date(sample.measured_at), sentAt: new Date(sample.sent_at), kind: sample.kind, value: sample.value, unit: sample.unit, source: sample.source })) };
    if (['BEGIN', 'COMMIT', 'ROLLBACK'].includes(sql)) return { rows: [] };
    throw Error('Unexpected smoke SQL');
  };
  return { pool: { query, connect: async () => ({ query, release() {} }), on() {}, async end() { ended += 1; } }, samples, statements, ended: () => ended };
}

test('Tiger smoke exercises immutable fixtures, scoped readback and observed half-open windows repeatably', async () => {
  const db = database();
  const first = await runTigerSmoke({ pool: db.pool });
  assert.deepEqual(first.fixtureIDs, TIGER_SMOKE_IDS);
  assert.deepEqual(first.counts, { environmentChecks: 4, created: 1, replays: 1, conflicts: 1, readbacks: 1, scalarRows: 4, windowRows: 2, gapRows: 0 });
  assert.ok(Object.values(first.timingsMs).every(value => typeof value === 'number' && value >= 0));
  assert.equal(db.samples.every(sample => sample.installationID === TIGER_SMOKE_IDS.installationID), true);
  assert.equal(db.samples.every(sample => sample.measured_at.startsWith('2000-01-01')), true);
  const repeated = await runTigerSmoke({ pool: db.pool });
  assert.equal(repeated.counts.created, 0);
  assert.equal(repeated.counts.replays, 2);
  assert.equal(db.samples.length, 4);
  assert.equal(db.statements.some(({ sql }) => /\b(CREATE|ALTER|DROP|DELETE|TRUNCATE)\b/i.test(sql)), false);
});

test('Tiger smoke refuses unverified TLS, unsupported versions or an absent hypertable before writes', async () => {
  for (const [config, code] of [[{ tls: false }, 'tls_required'], [{ timescaleVersion: '2.17.2' }, 'timescale_version_unsupported'], [{ postgresVersion: 130000 }, 'postgres_version_unsupported'], [{ hypertables: 0 }, 'hypertable_missing']]) {
    const db = database(config);
    await assert.rejects(runTigerSmoke({ pool: db.pool }), error => error.code === code);
    assert.equal(db.statements.some(({ sql }) => sql.startsWith('INSERT')), false);
  }
});

test('smoke command requires explicit opt-in and configuration before constructing a pool', async () => {
  let pools = 0;
  const createPool = () => { pools += 1; throw Error('must not connect'); };
  const missingOptIn = await tigerSmokeCommand({ args: [], env: { TIGER_DATABASE_URL: 'postgresql://private-password@secret-host/db' }, createPool });
  assert.deepEqual(missingOptIn, { exitCode: 1, error: { code: 'explicit_opt_in_required' } });
  const missingConfig = await tigerSmokeCommand({ args: ['--allow-live-synthetic'], env: {}, createPool });
  assert.deepEqual(missingConfig, { exitCode: 1, error: { code: 'missing_configuration' } });
  assert.equal(pools, 0);
  const collidingScope = await tigerSmokeCommand({ args: ['--allow-live-synthetic'], env: { TIGER_DATABASE_URL: 'unused-private-url', SPOTTR_INSTALLATION_ID: TIGER_SMOKE_IDS.installationID }, createPool });
  assert.deepEqual(collidingScope, { exitCode: 1, error: { code: 'fixture_scope_collision' } });
  assert.equal(pools, 0);
});

test('smoke command keeps fixture scope separate from the app and sanitizes driver failures', async () => {
  const db = database();
  const result = await tigerSmokeCommand({ args: ['--allow-live-synthetic'], env: { TIGER_DATABASE_URL: 'postgresql://private-password@secret-host/db', SPOTTR_INSTALLATION_ID: 'f17e0000-0000-4000-8000-000000000999' }, createPool: config => {
    assert.equal(config.ssl, undefined);
    return db.pool;
  } });
  assert.equal(result.exitCode, 0);
  assert.equal(result.fixtureIDs.installationID, TIGER_SMOKE_IDS.installationID);
  assert.equal(db.ended(), 1);
  assert.equal(/private-password|secret-host|postgresql/.test(JSON.stringify(result)), false);
  const failure = await tigerSmokeCommand({ args: ['--allow-live-synthetic'], env: { TIGER_DATABASE_URL: 'private-connection' }, createPool: () => ({ on() {}, query: async () => { throw Error('private-password secret-host SELECT hidden'); }, end: async () => {} }) });
  assert.deepEqual(failure, { exitCode: 1, error: { code: 'database_smoke_failed' } });
});

test('executable smoke refuses implicit live access and prints only its sanitized error code', () => {
  const result = spawnSync(process.execPath, ['src/tiger-smoke-cli.mjs'], { cwd: new URL('../', import.meta.url), env: { PATH: process.env.PATH, TIGER_DATABASE_URL: 'postgresql://private-password@secret-host/db' }, encoding: 'utf8' });
  assert.equal(result.status, 1);
  assert.equal(result.stdout, '');
  assert.deepEqual(JSON.parse(result.stderr), { error: { code: 'explicit_opt_in_required' } });
});

import assert from 'node:assert/strict';
import test from 'node:test';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readFile, mkdtemp, mkdir, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { loadPublicBenchmark, parsePredictionCSV } from '../src/snowflake-benchmark.mjs';
import { runSnowflakeBenchmark, BENCHMARK_SQL } from '../src/snowflake-benchmark-client.mjs';

const artifactRoot = new URL('../../research/hr_forecast/', import.meta.url);
const manifestPath = new URL('../../integrations/snowflake/pamap2-forecast-v1.manifest.json', import.meta.url);
const env = { SNOWFLAKE_ACCOUNT: 'organization-account', SNOWFLAKE_TOKEN: 'private-token', SNOWFLAKE_WAREHOUSE: 'EXISTING_WH', SNOWFLAKE_DATABASE: 'EXISTING_DB', SNOWFLAKE_SCHEMA: 'PUBLIC_EVALUATION' };
const handle = '01a8e001-0000-0010-0000-000000000001';
const hash = data => createHash('sha256').update(data).digest('hex');
const ready = data => Response.json({ data });
const metricsReply = plan => ready([[JSON.stringify(plan.metrics)]]);

async function fixture(t, change) {
  const root = await mkdtemp(join(tmpdir(), 'spottr-public-benchmark-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  const manifest = JSON.parse(await readFile(manifestPath, 'utf8'));
  for (const name of Object.keys(manifest.files)) {
    const path = join(root, name);
    await mkdir(join(path, '..'), { recursive: true });
    const original = await readFile(new URL(name, artifactRoot));
    const updated = change(name, original);
    await writeFile(path, updated);
    manifest.files[name] = hash(updated);
  }
  return { root, manifest };
}

test('Snowflake benchmark CLI defaults to a useful dry run without configuration or network', () => {
  const result = spawnSync(process.execPath, ['src/snowflake-benchmark-cli.mjs'], { cwd: new URL('../', import.meta.url), env: { PATH: process.env.PATH }, encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
  const plan = JSON.parse(result.stdout);
  assert.equal(plan.mode, 'dry-run');
  assert.equal(plan.sourceRows, 1622);
  assert.equal(plan.metrics.length, 18);
  assert.match(plan.runID, /^[a-f0-9]{64}$/);
  assert.equal(result.stderr, '');
  const invalid = spawnSync(process.execPath, ['src/snowflake-benchmark-cli.mjs', '--sql', 'DROP TABLE x'], { cwd: new URL('../', import.meta.url), env: { PATH: process.env.PATH }, encoding: 'utf8' });
  assert.equal(invalid.status, 1);
  assert.match(invalid.stderr, /invalid_request/);
});

test('Snowflake configuration check lists exact missing or invalid names without loading artifacts, connecting or revealing values', () => {
  const run = config => spawnSync(process.execPath, ['src/snowflake-benchmark-cli.mjs', '--check-configuration'], {
    cwd: new URL('../', import.meta.url), env: { PATH: process.env.PATH, ...config }, encoding: 'utf8'
  });
  const missing = run({ SNOWFLAKE_ACCOUNT: env.SNOWFLAKE_ACCOUNT, SNOWFLAKE_WAREHOUSE: env.SNOWFLAKE_WAREHOUSE });
  assert.equal(missing.status, 1);
  assert.equal(missing.stderr, '');
  assert.deepEqual(JSON.parse(missing.stdout), { mode: 'configuration', ready: false, missing: ['SNOWFLAKE_TOKEN', 'SNOWFLAKE_DATABASE', 'SNOWFLAKE_SCHEMA'], invalid: [] });
  const ready = run(env);
  assert.equal(ready.status, 0, ready.stderr);
  assert.deepEqual(JSON.parse(ready.stdout), { mode: 'configuration', ready: true, missing: [], invalid: [] });
  const invalid = run({ ...env, SNOWFLAKE_TOKEN_TYPE: 'bad-private-type', SNOWFLAKE_SCHEMA: 'private schema name' });
  assert.equal(invalid.status, 1);
  assert.deepEqual(JSON.parse(invalid.stdout), { mode: 'configuration', ready: false, missing: [], invalid: ['SNOWFLAKE_TOKEN_TYPE', 'SNOWFLAKE_SCHEMA'] });
  const personalDatabase = run({ ...env, SNOWFLAKE_DATABASE: 'USER$OMAR' });
  assert.equal(personalDatabase.status, 1);
  assert.deepEqual(JSON.parse(personalDatabase.stdout), { mode: 'configuration', ready: false, missing: [], invalid: ['SNOWFLAKE_DATABASE'] });
  for (const result of [ready, missing, invalid]) assert.equal(/private-token|organization-account|EXISTING_WH|private schema name|bad-private-type/.test(result.stdout + result.stderr), false);
});

test('Snowflake benchmark uses an explicitly selected existing role and rejects malformed role context before requests', async () => {
  const plan = await loadPublicBenchmark();
  const roles = [];
  const result = await runSnowflakeBenchmark({ plan, allowLivePublicData: true, env: { ...env, SNOWFLAKE_ROLE: 'PUBLIC_DATA_IMPORTER' }, fetchImpl: async (_url, options) => {
    const body = JSON.parse(options.body);
    roles.push(body.role);
    return body.statement === BENCHMARK_SQL.lookup ? ready([['1', plan.payloadSha256]]) : metricsReply(plan);
  } });
  assert.equal(result.replayed, true);
  assert.deepEqual(roles, ['PUBLIC_DATA_IMPORTER', 'PUBLIC_DATA_IMPORTER']);
  let calls = 0;
  await assert.rejects(runSnowflakeBenchmark({ plan, allowLivePublicData: true, env: { ...env, SNOWFLAKE_ROLE: 'ROLE;DROP TABLE X' }, fetchImpl: async () => { calls++; } }), error => error.code === 'missing_configuration');
  assert.equal(calls, 0);
});

test('Pinned public artifact preserves original prediction text, immutable lineage and zero-coverage people', async () => {
  const plan = await loadPublicBenchmark();
  const again = await loadPublicBenchmark();
  assert.equal(plan.runID, again.runID);
  assert.equal(plan.payloadSha256, hash(plan.payloadJSON));
  assert.equal(plan.payload.predictions[0].frozen, '84.06743271901618');
  assert.equal(plan.payload.predictions.find(row => row.target === null).target, null);
  assert.equal(plan.payload.lineage.dataset, 'PAMAP2');
  assert.equal(plan.payload.lineage.license, 'CC BY 4.0');
  assert.ok(plan.payload.lineage.files['results/models.json']);
  const zero = plan.metrics.find(row => row.subject === 109 && row.horizon === 30 && row.model === 'frozen');
  assert.equal(zero.scored, 0);
  assert.equal(zero.planned, 17);
  assert.equal(zero.mae, null);
  const macro = plan.metrics.find(row => row.subject === null && row.horizon === 30 && row.model === 'frozen');
  assert.equal(macro.contributingParticipants, 1);
});

test('Changed hashes, malformed CSV and inconsistent coverage stop before any Snowflake access', async t => {
  const changed = await fixture(t, (name, bytes) => name.endsWith('test-predictions.csv') ? Buffer.from(bytes.toString().replace('84.06743271901618', '999')) : bytes);
  await assert.rejects(loadPublicBenchmark({ root: changed.root }), error => error.code === 'invalid_public_artifact');
  const malformed = await fixture(t, (name, bytes) => name.endsWith('test-predictions.csv') ? Buffer.from(bytes.toString().replace('84.06743271901618', 'NaN')) : bytes);
  await assert.rejects(loadPublicBenchmark(malformed), error => error.code === 'invalid_public_artifact');
  const coverage = await fixture(t, (name, bytes) => name.endsWith('coverage-summary.json') ? Buffer.from(bytes.toString().replace('"planned_origins": 816', '"planned_origins": 1')) : bytes);
  await assert.rejects(loadPublicBenchmark(coverage), error => error.code === 'invalid_public_artifact');
});

test('Fixed CSV contract rejects duplicates, quotes, extra columns, invalid alignment and excessive data', async () => {
  const csv = await readFile(new URL('results/test-predictions.csv', artifactRoot), 'utf8');
  const lines = csv.trim().split(/\r?\n/);
  const invalid = [
    `${lines[0]}\n${lines[1]}\n${lines[1]}\n`,
    csv.replace('84.06743271901618', '"84.06743271901618"'),
    csv.replace('cold_start', 'cold_start,extra'),
    csv.replace('108,65,10,70,75', '108,65,10,71,75'),
    'x'.repeat(1_048_577), `${lines[0]}\n${Array(10001).fill(lines[1]).join('\n')}`
  ];
  for (const text of invalid) assert.throws(() => parsePredictionCSV(text), error => error.code === 'invalid_public_artifact');
});

test('Live import uses only fixed statements and JSON bindings, then reconciles Snowflake evaluation', async () => {
  const plan = await loadPublicBenchmark();
  const calls = [];
  let reads = 0;
  const fetchImpl = async (url, options) => {
    const body = JSON.parse(options.body);
    calls.push(body);
    assert.equal(new URL(url).origin, 'https://organization-account.snowflakecomputing.com');
    assert.equal(options.headers.Authorization, 'Bearer private-token');
    assert.equal(options.redirect, 'error');
    assert.equal(body.timeout, 60);
    assert.equal(body.database, 'EXISTING_DB');
    assert.equal(body.schema, 'PUBLIC_EVALUATION');
    assert.ok(Object.values(BENCHMARK_SQL).includes(body.statement));
    assert.equal(body.bindings['1'].value, plan.runID);
    if (body.statement === BENCHMARK_SQL.lookup) return ready([[String(reads++), reads === 1 ? '' : plan.payloadSha256]]);
    if (body.statement === BENCHMARK_SQL.insert) {
      assert.equal(body.bindings['3'].value, plan.payloadJSON);
      assert.equal(body.bindings['2'].value, plan.payloadSha256);
      assert.ok(!body.statement.includes(plan.payload.predictions[0].frozen));
      assert.ok(!/UPDATE|DELETE|CREATE|DROP/i.test(body.statement));
      return ready([['1']]);
    }
    return metricsReply(plan);
  };
  const result = await runSnowflakeBenchmark({ plan, allowLivePublicData: true, env, fetchImpl });
  assert.equal(result.mode, 'live');
  assert.equal(result.replayed, false);
  assert.deepEqual(result.metrics, plan.metrics);
  assert.equal(calls.length, 4);
});

test('Identical replay skips writes; conflicting hashes or duplicate run IDs never overwrite', async () => {
  const plan = await loadPublicBenchmark();
  const statements = [];
  const replay = await runSnowflakeBenchmark({ plan, allowLivePublicData: true, env, fetchImpl: async (_url, options) => {
    const body = JSON.parse(options.body); statements.push(body.statement);
    return body.statement === BENCHMARK_SQL.lookup ? ready([['1', plan.payloadSha256]]) : metricsReply(plan);
  } });
  assert.equal(replay.replayed, true);
  assert.deepEqual(statements, [BENCHMARK_SQL.lookup, BENCHMARK_SQL.evaluate]);
  for (const data of [[['1', '0'.repeat(64)]], [['2', plan.payloadSha256]]]) {
    let calls = 0;
    await assert.rejects(runSnowflakeBenchmark({ plan, allowLivePublicData: true, env, fetchImpl: async () => { calls++; return ready(data); } }), error => error.code === 'immutable_run_conflict');
    assert.equal(calls, 1);
  }
});

test('No live opt-in means no environment access or transport, and invalid live configuration never connects', async () => {
  const plan = await loadPublicBenchmark();
  let calls = 0;
  const fetchImpl = async () => { calls++; throw Error('must not connect private-token'); };
  const forbiddenEnv = new Proxy({}, { get() { throw Error('must not inspect credentials'); } });
  assert.equal((await runSnowflakeBenchmark({ plan, env: forbiddenEnv, fetchImpl })).mode, 'dry-run');
  assert.equal((await runSnowflakeBenchmark({ plan, allowLivePublicData: 'false', env: forbiddenEnv, fetchImpl })).mode, 'dry-run');
  for (const configuration of [{}, { ...env, SNOWFLAKE_SCHEMA: 'PUBLIC;DROP TABLE X' }, { ...env, SNOWFLAKE_DATABASE: 'USER$OMAR' }]) {
    await assert.rejects(runSnowflakeBenchmark({ plan, allowLivePublicData: true, env: configuration, fetchImpl }), error => error.code === 'missing_configuration');
  }
  assert.equal(calls, 0);
});

test('Asynchronous successful statements poll their own handles without resubmitting SQL', async () => {
  const plan = await loadPublicBenchmark();
  const calls = [];
  let stage = 0;
  const result = await runSnowflakeBenchmark({ plan, allowLivePublicData: true, env, waitImpl: async () => {}, fetchImpl: async (url, options) => {
    calls.push([new URL(url).pathname, options.method]);
    stage++;
    if (options.method === 'POST') return Response.json({ statementHandle: handle }, { status: 202 });
    return stage === 2 ? ready([['1', plan.payloadSha256]]) : metricsReply(plan);
  } });
  assert.equal(result.replayed, true);
  assert.deepEqual(calls.map(call => call[1]), ['POST', 'GET', 'POST', 'GET']);
  assert.ok(calls.filter(call => call[1] === 'GET').every(call => call[0].endsWith(handle)));
});

test('Total deadline cancels known work and cancellation failures are explicit and sanitized', async () => {
  const plan = await loadPublicBenchmark();
  let clock = 0;
  const calls = [];
  await assert.rejects(runSnowflakeBenchmark({ plan, allowLivePublicData: true, env, now: () => clock, fetchImpl: async (url, options) => {
    calls.push(options.method);
    if (url.includes('/cancel')) return ready([]);
    clock = 85000;
    return Response.json({ statementHandle: handle }, { status: 202 });
  } }), error => error.code === 'provider_timeout');
  assert.deepEqual(calls, ['POST', 'POST']);
  await assert.rejects(runSnowflakeBenchmark({ plan, allowLivePublicData: true, env, maxPolls: 1, waitImpl: async () => {}, fetchImpl: async url => {
    if (url.includes('/cancel')) return new Response('private-token account details', { status: 500 });
    return Response.json({ statementHandle: handle }, { status: 202 });
  } }), error => error.code === 'cancel_unconfirmed' && !/private|account|details/.test(error.message));
});

test('Async polling is bounded and cancels a known statement once before reporting timeout', async () => {
  const plan = await loadPublicBenchmark();
  const methods = [];
  await assert.rejects(runSnowflakeBenchmark({ plan, allowLivePublicData: true, env, maxPolls: 2, pollMs: 1, waitImpl: async () => {}, fetchImpl: async (url, options) => {
    methods.push([new URL(url).pathname, options.method]);
    if (url.includes('/cancel')) return ready([]);
    return Response.json({ statementHandle: handle }, { status: 202 });
  } }), error => error.code === 'provider_timeout');
  assert.deepEqual(methods.map(call => call[1]), ['POST', 'GET', 'GET', 'POST']);
  assert.equal(methods.at(-1)[0], `/api/v2/statements/${handle}/cancel`);
});

test('Pending query failures attempt cancellation and never expose raw Snowflake/token errors', async () => {
  const plan = await loadPublicBenchmark();
  const calls = [];
  await assert.rejects(runSnowflakeBenchmark({ plan, allowLivePublicData: true, env, waitImpl: async () => {}, fetchImpl: async (url, options) => {
    calls.push(options.method);
    if (url.includes('/cancel')) return ready([]);
    if (options.method === 'POST') return Response.json({ statementHandle: handle }, { status: 202 });
    return new Response('private-token sensitive driver context', { status: 500 });
  } }), error => error.code === 'provider_unavailable' && !/private|sensitive|driver/.test(error.message));
  assert.deepEqual(calls, ['POST', 'GET', 'POST']);
});

test('Snowflake metric mismatch fails instead of reporting an unverified evaluation', async () => {
  const plan = await loadPublicBenchmark();
  let calls = 0;
  await assert.rejects(runSnowflakeBenchmark({ plan, allowLivePublicData: true, env, fetchImpl: async (_url, options) => {
    calls++;
    return JSON.parse(options.body).statement === BENCHMARK_SQL.lookup ? ready([['1', plan.payloadSha256]]) : ready([[JSON.stringify([])]]);
  } }), error => error.code === 'evaluation_mismatch');
  assert.equal(calls, 2);
});

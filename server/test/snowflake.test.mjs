import assert from 'node:assert/strict';
import test from 'node:test';
import { createSnowflakeAdapter } from '../src/snowflake.mjs';
import { spawnSync } from 'node:child_process';

const env = { SNOWFLAKE_ACCOUNT: 'organization-account', SNOWFLAKE_TOKEN: 'private-token', SNOWFLAKE_WAREHOUSE: 'COMPUTE_WH' };
const statementHandle = '01a8e001-0000-0010-0000-000000000001';

test('Snowflake connection check executes one fixed SQL API statement with server-only authorization', async () => {
  const adapter = createSnowflakeAdapter({ env, fetchImpl: async (url, options) => {
    const parsed = new URL(url);
    assert.equal(parsed.origin, 'https://organization-account.snowflakecomputing.com');
    assert.equal(parsed.pathname, '/api/v2/statements');
    assert.match(parsed.searchParams.get('requestId'), /^[a-f0-9-]{36}$/);
    assert.equal(options.headers.Authorization, 'Bearer private-token');
    assert.equal(options.redirect, 'error');
    assert.equal(options.headers['X-Snowflake-Authorization-Token-Type'], 'PROGRAMMATIC_ACCESS_TOKEN');
    assert.deepEqual(JSON.parse(options.body), { statement: 'SELECT CURRENT_VERSION()', timeout: 10, warehouse: 'COMPUTE_WH' });
    return Response.json({ data: [['9.30.0']], statementHandle });
  } });
  assert.deepEqual(await adapter.check(), { status: 'ready', version: '9.30.0' });
});

test('Snowflake handles asynchronous statements without automatic polling or reexecution', async () => {
  const calls = [];
  const adapter = createSnowflakeAdapter({ env, fetchImpl: async (url, options) => {
    calls.push([url, options.method]);
    return options.method === 'POST' ? Response.json({ statementHandle }, { status: 202 }) : Response.json({ data: [['9.30.0']] });
  } });
  assert.deepEqual(await adapter.check(), { status: 'pending', statementHandle });
  assert.equal(calls.length, 1);
  assert.deepEqual(await adapter.status(statementHandle), { status: 'ready', version: '9.30.0' });
  assert.equal(calls.length, 2);
  assert.equal(new URL(calls[1][0]).pathname, `/api/v2/statements/${statementHandle}`);
  assert.equal(calls[1][1], 'GET');
});

test('Snowflake rejects invalid account configuration and statement handles before network access', async () => {
  let calls = 0;
  const fetchImpl = async () => { calls += 1; return Response.json({ data: [['9.30.0']] }); };
  for (const config of [{}, { ...env, SNOWFLAKE_ACCOUNT: 'https://attacker.invalid/path' }, { ...env, SNOWFLAKE_TOKEN_TYPE: 'invalid' }]) {
    await assert.rejects(createSnowflakeAdapter({ env: config, fetchImpl }).check(), error => error.code === 'missing_configuration');
  }
  await assert.rejects(createSnowflakeAdapter({ env, fetchImpl }).status('../other-account'), error => error.status === 422);
  assert.equal(calls, 0);
});

test('Snowflake failures and malformed envelopes return sanitized errors with no automatic retries', async () => {
  for (const reply of [() => new Response('private-token driver details', { status: 401 }), () => new Response('throttled private-token', { status: 429 }), () => Response.json({ data: [] }), () => Response.json({ statementHandle: '../../private' }, { status: 202 }), () => new Response('x'.repeat(262145))]) {
    let calls = 0;
    const adapter = createSnowflakeAdapter({ env, fetchImpl: async () => { calls += 1; return reply(); } });
    await assert.rejects(adapter.check(), error => (error.status === 502 || error.status === 503) && !/private|driver|token/.test(error.message));
    assert.equal(calls, 1);
  }
});

test('Snowflake HTTP deadlines abort instead of polling or retrying', async () => {
  let calls = 0;
  const adapter = createSnowflakeAdapter({ env, timeoutMs: 10, fetchImpl: (_url, options) => {
    calls += 1;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => resolve(Response.json({ data: [['late']] })), 100);
      options.signal?.addEventListener('abort', () => { clearTimeout(timer); reject(options.signal.reason); }, { once: true });
    });
  } });
  await assert.rejects(adapter.check(), error => error.status === 504 && error.code === 'provider_timeout');
  assert.equal(calls, 1);
});

test('Snowflake CLI check reports missing configuration without credentials or network', () => {
  const result = spawnSync(process.execPath, ['src/snowflake-check.mjs'], { cwd: new URL('../', import.meta.url), env: { PATH: process.env.PATH }, encoding: 'utf8' });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /missing_configuration/);
  assert.equal(result.stdout, '');
});

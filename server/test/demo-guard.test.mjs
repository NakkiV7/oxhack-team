import assert from 'node:assert/strict';
import { once } from 'node:events';
import { connect } from 'node:net';
import test from 'node:test';
import { createGateway } from '../src/gateway.mjs';

const env = { SPOTTR_GATEWAY_TOKEN: 'owner-test-token', GEMINI_API_KEY: 'fake-key', GEMINI_MODEL: 'offline-model' };
const instant = Date.parse('2026-10-25T00:00:00.000Z');
const demoEnv = (attempts = 2, expires = instant + 60_000) => ({ ...env,
  SPOTTR_DEMO_MAX_ATTEMPTS: String(attempts), SPOTTR_DEMO_EXPIRES_AT: new Date(expires).toISOString() });
const input = { generationID: 'demo-generation', message: 'Synthetic question.', facts: [{ id: 'observation', text: 'No saved history.' }] };
const post = (data = input) => ({ method: 'POST', headers: { authorization: 'Bearer owner-test-token', 'content-type': 'application/json' }, body: JSON.stringify(data) });
const grounded = { text: 'No recorded history.', factIDs: ['observation'] };
function providerResponse(options) {
  const current = JSON.parse(JSON.parse(options.body).contents.at(-1).parts.at(-1).text);
  const output = current.task === '/v1/chat' ? 'Synthetic reply.' : current.task === '/v1/summary'
    ? { generationID: input.generationID, kind: 'session', headline: grounded, insights: [], focus: grounded }
    : { generationID: input.generationID, items: [{ exerciseID: 'squat', sets: 1, target: 2, unit: 'reps', restSeconds: 30, factIDs: ['observation'] }], rationale: grounded };
  return Response.json({ candidates: [{ finishReason: 'STOP', content: { parts: [{ text: typeof output === 'string' ? output : JSON.stringify(output) }] } }] });
}
async function serve(t, options) {
  const server = createGateway(options);
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(() => new Promise(resolve => { server.closeAllConnections(); server.close(resolve); }));
  const port = server.address().port;
  return { port, request: (path, init = post()) => fetch(`http://127.0.0.1:${port}${path}`, init) };
}

test('owner demo fails closed for partial, malformed, expired or excessive settings', () => {
  const valid = demoEnv();
  const invalid = [
    { ...env, SPOTTR_DEMO_MAX_ATTEMPTS: '2' }, { ...env, SPOTTR_DEMO_EXPIRES_AT: valid.SPOTTR_DEMO_EXPIRES_AT },
    ...['', '0', '-1', '1.5', '1e2', ' 2', 'Infinity', '101'].map(value => ({ ...valid, SPOTTR_DEMO_MAX_ATTEMPTS: value })),
    ...['', 'invalid-date', '2026-02-30T00:00:00.000Z', '2026-10-25T00:01:00', new Date(instant).toISOString(), new Date(instant + 86_400_001).toISOString()]
      .map(value => ({ ...valid, SPOTTR_DEMO_EXPIRES_AT: value }))
  ];
  for (const configuration of invalid) assert.throws(() => createGateway({ env: configuration, now: () => instant }), error => error.code === 'invalid_demo_configuration');
});

test('owner demo refuses database access outside its synthetic coaching scope', () => {
  assert.throws(() => createGateway({ env: { ...demoEnv(), TIGER_DATABASE_URL: 'postgresql://unused.invalid/demo' }, now: () => instant }),
    error => error.code === 'invalid_demo_configuration');
});

test('owner demo shares a finite budget across routes and ignores invalid or unauthenticated input', async t => {
  let calls = 0;
  const { request } = await serve(t, { env: demoEnv(2), now: () => instant, fetchImpl: async (_url, options) => { calls++; return providerResponse(options); } });
  assert.equal((await request('/v1/chat', { ...post(), headers: { ...post().headers, authorization: 'Bearer wrong' } })).status, 401);
  assert.equal((await request('/v1/proposal', post({ ...input, facts: [] }))).status, 422);
  assert.equal((await request('/v1/chat', { ...post(), body: '{' })).status, 400);
  assert.equal((await request('/v1/chat')).status, 200);
  assert.equal((await request('/v1/summary')).status, 200);
  const exhausted = await request('/v1/proposal');
  assert.equal(exhausted.status, 429);
  assert.equal((await exhausted.json()).error.code, 'demo_budget_exhausted');
  assert.equal(calls, 2);
});

test('owner demo rejects concurrent work without spending another attempt or queuing it', async t => {
  let release, entered;
  const providerEntered = new Promise(resolve => { entered = resolve; });
  const wait = new Promise(resolve => { release = resolve; });
  let calls = 0;
  const { request } = await serve(t, { env: demoEnv(2), now: () => instant, fetchImpl: async (_url, options) => {
    calls++; entered(); await wait; return providerResponse(options);
  } });
  const first = request('/v1/chat');
  await providerEntered;
  try {
    const busy = await request('/v1/proposal');
    assert.equal(busy.status, 429);
    assert.equal((await busy.json()).error.code, 'demo_busy');
    assert.equal(calls, 1);
  } finally { release(); }
  assert.equal((await first).status, 200);
  assert.equal((await request('/v1/proposal')).status, 200);
  assert.equal((await request('/v1/summary')).status, 429);
  assert.equal(calls, 2);
});

test('owner demo provider failures and timeouts consume attempts without automatic retries', async t => {
  for (const timeout of [false, true]) {
    let calls = 0;
    const { request } = await serve(t, { env: { ...demoEnv(1), GEMINI_TIMEOUT_MS: '10' }, now: () => instant, fetchImpl: (_url, options) => {
      calls++;
      if (!timeout) return Promise.resolve(new Response('private upstream details', { status: 503 }));
      return new Promise((_resolve, reject) => options.signal.addEventListener('abort', () => reject(options.signal.reason), { once: true }));
    } });
    assert.equal((await request('/v1/chat')).status, timeout ? 504 : 503);
    const exhausted = await request('/v1/proposal');
    assert.equal(exhausted.status, 429);
    assert.equal((await exhausted.json()).error.code, 'demo_budget_exhausted');
    assert.equal(calls, 1);
  }
});

test('owner demo expires at its absolute deadline before any later provider call', async t => {
  let clock = instant, calls = 0;
  const expires = instant + 60_000;
  const { request } = await serve(t, { env: demoEnv(3, expires), now: () => clock, fetchImpl: async (_url, options) => { calls++; return providerResponse(options); } });
  assert.equal((await request('/v1/chat')).status, 200);
  clock = expires;
  for (const path of ['/v1/chat', '/v1/summary', '/v1/proposal']) {
    const expired = await request(path);
    assert.equal(expired.status, 503);
    assert.equal((await expired.json()).error.code, 'demo_expired');
  }
  assert.equal((await request('/health', { method: 'GET' })).status, 200);
  assert.equal((await request('/unknown')).status, 404);
  assert.equal(calls, 1);
});

test('owner demo deadline aborts active generation without restarting it', async t => {
  let clock = instant, calls = 0, aborted = false;
  const { request } = await serve(t, { env: demoEnv(2, instant + 30), now: () => clock, fetchImpl: (_url, options) => {
    calls++;
    return new Promise((_resolve, reject) => options.signal.addEventListener('abort', () => { aborted = true; reject(options.signal.reason); }, { once: true }));
  } });
  const expired = await request('/v1/chat');
  assert.equal(expired.status, 503);
  assert.equal((await expired.json()).error.code, 'demo_expired');
  assert.equal(aborted, true);
  clock = instant + 31;
  assert.equal((await request('/v1/summary')).status, 503);
  assert.equal(calls, 1);
});

test('owner demo bounds incomplete HTTP bodies without reserving a provider attempt', { timeout: 16_000 }, async t => {
  let calls = 0;
  const { port, request } = await serve(t, { env: demoEnv(1), now: () => instant, fetchImpl: async (_url, options) => { calls++; return providerResponse(options); } });
  const socket = connect({ host: '127.0.0.1', port });
  t.after(() => socket.destroy());
  await once(socket, 'connect');
  let response = '';
  socket.setEncoding('utf8');
  socket.on('data', data => { response += data; });
  socket.write('POST /v1/chat HTTP/1.1\r\nHost: localhost\r\nAuthorization: Bearer owner-test-token\r\nContent-Type: application/json\r\nContent-Length: 100\r\n\r\n{');
  await once(socket, 'close');
  assert.match(response, /^HTTP\/1\.1 408 /);
  assert.equal(calls, 0);
  assert.equal((await request('/v1/chat')).status, 200);
  assert.equal(calls, 1);
});

test('local gateway remains unrestricted by demo budgets when settings are absent', async t => {
  let calls = 0;
  const { request } = await serve(t, { env, fetchImpl: async (_url, options) => { calls++; return providerResponse(options); } });
  const replies = await Promise.all(['/v1/chat', '/v1/summary', '/v1/proposal'].map(path => request(path)));
  assert.deepEqual(replies.map(reply => reply.status), [200, 200, 200]);
  assert.equal(calls, 3);
});

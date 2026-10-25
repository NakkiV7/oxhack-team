import assert from 'node:assert/strict';
import { once } from 'node:events';
import test from 'node:test';
import { randomUUID } from 'node:crypto';
import { createGateway } from '../src/gateway.mjs';
import { workoutRequest, workoutIDContract } from '../src/tiger-contracts.mjs';

const instant = Date.parse('2026-10-25T00:00:00.000Z');
const demoToken = 'synthetic-demo-credential-32-characters';
const env = { SPOTTR_GATEWAY_TOKEN: 'owner-test-token', SPOTTR_DEMO_ACCESS_TOKEN: demoToken,
  SPOTTR_DEMO_MAX_ATTEMPTS: '2', SPOTTR_DEMO_EXPIRES_AT: new Date(instant + 60_000).toISOString(),
  GEMINI_API_KEY: 'fake-key', GEMINI_MODEL: 'offline-model', ELEVENLABS_API_KEY: 'fake-key', ELEVENLABS_DAVID_VOICE_ID: 'fake-voice' };
const input = { generationID: 'demo-generation', message: 'Help me train.', facts: [{ id: 'observation', text: 'No saved history.' }] };
const post = (data = input, token = demoToken) => ({ method: 'POST', headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' }, body: JSON.stringify(data) });
const reply = () => Response.json({ candidates: [{ finishReason: 'STOP', content: { parts: [{ text: 'Synthetic reply.' }] } }] });
const voiceInput = () => ({ generationID: randomUUID(), sessionID: randomUUID(), cueID: randomUUID(), playbackToken: randomUUID(),
  voice: 'david', priority: 'pacing', text: 'Steady pace.', expiresAt: new Date(instant + 5000).toISOString() });
async function serve(t, options = {}) {
  const server = createGateway({ env, now: () => instant, fetchImpl: async () => reply(), ...options });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(() => new Promise(resolve => { server.closeAllConnections(); server.close(resolve); }));
  return (path, init = post()) => fetch(`http://127.0.0.1:${server.address().port}${path}`, init);
}

test('dedicated demo identity only authorizes exact bounded coaching aliases', async t => {
  let databaseCalls = 0, providerCalls = 0;
  const pool = { on() {}, query() { databaseCalls++; throw new Error('must not reach database'); } };
  const request = await serve(t, { pool, fetchImpl: async () => { providerCalls++; return reply(); } });
  assert.equal((await request('/demo/v1/chat')).status, 200);
  for (const path of ['/v1/chat', '/v1/workouts', '/v1/workouts/synthetic', '/v1/workouts/synthetic/telemetry']) {
    assert.equal((await request(path, { ...post(), method: path.includes('synthetic') ? 'GET' : 'POST', ...(path.includes('synthetic') ? { body: undefined } : {}) })).status, 401, path);
  }
  for (const path of ['/demo/v1/workouts', '/demo/health', '/demo/v1/chat?owner=1', '/demo/v1/chat/', '/demo/v1/config', '/demo/v1/snowflake']) {
    assert.equal((await request(path)).status, 404, path);
  }
  assert.equal((await request('/demo/v1/chat', post(input, env.SPOTTR_GATEWAY_TOKEN))).status, 401);
  assert.equal((await request('/demo/v1/chat', post(input, 'wrong'))).status, 401);
  assert.equal((await request('/v1/chat', post(input, env.SPOTTR_GATEWAY_TOKEN))).status, 200);
  assert.equal(databaseCalls, 0);
  assert.equal(providerCalls, 2);
});

test('demo configuration requires a distinct credential and the existing finite guard', () => {
  for (const configuration of [
    { ...env, SPOTTR_DEMO_MAX_ATTEMPTS: undefined, SPOTTR_DEMO_EXPIRES_AT: undefined },
    { ...env, SPOTTR_DEMO_ACCESS_TOKEN: env.SPOTTR_GATEWAY_TOKEN },
    { ...env, SPOTTR_DEMO_ACCESS_TOKEN: '' },
    { ...env, SPOTTR_DEMO_ACCESS_TOKEN: 'too-short' },
    { ...env, SPOTTR_GATEWAY_TOKEN: undefined }
  ]) assert.throws(() => createGateway({ env: configuration, now: () => instant }), error => error.code === 'invalid_demo_configuration');
});

test('demo identity cannot read or write configured owner Tiger data before any connection or SQL', async t => {
  const installationID = '5aa3804a-58e8-49fb-876f-5751ac9cbaca';
  const workoutID = '5c69ed48-c98e-4b4e-8e21-78d246743535';
  const workout = { installationID, record: { id: workoutID, date: '2026-10-25T00:00:00.000Z', sets: [], loggedSets: [], telemetry: [] } };
  assert.equal(workoutIDContract.safeParse(installationID).success, true);
  assert.equal(workoutRequest.safeParse(workout).success, true);
  let connections = 0, queries = 0;
  const query = async () => { queries++; throw new Error('offline SQL sentinel'); };
  const pool = { on() {}, query, async connect() { connections++; return { query, release() {} }; } };
  const request = await serve(t, { env: { ...env, TIGER_DATABASE_URL: 'postgresql://offline.invalid:5432/spottr?sslmode=verify-full', SPOTTR_INSTALLATION_ID: installationID }, pool });
  const read = token => ({ method: 'GET', headers: { authorization: `Bearer ${token}` } });
  const paths = [
    ['/v1/workouts', post(workout)],
    [`/v1/workouts/${workoutID}`, read(demoToken)],
    [`/v1/workouts/${workoutID}/telemetry?from=2026-10-25T00:00:00.000Z&to=2026-10-25T01:00:00.000Z`, read(demoToken)]
  ];
  for (const [path, options] of paths) {
    const denied = await request(path, options);
    assert.equal(denied.status, 401, path);
    assert.equal((await denied.json()).error.code, 'unauthorized', path);
    assert.equal((await request(`/demo${path}`, options)).status, 404, path);
    assert.equal(connections, 0, path);
    assert.equal(queries, 0, path);
  }
  assert.equal((await request('/demo/v1/chat')).status, 200);
  assert.equal(connections, 0);
  assert.equal(queries, 0);

  // Positive controls prove the same valid owner configuration and payload reach the offline SQL boundary.
  for (const [path, options] of [[`/v1/workouts/${workoutID}`, read(env.SPOTTR_GATEWAY_TOKEN)], ['/v1/workouts', post(workout, env.SPOTTR_GATEWAY_TOKEN)]]) {
    const before = queries;
    const owner = await request(path, options);
    assert.equal(owner.status, 503, path);
    assert.equal((await owner.json()).error.code, 'database_unavailable', path);
    assert.ok(queries > before, path);
  }
  assert.equal(connections, 1);
});

test('demo expiry covers cached voice discovery, refusals and generation before provider access', async t => {
  let clock = instant, calls = 0;
  const request = await serve(t, { now: () => clock, fetchImpl: async () => { calls++; return reply(); } });
  assert.equal((await request('/demo/v1/voices', { method: 'GET', headers: post().headers })).status, 200);
  clock += 60_000;
  for (const [path, init] of [['chat', post()], ['chat', post({ ...input, message: 'Write a poem about politics.' })], ['summary', post()], ['proposal', post()], ['week-proposal', post()], ['voice', post(voiceInput())], ['voices', { method: 'GET', headers: post().headers }]]) {
    const response = await request(`/demo/v1/${path}`, init);
    assert.equal(response.status, 503, path);
    assert.equal((await response.json()).error.code, 'demo_expired');
  }
  assert.equal(calls, 0);
});

test('demo shares the owner guard across voice and coaching; failures spend once without retries', async t => {
  let calls = 0;
  const request = await serve(t, { fetchImpl: async () => { calls++; return new Response('offline failure', { status: 503 }); } });
  assert.equal((await request('/demo/v1/voice', post(voiceInput()))).status, 503);
  assert.equal((await request('/demo/v1/chat')).status, 503);
  const exhausted = await request('/v1/chat', post(input, env.SPOTTR_GATEWAY_TOKEN));
  assert.equal(exhausted.status, 429);
  assert.equal((await exhausted.json()).error.code, 'demo_budget_exhausted');
  assert.equal(calls, 2);
});

test('demo structured routes preserve the existing summary, workout and week contracts', async t => {
  const grounded = { text: 'Only supplied preferences.', factIDs: ['observation'] };
  const workout = { generationID: input.generationID, items: [{ exerciseID: 'squat', sets: 1, target: 2, unit: 'reps', restSeconds: 30, factIDs: ['observation'] }], rationale: grounded };
  const week = { startDate: '2026-10-25', timeZone: 'Europe/London', availableDays: [0], targetDays: 1 };
  const weekly = { generationID: input.generationID, status: 'proposed', weekStart: week.startDate, timeZone: week.timeZone,
    days: Array.from({ length: 7 }, (_, index) => ({ date: `2026-10-${25 + index}`, kind: index === 0 ? 'workout' : 'rest', workout: index === 0 ? workout : null })),
    rationale: grounded, guidanceIDs: ['nhs-strength'] };
  const summary = { generationID: input.generationID, kind: 'session', headline: grounded, insights: [], focus: grounded };
  const request = await serve(t, { env: { ...env, SPOTTR_DEMO_MAX_ATTEMPTS: '3' }, fetchImpl: async (_url, options) => {
    const context = JSON.parse(JSON.parse(options.body).contents.at(-1).parts.at(-1).text);
    const output = { '/v1/summary': summary, '/v1/proposal': workout, '/v1/week-proposal': weekly }[context.task];
    return Response.json({ candidates: [{ finishReason: 'STOP', content: { parts: [{ text: JSON.stringify(output) }] } }] });
  } });
  for (const [route, data, expected] of [['summary', { ...input, kind: 'session' }, summary], ['proposal', input, workout], ['week-proposal', { ...input, week }, weekly]]) {
    const response = await request(`/demo/v1/${route}`, post(data));
    assert.equal(response.status, 200, route);
    assert.deepEqual(await response.json(), expected);
  }
  assert.equal((await request('/demo/v1/chat')).status, 429);
});

test('demo and owner cannot run concurrent provider attempts or queue a second paid request', async t => {
  let entered, release, calls = 0;
  const started = new Promise(resolve => { entered = resolve; });
  const wait = new Promise(resolve => { release = resolve; });
  const request = await serve(t, { fetchImpl: async () => { calls++; entered(); await wait; return reply(); } });
  const first = request('/demo/v1/chat');
  await started;
  try {
    const busy = await request('/v1/chat', post(input, env.SPOTTR_GATEWAY_TOKEN));
    assert.equal(busy.status, 429);
    assert.equal((await busy.json()).error.code, 'demo_busy');
    assert.equal(calls, 1);
  } finally { release(); }
  assert.equal((await first).status, 200);
});

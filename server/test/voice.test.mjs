import assert from 'node:assert/strict';
import { once } from 'node:events';
import test from 'node:test';
import { createGateway } from '../src/gateway.mjs';

const initialTime = Date.parse('2026-10-25T07:00:00.000Z');
const configuration = { SPOTTR_GATEWAY_TOKEN: 'owner-token', ELEVENLABS_API_KEY: 'private-eleven-key', ELEVENLABS_DAVID_VOICE_ID: 'private-david-id', ELEVENLABS_ARNOLD_VOICE_ID: 'private-arnold-id' };
const ids = { generationID: '10000000-0000-4000-8000-000000000001', sessionID: '10000000-0000-4000-8000-000000000002', cueID: '10000000-0000-4000-8000-000000000003', playbackToken: '10000000-0000-4000-8000-000000000004' };
const cue = (at = initialTime, changes = {}) => ({ ...ids, voice: 'david', text: 'Keep your whole body in view.', priority: 'form', expiresAt: new Date(at + 6_000).toISOString(), ...changes });
const mp3 = () => { const bytes = Buffer.alloc(104); bytes.set([0xff, 0xf3, 0x40, 0xc0]); return bytes; };
const audio = (bytes = mp3(), type = 'audio/mpeg') => new Response(bytes, { headers: { 'content-type': type } });
const post = value => ({ method: 'POST', headers: { authorization: 'Bearer owner-token', 'content-type': 'application/json' }, body: JSON.stringify(value) });

async function serve(t, options = {}) {
  const server = createGateway({ env: configuration, now: () => initialTime, ...options });
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  t.after(() => new Promise(resolve => { server.close(resolve); server.closeIdleConnections(); }));
  return (path, options) => fetch(`http://127.0.0.1:${server.address().port}${path}`, options);
}

test('voice discovery is authenticated configuration metadata, never a provider call or availability claim', async t => {
  let calls = 0;
  const request = await serve(t, { fetchImpl: async () => { calls++; return audio(); } });
  const health = await (await request('/health')).json();
  assert.deepEqual(health.providers.elevenlabs, { configured: true, adapterImplemented: true });
  assert.equal((await request('/v1/voices')).status, 401);
  const response = await request('/v1/voices', { headers: { authorization: 'Bearer owner-token' } });
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { voices: [{ id: 'david', name: 'David' }, { id: 'arnold', name: 'Arnold' }], availability: 'configured_not_verified' });
  assert.equal(calls, 0);
});

test('explicit voice synthesis uses only a server-selected voice and echoes unchanged playback identity and expiry', async t => {
  let calls = 0;
  const input = cue();
  const request = await serve(t, { fetchImpl: async (url, options) => {
    calls++;
    assert.equal(url, 'https://api.elevenlabs.io/v1/text-to-speech/private-david-id?output_format=mp3_22050_32');
    assert.equal(options.method, 'POST'); assert.equal(options.redirect, 'error');
    assert.equal(options.headers['xi-api-key'], configuration.ELEVENLABS_API_KEY);
    assert.deepEqual(JSON.parse(options.body), { text: input.text, model_id: 'eleven_flash_v2_5' });
    return audio();
  } });
  const response = await request('/v1/voice', post(input));
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.deepEqual(body, { ...input, mimeType: 'audio/mpeg', audioBase64: mp3().toString('base64') });
  assert.equal(/private-|xi-api-key/.test(JSON.stringify(body)), false);
  assert.equal(calls, 1);
});

test('invalid or stop cues and malformed/authless requests cannot spend voice credits', async t => {
  let calls = 0;
  const request = await serve(t, { fetchImpl: async () => { calls++; return audio(); } });
  for (const input of [cue(initialTime, { text: 'x'.repeat(501) }), cue(initialTime, { text: ' ' }), cue(initialTime, { text: 'bad\u0000text' }), cue(initialTime, { priority: 'stop' }), cue(initialTime, { priority: 'chat' }), cue(initialTime, { sessionID: 'session' }), cue(initialTime, { playbackToken: 'token' }), cue(initialTime, { expiresAt: new Date(initialTime).toISOString() }), cue(initialTime, { expiresAt: new Date(initialTime + 6001).toISOString() }), cue(initialTime, { expiresAt: null }), cue(initialTime, { voice: 'private-provider-id' }), cue(initialTime, { extra: true })]) {
    assert.equal((await request('/v1/voice', post(input))).status, 422);
  }
  assert.equal((await request('/v1/voice', { ...post(cue()), headers: { 'content-type': 'application/json' } })).status, 401);
  assert.equal((await request('/v1/voice', { ...post(cue()), headers: { authorization: 'Bearer owner-token' } })).status, 415);
  assert.equal((await request('/v1/voice', { ...post(cue()), body: '{' })).status, 400);
  assert.equal((await request('/v1/voice', post(cue(initialTime, { text: 'x'.repeat(8193) })))).status, 413);
  assert.equal((await request('/v1/voice', { headers: { authorization: 'Bearer owner-token' } })).status, 405);
  assert.equal(calls, 0);
});

test('missing or invalid voice configuration never invents a default coach or silently ignores a deadline', async t => {
  let calls = 0;
  for (const change of [{ ELEVENLABS_API_KEY: '' }, { ELEVENLABS_DAVID_VOICE_ID: '' }, { ELEVENLABS_DAVID_VOICE_ID: '../not-a-voice' }, { ELEVENLABS_TIMEOUT_MS: '0' }, { ELEVENLABS_TIMEOUT_MS: '6001' }, { ELEVENLABS_TIMEOUT_MS: 'unbounded' }]) {
    const request = await serve(t, { env: { ...configuration, ...change }, fetchImpl: async () => { calls++; return audio(); } });
    assert.equal((await request('/v1/voice', post(cue()))).status, 503);
  }
  const request = await serve(t, { env: { SPOTTR_GATEWAY_TOKEN: configuration.SPOTTR_GATEWAY_TOKEN }, fetchImpl: async () => { calls++; return audio(); } });
  assert.deepEqual((await (await request('/v1/voices', { headers: { authorization: 'Bearer owner-token' } })).json()).voices, []);
  assert.equal(calls, 0);
});

test('voice cache is bounded, expires, and keys actual voice and text while preserving each request context', async t => {
  let clock = initialTime, calls = 0;
  const request = await serve(t, { now: () => clock, fetchImpl: async () => { calls++; return audio(); } });
  assert.equal((await request('/v1/voice', post(cue(clock)))).status, 200);
  const changed = cue(clock, { cueID: '20000000-0000-4000-8000-000000000003', playbackToken: '20000000-0000-4000-8000-000000000004' });
  const cached = await request('/v1/voice', post(changed));
  assert.equal((await cached.json()).playbackToken, changed.playbackToken);
  assert.equal(calls, 1);
  assert.equal((await request('/v1/voice', post(cue(clock, { voice: 'arnold' })))).status, 200);
  assert.equal(calls, 2);
  for (let i = 0; i < 33; i++) assert.equal((await request('/v1/voice', post(cue(clock, { text: `Synthetic cue ${i}` })))).status, 200);
  assert.equal((await request('/v1/voice', post(cue(clock)))).status, 200);
  assert.equal(calls, 36, 'oldest audio must be evicted after 32 cache entries');
  clock += 600_001;
  assert.equal((await request('/v1/voice', post(cue(clock)))).status, 200);
  assert.equal(calls, 37, 'expired audio is generated only on a new explicit request');
});

test('late synthesis is discarded without extending expiry or caching a stale result', async t => {
  let clock = initialTime, calls = 0;
  const request = await serve(t, { now: () => clock, fetchImpl: async () => { calls++; if (calls === 1) clock += 6001; return audio(); } });
  const response = await request('/v1/voice', post(cue()));
  assert.equal(response.status, 409);
  assert.equal((await response.json()).error.code, 'voice_expired');
  assert.equal((await request('/v1/voice', post(cue(clock)))).status, 200);
  assert.equal(calls, 2);
});

test('wrong audio types, headers, oversized streams and provider errors fail privately without retries', async t => {
  for (const result of [() => audio(mp3(), 'application/json'), () => audio(Buffer.from('not mp3')), () => audio(Buffer.alloc(262_145)), () => new Response('private provider error private-eleven-key', { status: 429 })]) {
    let calls = 0;
    const request = await serve(t, { fetchImpl: async () => { calls++; return result(); } });
    const response = await request('/v1/voice', post(cue()));
    assert.ok([502, 503].includes(response.status));
    assert.equal(/private|provider error/.test(await response.text()), false);
    assert.equal(calls, 1);
  }
});

test('voice provider and body reads have bounded deadlines with no automatic retry', async t => {
  for (const bodyStalls of [false, true]) {
    let calls = 0;
    const request = await serve(t, { env: { ...configuration, ELEVENLABS_TIMEOUT_MS: '20' }, fetchImpl: async () => {
      calls++;
      if (!bodyStalls) return new Promise(() => {});
      return new Response(new ReadableStream({ start(controller) { controller.enqueue(mp3()); } }), { headers: { 'content-type': 'audio/mpeg' } });
    } });
    const response = await request('/v1/voice', post(cue()));
    assert.equal(response.status, 504);
    assert.equal((await response.json()).error.code, 'voice_timeout');
    assert.equal(calls, 1);
  }
});

test('only one fresh synthesis is active and client disconnect cancels it without prewarming', async t => {
  let calls = 0, started, aborted;
  const beginning = new Promise(resolve => { started = resolve; });
  const cancellation = new Promise(resolve => { aborted = resolve; });
  const request = await serve(t, { fetchImpl: async (_url, { signal }) => {
    calls++; started(); signal.addEventListener('abort', () => aborted(), { once: true });
    return new Promise(() => {});
  } });
  const controller = new AbortController();
  const first = request('/v1/voice', { ...post(cue()), signal: controller.signal }).catch(error => error);
  assert.equal(await Promise.race([beginning.then(() => true), first.then(() => false)]), true, 'request must reach the voice adapter');
  assert.equal((await request('/v1/voice', post(cue(initialTime, { text: 'Different cue' })))).status, 429);
  controller.abort(); await first; await cancellation;
  assert.equal(calls, 1);
});

test('owner demo allowance is shared with Gemini, includes voice failures and expires even for cached audio', async t => {
  let clock = initialTime, calls = 0;
  const env = { ...configuration, GEMINI_API_KEY: 'unused-key', GEMINI_MODEL: 'unused-model', SPOTTR_DEMO_MAX_ATTEMPTS: '1', SPOTTR_DEMO_EXPIRES_AT: new Date(initialTime + 60_000).toISOString() };
  const request = await serve(t, { env, now: () => clock, fetchImpl: async () => { calls++; return audio(); } });
  assert.equal((await request('/v1/voice', post(cue(initialTime, { priority: 'stop' })))).status, 422);
  assert.equal((await request('/v1/voice', post(cue()))).status, 200);
  assert.equal((await request('/v1/voice', post(cue()))).status, 200, 'cached audio costs no new attempt');
  const chat = { generationID: 'g', message: 'Help me exercise', history: [], facts: [], availableSupport: [] };
  assert.equal((await request('/v1/chat', post(chat))).status, 429);
  clock += 60_001;
  assert.equal((await request('/v1/voice', post(cue(clock)))).status, 503);
  assert.equal((await request('/v1/voices', { headers: { authorization: 'Bearer owner-token' } })).status, 503);
  assert.equal(calls, 1);
  const failed = await serve(t, { env, now: () => initialTime, fetchImpl: async () => new Response('', { status: 500 }) });
  assert.equal((await failed('/v1/voice', post(cue()))).status, 503);
  assert.equal((await failed('/v1/chat', post(chat))).status, 429);
});

test('demo expiry between authorization and completed body validation also blocks cached audio', async t => {
  let clock = initialTime, expireAfterClockRead = false, calls = 0;
  const now = () => { const value = clock; if (expireAfterClockRead) { clock += 60_001; expireAfterClockRead = false; } return value; };
  const env = { ...configuration, SPOTTR_DEMO_MAX_ATTEMPTS: '1', SPOTTR_DEMO_EXPIRES_AT: new Date(initialTime + 60_000).toISOString() };
  const request = await serve(t, { env, now, fetchImpl: async () => { calls++; return audio(); } });
  assert.equal((await request('/v1/voice', post(cue()))).status, 200);
  expireAfterClockRead = true;
  const response = await request('/v1/voice', post(cue(initialTime + 60_001)));
  assert.equal(response.status, 503);
  assert.equal((await response.json()).error.code, 'demo_expired');
  assert.equal(calls, 1);
});

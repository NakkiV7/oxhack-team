import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { mkdtemp, copyFile, rm } from 'node:fs/promises';
import { createServer } from 'node:net';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';

async function startOfflineServer(t) {
  const folder = await mkdtemp(join(tmpdir(), 'pushup-server-test-'));
  const reservation = createServer();
  reservation.listen(0, '127.0.0.1');
  await once(reservation, 'listening');
  const port = reservation.address().port;
  await new Promise((resolve) => reservation.close(resolve));
  for (const file of ['server.mjs', 'ask.mjs']) {
    await copyFile(new URL(`../${file}`, import.meta.url), join(folder, file));
  }
  const child = spawn(process.execPath, [join(folder, 'server.mjs')], {
    env: { PATH: process.env.PATH, PORT: String(port), GEMINI_API_KEY: '' },
    stdio: 'ignore',
  });
  const exited = once(child, 'exit');
  t.after(async () => {
    child.kill();
    await exited;
    await rm(folder, { recursive: true, force: true });
  });
  const request = (path, options = {}) => fetch(`http://127.0.0.1:${port}${path}`, {
    ...options, signal: options.signal ?? AbortSignal.timeout(3000),
  });
  for (let attempt = 0; attempt < 100; attempt += 1) {
    try {
      if ((await request('/state')).ok) return request;
    } catch {}
    await delay(20);
  }
  throw new Error('Offline prototype server did not start');
}

test('phone control requires the code and a listening Mac page', async (t) => {
  const request = await startOfflineServer(t);
  const token = await (await request('/control-code')).text();
  assert.ok(/^[0-9a-f]{8}$/.test(token));
  const control = (body) => request('/control', { method: 'POST', body: JSON.stringify(body) });
  assert.equal((await control({ cmd: 'stop' })).status, 403);
  assert.equal((await control({ cmd: 'start', token })).status, 400);
  assert.equal((await control({ cmd: 'stop', token })).status, 503);

  const subscription = new AbortController();
  t.after(() => subscription.abort());
  const stream = await request('/coach-events', { signal: subscription.signal });
  const reader = stream.body.getReader();
  await reader.read();
  assert.equal((await control({ cmd: 'pause', token })).status, 200);
  const event = new TextDecoder().decode((await reader.read()).value);
  assert.match(event, /event: control\ndata: \{"cmd":"pause"\}/);
  subscription.abort();
});

test('five wrong control codes lock the address before a correct code is accepted', async (t) => {
  const request = await startOfflineServer(t);
  const token = await (await request('/control-code')).text();
  for (let attempt = 0; attempt < 5; attempt += 1) {
    const response = await request('/control', { method: 'POST', body: JSON.stringify({ cmd: 'stop', token: '' }) });
    assert.equal(response.status, 403);
  }
  const response = await request('/control', { method: 'POST', body: JSON.stringify({ cmd: 'stop', token }) });
  assert.equal(response.status, 429);
});

test('the offline coach fails without making a provider request', async (t) => {
  const request = await startOfflineServer(t);
  const response = await request('/ask', { method: 'POST', body: JSON.stringify({ q: 'How should I position my arms?' }) });
  assert.equal(response.status, 503);
  assert.match((await response.json()).error, /Coach is off/);
});

test('valid published state is replayed and malformed JSON is rejected', async (t) => {
  const request = await startOfflineServer(t);
  assert.equal((await request('/state', { method: 'POST', body: '{' })).status, 400);
  const state = { running: false, count: 3, paused: true, clockMs: 5000 };
  assert.equal((await request('/state', { method: 'POST', body: JSON.stringify(state) })).status, 204);
  assert.deepEqual(await (await request('/state')).json(), state);
  const subscription = new AbortController();
  t.after(() => subscription.abort());
  const stream = await request('/events', { signal: subscription.signal });
  const event = new TextDecoder().decode((await stream.body.getReader().read()).value);
  assert.ok(event.includes(`data: ${JSON.stringify(state)}\n\n`));
  subscription.abort();
});

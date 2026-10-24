import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { mkdtemp, copyFile, mkdir, writeFile, stat, rm } from 'node:fs/promises';
import { createServer } from 'node:net';
import { request as httpRequest } from 'node:http';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';

async function startOfflineServer(t, { tigerScript, initialProfile, env = {} } = {}) {
  const folder = await mkdtemp(join(tmpdir(), 'pushup-server-test-'));
  const reservation = createServer();
  reservation.listen(0, '127.0.0.1');
  await once(reservation, 'listening');
  const port = reservation.address().port;
  await new Promise((resolve) => reservation.close(resolve));
  for (const file of ['server.mjs', 'ask.mjs', 'profile.mjs', 'profile-service.mjs', 'sync.mjs']) {
    await copyFile(new URL(`../${file}`, import.meta.url), join(folder, file));
  }
  await mkdir(join(folder, 'data'));
  await copyFile(new URL('../data/history.csv', import.meta.url), join(folder, 'data/history.csv'));
  if (initialProfile) await writeFile(join(folder, 'data/profile.json'), JSON.stringify(initialProfile));
  if (tigerScript) await writeFile(join(folder, 'tiger.mjs'), tigerScript);
  const child = spawn(process.execPath, [join(folder, 'server.mjs')], {
    env: { PATH: process.env.PATH, PORT: String(port), GEMINI_API_KEY: '', ...env },
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
  request.rawStatus = (path, options = {}) => new Promise((resolve, reject) => {
    const req = httpRequest({ hostname: '127.0.0.1', port, path, ...options }, (res) => {
      res.resume();
      res.on('end', () => resolve(res.statusCode));
    });
    req.on('error', reject);
    req.end(options.body ?? '');
  });
  request.profilePath = join(folder, 'data/profile.json');
  request.origin = `http://127.0.0.1:${port}`;
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

test('cloud mutations require same-origin JSON and the current local session token', async (t) => {
  const request = await startOfflineServer(t);
  const contextResponse = await request('/cloud-context');
  assert.equal(contextResponse.status, 200);
  const context = await contextResponse.json();
  assert.equal(context.userId, 'local');
  assert.equal(context.cloudAvailable, false);
  assert.match(context.token, /^[0-9a-f]{64}$/);
  const send = (path, headers = {}, body = {}) => request(path, { method: 'POST', headers, body: JSON.stringify(body) });
  const authorized = { Authorization: `Bearer ${context.token}`, 'Content-Type': 'application/json', Origin: request.origin };
  for (const path of ['/sync', '/profile/train']) {
    assert.equal((await send(path)).status, 403);
    assert.equal((await send(path, { ...authorized, Origin: 'https://attacker.invalid' })).status, 403);
    assert.equal(await request.rawStatus(path, { method: 'POST', headers: { ...authorized, Host: 'attacker.invalid' }, body: '{}' }), 403);
    assert.equal((await send(path, { ...authorized, 'Content-Type': 'text/plain' })).status, 415);
  }
  assert.equal((await send('/sync', authorized, { cloudConsent: true })).status, 503);
  assert.equal(await request.rawStatus('/cloud-context', { headers: { Host: 'attacker.invalid' } }), 403);
  assert.equal((await request('/profile/status', { headers: { Origin: 'https://attacker.invalid' } })).status, 403);
});

test('cloud writes preserve owner and immutable workout receipt and reject unapproved uploads', async (t) => {
  const request = await startOfflineServer(t, {
    env: { TIGER_DATABASE_URL: 'configured-offline', PUSHUP_USER_ID: 'owner-A' },
    tigerScript: `
      export const createPool = async () => ({});
      export const insertReps = async (_pool, rows, options) => {
        if (options.userId !== 'owner-A' || options.source !== 'real' || !options.workoutId || !/^[a-f0-9]{64}$/.test(options.contentHash ?? '')) throw new Error('Missing receipt');
        if (rows[0].elbow === 80) throw Object.assign(new Error('Workout content changed'), { code: 'workout_conflict' });
        return rows.length;
      };
    `,
  });
  const context = await (await request('/cloud-context')).json();
  assert.equal(context.userId, 'owner-A');
  const headers = { Authorization: `Bearer ${context.token}`, 'Content-Type': 'application/json', Origin: request.origin };
  const body = {
    workoutId: 'a084e460-55eb-4089-b050-d424095a34e5', userId: 'owner-A', source: 'real', variation: 'standard', cloudConsent: true,
    startedAt: Date.UTC(2026, 9, 23, 10), endedAt: Date.UTC(2026, 9, 23, 10, 0, 5), timeMs: 5000,
    reps: [{ observedAt: Date.UTC(2026, 9, 23, 10, 0, 4), counted: true, good: true, minElbow: 64, minLine: 175, secs: 3, issue: null }],
  };
  const send = (payload) => request('/sync', { method: 'POST', headers, body: JSON.stringify(payload) });
  assert.equal((await send({ ...body, cloudConsent: false })).status, 422);
  assert.equal((await send({ ...body, userId: 'owner-B' })).status, 422);
  assert.equal((await send({ ...body, source: 'video' })).status, 422);
  assert.equal((await send(body)).status, 200);
  const changed = { ...body, reps: [{ ...body.reps[0], minElbow: 80 }] };
  assert.equal((await send(changed)).status, 409);
});

test('profile HTTP flow retains training provenance and invalidates another owner', async (t) => {
  const request = await startOfflineServer(t, { env: { PUSHUP_USER_ID: 'owner-A' } });
  const context = await (await request('/cloud-context')).json();
  const trained = await (await request('/profile/train', {
    method: 'POST', headers: { Authorization: `Bearer ${context.token}`, 'Content-Type': 'application/json' }, body: '{}',
  })).json();
  assert.equal(trained.ok, true);
  assert.equal((await stat(request.profilePath)).mode & 0o777, 0o600);
  assert.equal(trained.profile.provenance.userId, 'owner-A');
  assert.deepEqual(trained.profile.provenance.selectedSources, ['mock']);
  const status = await (await request('/profile/status')).json();
  assert.equal(status.profile.mockShare, 1);
  assert.deepEqual(status.profile.provenance, trained.profile.provenance);
  const other = await startOfflineServer(t, { env: { PUSHUP_USER_ID: 'owner-B' }, initialProfile: trained.profile });
  const otherStatus = await (await other('/profile/status')).json();
  assert.equal(otherStatus.profile, null);
});

import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createServer } from 'node:net';
import { once } from 'node:events';
import { setTimeout as delay } from 'node:timers/promises';
import { fileURLToPath } from 'node:url';

for (const exercise of ['squat', 'pushup']) {
  test(`${exercise} offers playable Arnold and Goggins without provider keys`, async (t) => {
    const reservation = createServer().listen(0, '127.0.0.1');
    await once(reservation, 'listening');
    const port = reservation.address().port;
    await new Promise((resolve) => reservation.close(resolve));
    const child = spawn(process.execPath, [fileURLToPath(new URL(`../../${exercise}/server.mjs`, import.meta.url))], {
      env: { PATH: process.env.PATH, PORT: String(port) }, stdio: 'ignore',
    });
    const exited = once(child, 'exit');
    t.after(async () => { child.kill(); await exited; });
    const request = (path) => fetch(`http://localhost:${port}${path}`, { signal: AbortSignal.timeout(3000) });
    let response;
    for (let attempt = 0; attempt < 100; attempt++) {
      try { response = await request('/voices'); break; } catch { await delay(30); }
    }
    assert.ok(response?.ok);
    const voices = await response.json();
    assert.deepEqual(voices.map((voice) => voice.id), ['offline-arnold', 'offline-goggins']);
    for (const voice of voices) {
      assert.equal(voice.offline, true);
      assert.ok(voice.clips.some((clip) => clip.text === '1'));
      const audio = await request(`/say?voice=${voice.id}&text=1`);
      assert.equal(audio.status, 200);
      assert.equal(audio.headers.get('content-type'), 'audio/mpeg');
      assert.ok((await audio.arrayBuffer()).byteLength > 1000);
    }
    assert.equal((await request('/say?voice=offline-arnold&text=unknown')).status, 204);
    assert.equal((await request('/say?voice=provider&text=hello')).status, 404);
    assert.equal((await request('/say?voice=offline-arnold&text=../../.env')).status, 204);
  });
}

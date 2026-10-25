import assert from 'node:assert/strict';
import { once } from 'node:events';
import { createServer } from 'node:http';
import { spawn } from 'node:child_process';
import { mkdtemp, readFile, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { createGateway } from '../src/gateway.mjs';

test('Caddy exposes only exact demo routes outside owner CIDRs, preserving landing and owner protection',
  { skip: !process.env.SPOTTR_TEST_CADDY, timeout: 15_000 }, async t => {
    const folder = await mkdtemp(join(tmpdir(), 'spottr-demo-proxy-'));
    t.after(() => rm(folder, { recursive: true, force: true }));
    await writeFile(join(folder, 'index.html'), 'Synthetic landing');
    const gateway = createGateway({ env: { SPOTTR_GATEWAY_TOKEN: 'synthetic-owner' } });
    gateway.listen(0, '127.0.0.1');
    await once(gateway, 'listening');
    t.after(() => new Promise(resolve => { gateway.closeAllConnections(); gateway.close(resolve); }));
    const reservation = createServer();
    reservation.listen(0, '127.0.0.1');
    await once(reservation, 'listening');
    const port = reservation.address().port;
    await new Promise(resolve => reservation.close(resolve));
    const original = await readFile(new URL('../../deploy/Caddyfile', import.meta.url), 'utf8');
    const config = original.replace('email {$ACME_EMAIL}', 'admin off\n    email demo@example.invalid')
      .replace('{$SPOTTR_HOSTNAME}', `http://127.0.0.1:${port}`)
      .replaceAll('{$SPOTTR_ALLOWED_CIDRS}', '192.0.2.1/32')
      .replaceAll('gateway:8787', `127.0.0.1:${gateway.address().port}`)
      .replace('/srv/landing', folder);
    const configPath = join(folder, 'Caddyfile');
    await writeFile(configPath, config);
    const caddy = spawn(process.env.SPOTTR_TEST_CADDY, ['run', '--config', configPath, '--adapter', 'caddyfile'], {
      stdio: 'ignore', env: { ...process.env, XDG_DATA_HOME: folder, XDG_CONFIG_HOME: folder }
    });
    t.after(async () => { if (caddy.exitCode === null) { caddy.kill('SIGTERM'); await once(caddy, 'exit'); } });
    let ready = false;
    for (let attempt = 0; attempt < 50; attempt++) {
      try { ready = (await fetch(`http://127.0.0.1:${port}/`)).status === 200; } catch {}
      if (ready) break;
      await new Promise(resolve => setTimeout(resolve, 50));
    }
    assert.equal(ready, true, 'Caddy must start on the task-owned loopback port');
    for (const route of ['chat', 'summary', 'proposal', 'week-proposal', 'voice', 'voices']) {
      const response = await fetch(`http://127.0.0.1:${port}/demo/v1/${route}`, {
        method: route === 'voices' ? 'GET' : 'POST', headers: { authorization: 'Bearer synthetic-owner' }
      });
      assert.equal(response.status, 401, route);
    }
    for (const path of ['/v1/chat', '/v1/workouts', '/health', '/demo/v1/workouts', '/demo/v1/chat/', '/demo/health', '/config']) {
      const response = await fetch(`http://127.0.0.1:${port}${path}`, { headers: { authorization: 'Bearer synthetic-owner' } });
      assert.equal(response.status, 403, path);
    }
    assert.equal(await (await fetch(`http://127.0.0.1:${port}/`)).text(), 'Synthetic landing');
  });

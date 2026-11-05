import test from 'node:test';
import assert from 'node:assert/strict';
import site, { type SiteEnv } from '../src/index.ts';
const origin = 'https://spottr.example';
const env: SiteEnv = {
  ORIGIN: origin, AUTH_ENCRYPTION_KEY: '', AUTH_TOKEN_PEPPER: '',
  DB: { prepare: () => { throw new Error('Static pages must not access account storage'); }, batch: () => { throw new Error('Static pages must not access account storage'); } },
  ASSETS: { fetch: async request => new Response(new URL(request.url).pathname === '/missing/' ? 'Missing page' : '<h1>Spottr</h1>', { status: new URL(request.url).pathname === '/missing/' ? 404 : 200, headers: { 'Content-Type': 'text/html' } }) }
};
test('public pages, missing pages and account shell have browser protection without database access', async () => {
  for (const path of ['/', '/privacy/', '/account/', '/missing/']) {
    const response = await site.fetch(new Request(origin + path), env);
    assert.equal(response.status, path === '/missing/' ? 404 : 200);
    assert.equal(response.headers.get('X-Content-Type-Options'), 'nosniff');
    assert.equal(response.headers.get('X-Frame-Options'), 'DENY');
    assert.match(response.headers.get('Content-Security-Policy') ?? '', /script-src 'self'/);
    assert.match(response.headers.get('Permissions-Policy') ?? '', /camera=\(\)/);
    assert.match(response.headers.get('Strict-Transport-Security') ?? '', /31536000/);
    assert.equal(response.headers.has('Set-Cookie'), false);
    if (path === '/account/') assert.equal(response.headers.get('Cache-Control'), 'no-store');
  }
});
test('health endpoint is non-sensitive and HTTP is upgraded to the same HTTPS path', async () => {
  const health = await site.fetch(new Request(origin + '/api/health'), env);
  assert.deepEqual(await health.json(), { service: 'Spottr', status: 'available' });
  assert.equal(health.headers.get('Cache-Control'), 'no-store');
  const redirect = await site.fetch(new Request('http://spottr.example/privacy/?x=1'), env);
  assert.equal(redirect.status, 308);
  assert.equal(redirect.headers.get('Location'), origin + '/privacy/?x=1');
});

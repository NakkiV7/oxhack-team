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
test('native v1 routes reach the additive handler without a browser Origin header',async()=>{
 const {fixture}=await import('./native-fixture.ts');const f=await fixture();try{
 const response=await site.fetch(new Request(origin+'/api/native/v1/passkey/login/options',{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'}),{...f.env,ASSETS:env.ASSETS});
 assert.equal(response.status,200);assert.equal(response.headers.get('Cache-Control'),'no-store');
 }finally{await f.mf.dispose();}
});
test('scheduled retention removes expired native challenges and flows without deleting active accounts',async()=>{
 const {fixture}=await import('./native-fixture.ts');const f=await fixture();try{
 await f.seed();
 await f.db.prepare('INSERT INTO native_flows(id,stage,payload,expires_at) VALUES(?,?,?,?)').bind('expired','email','test-only',1).run();
 await f.db.prepare('INSERT INTO native_mail_reservations VALUES(?,?,?,?,?)').bind('old','2000-01-01','2000-01','hashed-test',1).run();
 await site.scheduled({}, {...f.env,ASSETS:env.ASSETS});
 assert.equal((await f.db.prepare('SELECT COUNT(*) AS n FROM native_flows').first<{n:number}>())?.n,0);
 assert.equal((await f.db.prepare('SELECT COUNT(*) AS n FROM native_mail_reservations').first<{n:number}>())?.n,0);
 assert.equal((await f.db.prepare('SELECT COUNT(*) AS n FROM users').first<{n:number}>())?.n,1);
 }finally{await f.mf.dispose();}
});
test('native passkeys have exact production webcredentials association without redirects or account access', async()=>{
 const response=await site.fetch(new Request('https://spottr.omarchoudhry.co.uk/.well-known/apple-app-site-association'),env);
 assert.equal(response.status,200);assert.match(response.headers.get('Content-Type')??'',/application\/json/);
 assert.deepEqual(await response.json(),{webcredentials:{apps:['952HTWFJX7.com.omarchoudhry.spottr']}});
 assert.equal(response.headers.has('Location'),false);
});

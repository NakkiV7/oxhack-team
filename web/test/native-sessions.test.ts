import test from 'node:test';
import assert from 'node:assert/strict';
import { z } from 'zod';
import { fixture } from './native-fixture.ts';

test('device signed refresh rotates, survives handler restart and returns the same bounded retry result',async()=>{
 const f=await fixture();try {
 const d=await f.seed(),body={requestID:crypto.randomUUID()};
 const result=await f.signed('/session/refresh',body,d.refreshToken,d.keys);
 assert.equal(result.response.status,200);
 assert.equal(Date.parse(z.string().parse(result.json['accessExpiresAt']))-f.now,900000);
 assert.equal(Date.parse(z.string().parse(result.json['refreshExpiresAt']))-f.now,180*86400000);
 const retry=await f.signed('/session/refresh',body,d.refreshToken,d.keys);
 assert.equal(retry.response.status,200);assert.deepEqual(retry.json,result.json);
 const access=z.string().parse(result.json['accessToken']);
 assert.equal((await f.signed('/session/current',{},access,d.keys)).response.status,200);
 assert.equal((await f.signed('/session/current',{},d.accessToken,d.keys)).response.status,401);
 f.advance(61);
 assert.equal((await f.signed('/session/refresh',body,d.refreshToken,d.keys)).response.status,401);
 assert.equal((await f.signed('/session/current',{},access,d.keys)).response.status,401);
 }finally{await f.mf.dispose();}
});

test('concurrent identical refreshes return one durable result and different IDs revoke reuse',async()=>{
 const f=await fixture();try{
 const d=await f.seed(),body={requestID:crypto.randomUUID()};
 const results=await Promise.all([f.signed('/session/refresh',body,d.refreshToken,d.keys),f.signed('/session/refresh',body,d.refreshToken,d.keys)]);
 assert.deepEqual(results.map(v=>v.response.status),[200,200]);assert.deepEqual(results[0]?.json,results[1]?.json);
 assert.equal(results[0]?.json['appAccountToken'],d.accountID);
 assert.equal((await f.signed('/session/refresh',{requestID:crypto.randomUUID()},d.refreshToken,d.keys)).response.status,401);
 }finally{await f.mf.dispose();}
});

test('sign-out, device revoke, auth-version rotation and account deletion invalidate native leases',async()=>{
 const f=await fixture();try{
 const d=await f.seed();
 assert.equal((await f.signed('/session/current',{},d.accessToken,d.keys)).json['appAccountToken'],d.accountID);
 assert.equal((await f.signed('/session/sign-out',{},d.accessToken,d.keys)).response.status,200);
 assert.equal((await f.signed('/session/refresh',{requestID:crypto.randomUUID()},d.refreshToken,d.keys)).response.status,401);
 const e=await f.seed();
 assert.equal((await f.signed('/session/revoke',{deviceID:e.deviceID},e.accessToken,e.keys)).response.status,200);
 const a=await f.seed();
 assert.equal((await f.signed('/account/delete',{confirm:'DELETE'},a.accessToken,a.keys)).response.status,200);
 assert.equal(await f.db.prepare('SELECT id FROM users WHERE id=?').bind(a.accountID).first(),null);
 const b=await f.seed();await f.db.prepare('UPDATE users SET auth_version=2 WHERE id=?').bind(b.accountID).run();
 assert.equal((await f.signed('/session/current',{},b.accessToken,b.keys)).response.status,401);
 }finally{await f.mf.dispose();}
});

test('unknown fields, oversized bodies, wrong origins and rate bursts fail closed',async()=>{
 const f=await fixture();try{
 assert.equal((await f.request('/passkey/login/options',{accountID:'forged'})).response.status,400);
 assert.equal((await f.request('/passkey/login/options',{}, {Origin:'https://evil.example'})).response.status,403);
 assert.equal((await f.request('/passkey/login/options',{padding:'x'.repeat(33000)})).response.status,413);
 for(let i=0;i<60;i++) await f.request('/passkey/login/options',{}, {'CF-Connecting-IP':'192.0.2.2'});
 assert.equal((await f.request('/passkey/login/options',{}, {'CF-Connecting-IP':'192.0.2.2'})).response.status,429);
 }finally{await f.mf.dispose();}
});

test('auth-version change during refresh authorization fails once without retry loops or credential destruction',async()=>{
 const f=await fixture();try{
 const d=await f.seed();let changed=false,batches=0;
 const originals=new WeakMap<import('../src/auth.ts').Statement,import('../src/auth.ts').Statement>();
 const wrap=(real:import('../src/auth.ts').Statement,sql:string):import('../src/auth.ts').Statement=>{
 const wrapped:import('../src/auth.ts').Statement={bind:(...args)=>wrap(real.bind(...args),sql),all:<T>()=>real.all<T>(),run:()=>real.run(),first:async<T>()=>{const value=await real.first<T>();if(!changed&&sql.includes('AND ((d.refresh_hash')){changed=true;await f.db.prepare('UPDATE users SET auth_version=2 WHERE id=?').bind(d.accountID).run();}return value;}};
 originals.set(wrapped,real);return wrapped;
 };
 f.env.DB={prepare:sql=>wrap(f.db.prepare(sql),sql),batch:async statements=>{if(++batches>2)throw new Error('Unexpected retry loop');return f.db.batch(statements.map(v=>originals.get(v)??v));}};
 assert.equal((await f.signed('/session/refresh',{requestID:crypto.randomUUID()},d.refreshToken,d.keys)).response.status,401);
 assert.equal(batches,2);
 assert.ok(await f.db.prepare('SELECT id FROM native_devices WHERE id=?').bind(d.deviceID).first());
 }finally{await f.mf.dispose();}
});

test('transient database failure while consuming proof returns 503 and leaves a healthy lease usable',async()=>{
 const f=await fixture();try{
 const d=await f.seed(),database=f.env.DB;
 f.env.DB={prepare:sql=>database.prepare(sql),batch:async()=>{throw new Error('test transient database outage');}};
 assert.equal((await f.signed('/session/current',{},d.accessToken,d.keys)).response.status,503);
 f.env.DB=database;
 assert.equal((await f.signed('/session/current',{},d.accessToken,d.keys)).response.status,200);
 }finally{await f.mf.dispose();}
});

test('fresh MFA is required to revoke another device or delete an account; expired refresh never renews',async()=>{
 const f=await fixture();try{
 const a=await f.seed(),b=await f.seed();
 assert.equal((await f.signed('/session/revoke',{deviceID:b.deviceID},a.accessToken,a.keys)).response.status,401);
 f.advance(301);
 assert.equal((await f.signed('/account/delete',{confirm:'DELETE'},a.accessToken,a.keys)).response.status,401);
 assert.equal((await f.signed('/session/revoke',{deviceID:a.deviceID},a.accessToken,a.keys)).response.status,401);
 f.advance(180*86400);
 assert.equal((await f.signed('/session/refresh',{requestID:crypto.randomUUID()},a.refreshToken,a.keys)).response.status,401);
 assert.ok(await f.db.prepare('SELECT id FROM users WHERE id=?').bind(a.accountID).first());
 }finally{await f.mf.dispose();}
});

import test from 'node:test';
import assert from 'node:assert/strict';
import { z } from 'zod';
import { fixture, origin, dictionary } from './native-fixture.ts';
import { SoftwarePasskey } from './passkey.ts';
import { totp } from '../src/crypto.ts';

test('verified email then actual UV passkey and TOTP are all required before issuing a device session',async()=>{
 let mail='';const f=await fixture(async(input,init)=>{mail=await new Request(input,init).text();return Response.json({MessageId:'test-mail'});});try{
 const d=await f.seed();
 const started=await f.request('/identity/email/start',{email:'New@Example.com',purpose:'enroll'});
 assert.equal(started.response.status,200);assert.ok(!JSON.stringify(started.json).includes('code'));
 const flowToken=z.string().parse(started.json['flowToken']);
 const code=/\b\d{6}\b/.exec(mail)?.[0];assert.ok(code);
 const verified=await f.request('/identity/email/verify',{flowToken,code});assert.equal(verified.response.status,200);
 const identityToken=z.string().parse(verified.json['flowToken']);
 assert.equal((await f.request('/identity/email/verify',{flowToken,code})).response.status,401);
 const options=await f.request('/passkey/enroll/options',{flowToken:identityToken});assert.equal(options.response.status,200);
 const opts=z.object({challenge:z.string(),user:z.object({id:z.string()})}).parse(options.json['options']);
 const key=await SoftwarePasskey.create();
 const pass=await f.request('/passkey/enroll/verify',{flowToken:options.json['flowToken'],credential:await key.registration(opts.challenge,opts.user.id,origin)});assert.equal(pass.response.status,200);
 assert.equal((await f.db.prepare('SELECT COUNT(*) AS n FROM users').first<{n:number}>())?.n,1);
 const invalid=await f.request('/enroll/complete',{flowToken:pass.json['flowToken'],code:await totp(z.string().parse(pass.json['secret']),f.now),deviceKey:{kty:'EC',crv:'P-256',x:'A'.repeat(43),y:'A'.repeat(43)}});assert.equal(invalid.response.status,400);
 const finish=await f.request('/enroll/complete',{flowToken:pass.json['flowToken'],code:await totp(z.string().parse(pass.json['secret']),f.now),deviceKey:d.deviceKey});assert.equal(finish.response.status,200);
 assert.equal(finish.json['authenticated'],true);assert.equal(z.array(z.string()).parse(finish.json['backupCodes']).length,10);
 assert.equal((await f.signed('/session/current',{},z.string().parse(finish.json['accessToken']),d.keys)).response.status,200);
 assert.equal((await f.request('/enroll/complete',{flowToken:pass.json['flowToken'],code:'000000',deviceKey:d.deviceKey})).response.status,401);
 const stored=JSON.stringify((await f.db.prepare('SELECT * FROM native_identities').all()).results);
 assert.ok(!stored.includes('New@Example.com'));assert.ok(!stored.includes('new@example.com'));
 assert.ok(!mail.includes('health'));dictionary.parse(finish.json);
 }finally{await f.mf.dispose();}
});

test('ordinary native login requires a fresh passkey plus TOTP or exactly one spent backup',async()=>{
 const {accountFixture}=await import('./native-fixture.ts');const f=await accountFixture();try {
 const a=await f.enroll();
 const proof=await f.login(a.passkey);assert.equal(proof.response.status,200);assert.equal(proof.json['authenticated'],undefined);
 assert.equal((await f.request('/mfa/complete',{flowToken:proof.json['flowToken'],code:await totp(a.secret,f.now),deviceKey:a.deviceKey})).response.status,401);
 assert.equal((await f.request('/mfa/complete',{flowToken:proof.json['flowToken'],code:'',backupCode:a.backups[0],deviceKey:a.deviceKey})).response.status,401);
 const result=await f.request('/mfa/complete',{flowToken:proof.json['flowToken'],backupCode:a.backups[0],deviceKey:a.deviceKey});assert.equal(result.response.status,200);
 const again=await f.login(a.passkey);
 assert.equal((await f.request('/mfa/complete',{flowToken:again.json['flowToken'],backupCode:a.backups[0],deviceKey:a.deviceKey})).response.status,401);
 assert.equal((await f.request('/mfa/complete',{flowToken:again.json['flowToken'],backupCode:a.backups[1],deviceKey:a.deviceKey})).response.status,200);
 }finally{await f.mf.dispose();}
});

test('abandoned recovery preserves old credentials; completed recovery replaces all factors atomically',async()=>{
 const {accountFixture}=await import('./native-fixture.ts');const f=await accountFixture();try{
 const a=await f.enroll();
 const identity=await f.identity(a.email,'recover');assert.equal(identity.response.status,200);
 const options=await f.request('/recovery/options',{flowToken:identity.json['flowToken'],backupCode:a.backups[0]});assert.equal(options.response.status,200);
 assert.equal((await f.signed('/session/current',{},a.accessToken,a.keys)).response.status,200);
 assert.equal((await f.db.prepare('SELECT COUNT(*) AS n FROM backup_codes').first<{n:number}>())?.n,10);
 const key=await SoftwarePasskey.create(),opts=z.object({challenge:z.string(),user:z.object({id:z.string()})}).parse(options.json['options']);
 const pass=await f.request('/passkey/enroll/verify',{flowToken:options.json['flowToken'],credential:await key.registration(opts.challenge,opts.user.id,origin)});assert.equal(pass.response.status,200);
 const complete=await f.request('/enroll/complete',{flowToken:pass.json['flowToken'],code:await totp(z.string().parse(pass.json['secret']),f.now),deviceKey:a.deviceKey});assert.equal(complete.response.status,200);
 assert.equal(complete.json['accountID'],a.accountID);
 assert.equal((await f.signed('/session/current',{},a.accessToken,a.keys)).response.status,401);
 assert.equal((await f.login(a.passkey)).response.status,401);
 assert.equal((await f.login(key)).response.status,200);
 assert.equal((await f.db.prepare('SELECT COUNT(*) AS n FROM credentials').first<{n:number}>())?.n,1);
 }finally{await f.mf.dispose();}
});

test('identity linking requires fresh authenticated authority and never matches another account by email',async()=>{
 const {accountFixture}=await import('./native-fixture.ts');const f=await accountFixture();try{
 const a=await f.enroll(),b=await f.enroll();
 assert.equal((await f.request('/identity/email/start',{email:'link@example.com',purpose:'link'})).response.status,401);
 const start=await f.signed('/identity/email/start',{email:'link@example.com',purpose:'link'},a.accessToken,a.keys);assert.equal(start.response.status,200);
 const code=/\b\d{6}\b/.exec(f.mails.at(-1)??'')?.[0];
 const verified=await f.request('/identity/email/verify',{flowToken:start.json['flowToken'],code});assert.equal(verified.response.status,200);
 assert.equal((await f.signed('/identity/link/complete',{flowToken:verified.json['flowToken']},b.accessToken,b.keys)).response.status,401);
 assert.equal((await f.signed('/identity/link/complete',{flowToken:verified.json['flowToken']},a.accessToken,a.keys)).response.status,200);
 const conflict=await f.signed('/identity/email/start',{email:a.email,purpose:'link'},b.accessToken,b.keys);assert.equal(conflict.response.status,200);
 const conflictCode=/\b\d{6}\b/.exec(f.mails.at(-1)??'')?.[0];
 assert.equal((await f.request('/identity/email/verify',{flowToken:conflict.json['flowToken'],code:conflictCode})).response.status,401);
 f.advance(301);
 assert.equal((await f.signed('/identity/email/start',{email:'fresh@example.com',purpose:'link'},a.accessToken,a.keys)).response.status,401);
 }finally{await f.mf.dispose();}
});

test('account deletion removes linked partial recovery data',async()=>{
 const {accountFixture}=await import('./native-fixture.ts');const f=await accountFixture();try{
 const a=await f.enroll();assert.equal((await f.identity(a.email,'recover')).response.status,200);
 assert.equal((await f.signed('/account/delete',{confirm:'DELETE'},a.accessToken,a.keys)).response.status,200);
 assert.equal((await f.db.prepare('SELECT COUNT(*) AS n FROM native_flows').first<{n:number}>())?.n,0);
 }finally{await f.mf.dispose();}
});

test('competing recovery completions replace an account once and revoke every old device',async()=>{
 const {accountFixture}=await import('./native-fixture.ts');const f=await accountFixture();try{
 const a=await f.enroll();
 async function prepare() {
 const identity=await f.identity(a.email,'recover');
 const options=await f.request('/recovery/options',{flowToken:identity.json['flowToken'],backupCode:a.backups[0]});
 const opts=z.object({challenge:z.string(),user:z.object({id:z.string()})}).parse(options.json['options']),key=await SoftwarePasskey.create();
 const pass=await f.request('/passkey/enroll/verify',{flowToken:options.json['flowToken'],credential:await key.registration(opts.challenge,opts.user.id,origin)});
 return {flowToken:pass.json['flowToken'],code:await totp(z.string().parse(pass.json['secret']),f.now),deviceKey:a.deviceKey};
 }
 const first=await prepare(),second=await prepare();
 const results=await Promise.all([f.request('/enroll/complete',first),f.request('/enroll/complete',second)]);
 assert.deepEqual(results.map(r=>r.response.status).sort(),[200,401]);
 assert.equal((await f.db.prepare('SELECT auth_version FROM users WHERE id=?').bind(a.accountID).first<{auth_version:number}>())?.auth_version,2);
 assert.equal((await f.db.prepare('SELECT COUNT(*) AS n FROM credentials').first<{n:number}>())?.n,1);
 assert.equal((await f.db.prepare('SELECT COUNT(*) AS n FROM backup_codes').first<{n:number}>())?.n,10);
 assert.equal((await f.signed('/session/refresh',{requestID:crypto.randomUUID()},a.refreshToken,a.keys)).response.status,401);
 }finally{await f.mf.dispose();}
});

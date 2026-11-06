import test from 'node:test';
import assert from 'node:assert/strict';
import { fixture, accountFixture } from './native-fixture.ts';

test('mail verification is five-attempt bounded and no OTP, identity existence or Health content leaks in responses',async()=>{
 const f=await accountFixture();try{
 const a=await f.enroll();
 const existing=await f.request('/identity/email/start',{email:a.email,purpose:'enroll'});
 const absent=await f.request('/identity/email/start',{email:'absent@example.com',purpose:'enroll'});
 assert.equal(existing.response.status,absent.response.status);assert.deepEqual(Object.keys(existing.json).sort(),Object.keys(absent.json).sort());
 const code=/\b\d{6}\b/.exec(f.mails.at(-1)??'')?.[0];assert.ok(code);
 assert.ok(!JSON.stringify(absent.json).includes(code));
 for(let i=0;i<5;i++) assert.equal((await f.request('/identity/email/verify',{flowToken:absent.json['flowToken'],code:'wrong'})).response.status,401);
 assert.equal((await f.request('/identity/email/verify',{flowToken:absent.json['flowToken'],code})).response.status,401);
 const message=JSON.parse(f.mails.at(-1)??'{}');assert.deepEqual(Object.keys(message).sort(),['from','subject','text','to']);assert.ok(!/health|workout|weight|plan|age|profile/i.test(message.text));
 }finally{await f.mf.dispose();}
});
test('missing mail config and failed delivery fail closed and leave no usable flow',async()=>{
 let calls=0;const f=await fixture(async()=>{calls++;return new Response('',{status:503});});try{
 delete f.env.RESEND_API_KEY;
 assert.equal((await f.request('/identity/email/start',{email:'test@example.com',purpose:'enroll'})).response.status,503);assert.equal(calls,0);
 f.env.RESEND_API_KEY='test-only';assert.equal((await f.request('/identity/email/start',{email:'test@example.com',purpose:'enroll'})).response.status,503);assert.equal(calls,1);
 assert.equal((await f.db.prepare('SELECT COUNT(*) AS n FROM native_flows').first<{n:number}>())?.n,0);
 }finally{await f.mf.dispose();}
});
test('atomic ResendFree daily and monthly quotas never send overflow or retry with another provider',async()=>{
 let calls=0;const f=await fixture(async()=>{calls++;return Response.json({id:'fake'});});try{
 const date=new Date(f.now).toISOString();
 await f.db.prepare("WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM n WHERE x<99) INSERT INTO native_mail_reservations SELECT 'seed-'||x,?,?, 'seed',? FROM n").bind(date.slice(0,10),date.slice(0,7),f.now).run();
 const results=await Promise.all(['one','two'].map(v=>f.request('/identity/email/start',{email:v+'@example.com',purpose:'enroll'})));
 assert.deepEqual(results.map(v=>v.response.status).sort(),[200,503]);assert.equal(calls,1);
 await f.db.prepare("WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM n WHERE x<2900) INSERT INTO native_mail_reservations SELECT 'month-'||x,'earlier',?, 'seed',? FROM n").bind(date.slice(0,7),f.now).run();
 f.advance(86400);
 assert.equal((await f.request('/identity/email/start',{email:'next@example.com',purpose:'enroll'})).response.status,503);assert.equal(calls,1);
 }finally{await f.mf.dispose();}
});

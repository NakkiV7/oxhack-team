import test from 'node:test';
import assert from 'node:assert/strict';
import { fixture, accountFixture } from './native-fixture.ts';

const sesConfiguration = {
 AWS_SES_REGION:'eu-west-2', AWS_SES_FROM:'auth@mail.spottr.omarchoudhry.co.uk', AWS_SES_CONFIGURATION_SET:'spottr-auth',
 AWS_SES_ACCESS_KEY_ID:'AKIDEXAMPLE', AWS_SES_SECRET_ACCESS_KEY:'test-only-not-real-secret'
};
test('SES single-request timeout aborts within the native budget and consumes its reservation without retry',async(t)=>{
 let calls=0,receivedAbort=false;
 const f=await fixture(async(input,init)=>{calls++;const request=new Request(input,init);receivedAbort=request.signal.aborted;throw new DOMException('private-timeout-details','TimeoutError');});try{
 Object.assign(f.env,sesConfiguration);
 const timeout=t.mock.method(AbortSignal,'timeout',(milliseconds:number)=>{assert.equal(milliseconds,10000);return AbortSignal.abort(new DOMException('private-timeout-details','TimeoutError'));});
 const result=await f.request('/identity/email/start',{email:'recipient@example.com',purpose:'enroll'});
 assert.equal(timeout.mock.callCount(),1);assert.equal(receivedAbort,true);assert.equal(calls,1);
 assert.equal(result.response.status,503);assert.deepEqual(result.json,{error:'temporarily_unavailable'});
 assert.equal((await f.db.prepare('SELECT COUNT(*) AS n FROM native_flows').first<{n:number}>())?.n,0);
 assert.equal((await f.db.prepare('SELECT COUNT(*) AS n FROM native_mail_reservations').first<{n:number}>())?.n,1);
 }finally{await f.mf.dispose();}
});
test('SES sends one SigV4 signed London request through the injected fetch seam with redirects rejected',async()=>{
 const requests:Request[]=[];
 const f=await fixture(async(input,init)=>{requests.push(new Request(input,init));return Response.json({MessageId:'test-ses-message'});});try{
 Object.assign(f.env,sesConfiguration,{AWS_SES_SESSION_TOKEN:'test-only-session-token'});
 assert.equal((await f.request('/identity/email/start',{email:'recipient@example.com',purpose:'enroll'})).response.status,200);
 assert.equal(requests.length,1);const request=requests[0];assert.ok(request);
 assert.equal(request.url,'https://email.eu-west-2.amazonaws.com/v2/email/outbound-emails');
 assert.equal(request.method,'POST');assert.equal(request.redirect,'manual');
 assert.match(request.headers.get('Authorization')??'',/^AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE\/\d{8}\/eu-west-2\/ses\/aws4_request,/);
 assert.equal(request.headers.get('X-Amz-Security-Token'),'test-only-session-token');
 assert.match(request.headers.get('X-Amz-Date')??'',/^\d{8}T\d{6}Z$/);
 assert.equal(request.headers.get('Content-Type'),'application/json');
 }finally{await f.mf.dispose();}
});
test('SES simple UTF8 content has one recipient and only the requested ownership code',async()=>{
 let content='';const f=await fixture(async(input,init)=>{content=await new Request(input,init).text();return Response.json({MessageId:'test-ses-message'});});try{
 Object.assign(f.env,sesConfiguration);
 const result=await f.request('/identity/email/start',{email:'recipient@example.com',purpose:'enroll'});
 assert.equal(result.response.status,200);
 const code=/\b\d{6}\b/.exec(content)?.[0];assert.ok(code);
 assert.deepEqual(JSON.parse(content),{FromEmailAddress:sesConfiguration.AWS_SES_FROM,Destination:{ToAddresses:['recipient@example.com']},ConfigurationSetName:'spottr-auth',Content:{Simple:{Subject:{Charset:'UTF-8',Data:'Your Spottr verification code'},Body:{Text:{Charset:'UTF-8',Data:`Your Spottr verification code is ${code}. It expires in five minutes. If you did not request this, ignore this email.`}}}}});
 assert.ok(!JSON.stringify(result.json).includes(code));
 assert.equal((await f.request('/identity/email/verify',{flowToken:result.json['flowToken'],code})).response.status,200);
 }finally{await f.mf.dispose();}
});
test('SES missing or mismatched dedicated configuration fails closed before sending or reserving mail',async()=>{
 let calls=0;const f=await fixture(async()=>{calls++;return Response.json({MessageId:'test-ses-message'});});try{
 for(const [key,value] of [['AWS_SES_ACCESS_KEY_ID',''],['AWS_SES_SECRET_ACCESS_KEY',''],['AWS_SES_REGION','us-east-1'],['AWS_SES_FROM','other@example.com'],['AWS_SES_CONFIGURATION_SET','rise-default']]) {
  Object.assign(f.env,sesConfiguration,{[key??'']:value});
  const result=await f.request('/identity/email/start',{email:'recipient@example.com',purpose:'enroll'});
  assert.equal(result.response.status,503);assert.deepEqual(result.json,{error:'temporarily_unavailable'});
 }
 assert.equal(calls,0);
 assert.equal((await f.db.prepare('SELECT COUNT(*) AS n FROM native_flows').first<{n:number}>())?.n,0);
 assert.equal((await f.db.prepare('SELECT COUNT(*) AS n FROM native_mail_reservations').first<{n:number}>())?.n,0);
 }finally{await f.mf.dispose();}
});
test('SES malformed acceptance and provider failures consume one reservation with no retry or usable flow',async()=>{
 const responses=[()=>Response.json({}),()=>Response.json({MessageId:''}),()=>Response.json({MessageId:123}),()=>new Response('not JSON'),()=>new Response('x'.repeat(5000)),()=>Response.json({error:'sensitive-provider-body'},{status:429}),()=>Response.json({error:'sensitive-provider-body'},{status:503}),()=>new Response('',{status:302,headers:{Location:'https://other.example/secret'}}),()=>{throw new TypeError('sensitive-provider-body');}];
 let calls=0;const f=await fixture(async()=>{const response=responses[calls++];assert.ok(response);return response();});try{
 Object.assign(f.env,sesConfiguration);
 for(let index=0;index<responses.length;index++) {
  const result=await f.request('/identity/email/start',{email:`recipient${index}@example.com`,purpose:'enroll'});
  assert.equal(result.response.status,503);assert.deepEqual(result.json,{error:'temporarily_unavailable'});
  assert.equal(calls,index+1);
  assert.equal((await f.db.prepare('SELECT COUNT(*) AS n FROM native_flows').first<{n:number}>())?.n,0);
  assert.equal((await f.db.prepare('SELECT COUNT(*) AS n FROM native_mail_reservations').first<{n:number}>())?.n,index+1);
 }
 }finally{await f.mf.dispose();}
});

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
 const message:unknown=JSON.parse(f.mails.at(-1)??'{}');assert.ok(message&&typeof message==='object');assert.deepEqual(Object.keys(message).sort(),['ConfigurationSetName','Content','Destination','FromEmailAddress']);assert.ok(!/health|workout|weight|plan|age|profile/i.test(JSON.stringify(message)));
 }finally{await f.mf.dispose();}
});
test('missing mail config and failed delivery fail closed and leave no usable flow',async()=>{
 let calls=0;const f=await fixture(async()=>{calls++;return new Response('',{status:503});});try{
 delete f.env.AWS_SES_ACCESS_KEY_ID;
 assert.equal((await f.request('/identity/email/start',{email:'test@example.com',purpose:'enroll'})).response.status,503);assert.equal(calls,0);
 f.env.AWS_SES_ACCESS_KEY_ID='AKIDEXAMPLE';assert.equal((await f.request('/identity/email/start',{email:'test@example.com',purpose:'enroll'})).response.status,503);assert.equal(calls,1);
 assert.equal((await f.db.prepare('SELECT COUNT(*) AS n FROM native_flows').first<{n:number}>())?.n,0);
 }finally{await f.mf.dispose();}
});
test('atomic daily and monthly mail quotas never send overflow or retry with another provider',async()=>{
 let calls=0;const f=await fixture(async()=>{calls++;return Response.json({MessageId:'test-mail'});});try{
 const date=new Date(f.now).toISOString();
 await f.db.prepare("WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM n WHERE x<99) INSERT INTO native_mail_reservations SELECT 'seed-'||x,?,?, 'seed',? FROM n").bind(date.slice(0,10),date.slice(0,7),f.now).run();
 const results=await Promise.all(['one','two'].map(v=>f.request('/identity/email/start',{email:v+'@example.com',purpose:'enroll'})));
 assert.deepEqual(results.map(v=>v.response.status).sort(),[200,503]);assert.equal(calls,1);
 await f.db.prepare("WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM n WHERE x<2900) INSERT INTO native_mail_reservations SELECT 'month-'||x,'earlier',?, 'seed',? FROM n").bind(date.slice(0,7),f.now).run();
 f.advance(86400);
 assert.equal((await f.request('/identity/email/start',{email:'next@example.com',purpose:'enroll'})).response.status,503);assert.equal(calls,1);
 }finally{await f.mf.dispose();}
});
test('concurrent ambiguous sends consume the three-per-recipient hourly budget before networking',async()=>{
 let calls=0;const f=await fixture(async()=>{
  calls++;
  assert.ok(((await f.db.prepare('SELECT COUNT(*) AS n FROM native_mail_reservations').first<{n:number}>())?.n??0)>0);
  throw new TypeError('ambiguous delivery');
 });try{
 const results=await Promise.all(Array.from({length:4},()=>f.request('/identity/email/start',{email:'recipient@example.com',purpose:'enroll'})));
 assert.ok(results.every(result=>result.response.status===503));assert.equal(calls,3);
 assert.equal((await f.db.prepare('SELECT COUNT(*) AS n FROM native_mail_reservations').first<{n:number}>())?.n,3);
 assert.equal((await f.db.prepare('SELECT COUNT(*) AS n FROM native_flows').first<{n:number}>())?.n,0);
 }finally{await f.mf.dispose();}
});

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { Miniflare, type Request as RuntimeRequest } from 'miniflare';
import { randomToken } from '../src/crypto.ts';
import { context, type NativeEnv } from '../src/native-sessions.ts';

async function withRuntime(action:()=>Promise<void>) {
 const requireWrangler=createRequire(import.meta.resolve('wrangler'));
 const runtime:unknown=requireWrangler('workerd');assert.ok(runtime&&typeof runtime==='object'&&'default'in runtime&&typeof runtime.default==='string');
 const previousRuntime=process.env.MINIFLARE_WORKERD_PATH;
 process.env.MINIFLARE_WORKERD_PATH=runtime.default;
 try {await action();} finally {if(previousRuntime===undefined) delete process.env.MINIFLARE_WORKERD_PATH;else process.env.MINIFLARE_WORKERD_PATH=previousRuntime;}
}

for(const providerStatus of [200,503,302]) test(`actual workerd native default transport reaches SES and handles provider ${providerStatus}`,async()=>withRuntime(async()=>{
 const bundle=await build({absWorkingDir:fileURLToPath(new URL('../',import.meta.url)),entryPoints:['src/index.ts'],bundle:true,write:false,format:'esm',platform:'neutral',mainFields:['browser','module','main'],conditions:['workerd','worker','browser'],external:['node:*']});
 const script=bundle.outputFiles[0]?.text;assert.ok(script);
 let upstreamCalls=0,code:string|undefined,signed=false;
 const origin='https://spottr.example';
 const mf=new Miniflare({cf:false,modules:true,script,compatibilityDate:'2026-11-05',compatibilityFlags:['nodejs_compat'],d1Databases:['DB'],bindings:{
  ORIGIN:origin,AUTH_ENCRYPTION_KEY:randomToken(),AUTH_TOKEN_PEPPER:randomToken(),AWS_SES_REGION:'eu-west-2',AWS_SES_FROM:'auth@mail.spottr.omarchoudhry.co.uk',AWS_SES_CONFIGURATION_SET:'spottr-auth',AWS_SES_ACCESS_KEY_ID:'AKIDEXAMPLE',AWS_SES_SECRET_ACCESS_KEY:'test-only-not-real-secret'
 },outboundService:async(request:RuntimeRequest)=>{
  upstreamCalls++;assert.equal(request.url,'https://email.eu-west-2.amazonaws.com/v2/email/outbound-emails');
  signed=/^AWS4-HMAC-SHA256 /.test(request.headers.get('Authorization')??'');
  code=/\b\d{6}\b/.exec(await request.text())?.[0];
  if(providerStatus===302) return new Response('',{status:302,headers:{Location:'https://redirect.invalid/must-not-follow'}});
  return Response.json(providerStatus===200?{MessageId:'test-ses-message'}:{error:'private-provider-details'},{status:providerStatus});
 }});
 try {
  const db=await mf.getD1Database('DB');
  for(const migration of ['0001_accounts.sql','0002_native_accounts.sql','0003_analytics.sql']) await db.exec((await readFile(new URL('../migrations/'+migration,import.meta.url),'utf8')).replace(/\n/g,' '));
  const response=await mf.dispatchFetch(origin+'/api/native/v1/identity/email/start',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email:'recipient@example.com',purpose:'enroll'})});
  const reservations=(await db.prepare('SELECT COUNT(*) AS n FROM native_mail_reservations').first<{n:number}>())?.n;
  const flows=(await db.prepare('SELECT COUNT(*) AS n FROM native_flows').first<{n:number}>())?.n;
  console.log(JSON.stringify({realm:'workerd',compatibilityDate:'2026-11-05',providerStatus,status:response.status,upstreamCalls,reservations,flows}));
  assert.equal(response.status,providerStatus===200?200:503);
  assert.equal(upstreamCalls,1);assert.equal(signed,true);assert.equal(reservations,1);
  const result:unknown=await response.json();assert.ok(result&&typeof result==='object');
  if(providerStatus===200) {
   assert.equal(flows,1);assert.ok('flowToken'in result);assert.ok(code);
   assert.ok(!JSON.stringify(result).includes(code));
   const verification=await mf.dispatchFetch(origin+'/api/native/v1/identity/email/verify',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({flowToken:result.flowToken,code})});
   assert.equal(verification.status,200);
  } else {assert.equal(flows,0);assert.deepEqual(result,{error:'temporarily_unavailable'});}
 } finally {
  await mf.dispose();
 }
}));

test('actual workerd context safely forwards explicitly supplied global fetch used by legacy revocation',async()=>withRuntime(async()=>{
 const bundle=await build({absWorkingDir:fileURLToPath(new URL('../',import.meta.url)),stdin:{contents:"import{context}from'./src/native-sessions.ts';export default{async fetch(request,env){const c=context(env,{fetch});try{return await c.fetch('https://appleid.apple.com/auth/revoke',{method:'POST',body:'test-only'});}catch{return new Response('receiver rejected',{status:500});}}}",resolveDir:fileURLToPath(new URL('../',import.meta.url)),loader:'ts'},bundle:true,write:false,format:'esm',platform:'neutral',mainFields:['browser','module','main'],conditions:['workerd','worker','browser'],external:['node:*']});
 const script=bundle.outputFiles[0]?.text;assert.ok(script);let calls=0;
 const mf=new Miniflare({cf:false,modules:true,script,compatibilityDate:'2026-11-05',compatibilityFlags:['nodejs_compat'],outboundService:async(request:RuntimeRequest)=>{calls++;assert.equal(request.url,'https://appleid.apple.com/auth/revoke');assert.equal(request.method,'POST');assert.equal(await request.text(),'test-only');return new Response('fake provider result');}});
 try {const response=await mf.dispatchFetch('https://local.invalid/');assert.equal(response.status,200);assert.equal(calls,1);assert.equal(await response.text(),'fake provider result');}finally{await mf.dispose();}
}));
test('context preserves injected fetch arguments and promise without mutating global fetch',async()=>{
 const env:NativeEnv={ORIGIN:'https://local.invalid',AUTH_ENCRYPTION_KEY:'unused',AUTH_TOKEN_PEPPER:'unused',DB:{prepare(){throw new Error('Fetch delegation must not touch D1');},batch(){throw new Error('Fetch delegation must not touch D1');}}};
  const original=globalThis.fetch,request=new Request('https://local.invalid/'),result=Promise.resolve(new Response('test-only'));
  let seen:Parameters<typeof fetch>|undefined;
  const injected:typeof fetch=(...args)=>{seen=args;return result;};
  const c=context(env,{fetch:injected});assert.equal(c.fetch(request),result);assert.deepEqual(seen,[request]);assert.equal(globalThis.fetch,original);
});

import test from 'node:test';
import assert from 'node:assert/strict';
import { z } from 'zod';
import { accountFixture, fixture, origin, digest } from './native-fixture.ts';
import { bytesToBase64URL, base64URLToBytes, randomToken, totp } from '../src/crypto.ts';
import { SoftwarePasskey } from './passkey.ts';

test('real WebAuthn rejects UV, origin, RP, challenge and signature violations',async()=>{
 const f=await accountFixture();try{
 const a=await f.enroll();
 for(const variant of ['uv','origin','rp','challenge','signature']) {
  const start=await f.request('/passkey/login/options',{}),options=z.object({challenge:z.string()}).parse(start.json['options']);
  const credential=await a.passkey.authentication(variant==='challenge'?randomToken():options.challenge,variant==='origin'||variant==='rp'?'https://evil.example':origin,variant!=='uv');
  const body=variant==='signature'?{...credential,response:{...credential.response,signature:bytesToBase64URL(new Uint8Array(64).fill(7))}}:variant==='rp'?{...credential,response:{...credential.response,clientDataJSON:bytesToBase64URL(new TextEncoder().encode(JSON.stringify({type:'webauthn.get',challenge:options.challenge,origin,crossOrigin:false})))}}:credential;
  assert.equal((await f.request('/passkey/login/verify',{flowToken:start.json['flowToken'],credential:body})).response.status,401,variant);
 }
 const proof=await f.login(a.passkey);for(let i=0;i<5;i++) assert.equal((await f.request('/mfa/complete',{flowToken:proof.json['flowToken'],code:'bad',deviceKey:a.deviceKey})).response.status,401);
 assert.equal((await f.request('/mfa/complete',{flowToken:proof.json['flowToken'],backupCode:a.backups[0],deviceKey:a.deviceKey})).response.status,401);
 }finally{await f.mf.dispose();}
});

test('device P-256 proof binds exact method/path/body/token/challenge/nonce/time and cannot be replayed',async()=>{
 const f=await fixture();try{
 const a=await f.seed();
 async function signedRequest(reusedNonce?:string) {
 const ch=await f.request('/session/challenge',{token:a.accessToken}),challenge=z.string().parse(ch.json['challenge']),nonce=reusedNonce??randomToken(),issuedAt=new Date(f.now).toISOString();
 const body='{}',path='/api/native/v1/session/current';
 const canonical=['spottr-native-v1','POST',path,await digest(body),await digest(a.accessToken),challenge,nonce,issuedAt].join('\n');
 const signature=bytesToBase64URL(new Uint8Array(await crypto.subtle.sign({name:'ECDSA',hash:'SHA-256'},a.keys.privateKey,new TextEncoder().encode(canonical))));
 return {path,body,proof:{challenge,nonce,issuedAt,signature},headers:{'Content-Type':'application/json',Authorization:'Bearer '+a.accessToken}};
 }
 for(const variant of ['method','path','body','token','challenge','nonce','time','signature']) {
 const s=await signedRequest(),proof={...s.proof};
 if(variant==='challenge')proof.challenge=randomToken();if(variant==='nonce')proof.nonce=randomToken();if(variant==='time')proof.issuedAt=new Date(f.now-120000).toISOString();if(variant==='signature')proof.signature=bytesToBase64URL(new Uint8Array(64));
 const response=await f.handler()(new Request(origin+(variant==='path'?'/api/native/v1/session/sign-out':s.path),{method:variant==='method'?'PUT':'POST',headers:{...s.headers,Authorization:'Bearer '+(variant==='token'?randomToken():a.accessToken),'X-Spottr-Proof':JSON.stringify(proof)},body:variant==='body'?'{ }':s.body}));
 assert.ok([401,404].includes(response.status),variant);
 }
 const s=await signedRequest(),request=new Request(origin+s.path,{method:'POST',headers:{...s.headers,'X-Spottr-Proof':JSON.stringify(s.proof)},body:s.body});
 assert.equal((await f.handler()(request.clone())).status,200);assert.equal((await f.handler()(request.clone())).status,401);
 const duplicate=await signedRequest(s.proof.nonce);
 assert.equal((await f.handler()(new Request(origin+duplicate.path,{method:'POST',headers:{...duplicate.headers,'X-Spottr-Proof':JSON.stringify(duplicate.proof)},body:duplicate.body}))).status,401);
 const wrong=await crypto.subtle.generateKey({name:'ECDSA',namedCurve:'P-256'},true,['sign','verify']);assert.equal((await f.signed('/session/current',{},a.accessToken,wrong)).response.status,401);
 f.advance(901);assert.equal((await f.signed('/session/current',{},a.accessToken,a.keys)).response.status,401);
 assert.equal((await f.signed('/session/refresh',{requestID:crypto.randomUUID()},a.refreshToken,a.keys)).response.status,200);
 }finally{await f.mf.dispose();}
});

test('concurrent backup completion grants one session; failed atomic recovery preserves original credentials',async()=>{
 const f=await accountFixture();try{
 const a=await f.enroll(),first=await f.login(a.passkey),second=await f.login(a.passkey);
 const outcomes=await Promise.all([first,second].map(proof=>f.request('/mfa/complete',{flowToken:proof.json['flowToken'],backupCode:a.backups[0],deviceKey:a.deviceKey})));
 assert.deepEqual(outcomes.map(v=>v.response.status).sort(),[200,401]);
 const identity=await f.identity(a.email,'recover'),options=await f.request('/recovery/options',{flowToken:identity.json['flowToken'],backupCode:a.backups[1]});
 const opts=z.object({challenge:z.string(),user:z.object({id:z.string()})}).parse(options.json['options']),passkey=await SoftwarePasskey.create();
 const pass=await f.request('/passkey/enroll/verify',{flowToken:options.json['flowToken'],credential:await passkey.registration(opts.challenge,opts.user.id,origin)});
 await f.db.exec("CREATE TRIGGER test_fail_recovery BEFORE INSERT ON credentials BEGIN SELECT RAISE(ABORT,'test rollback'); END;");
 const completed=await f.request('/enroll/complete',{flowToken:pass.json['flowToken'],code:await totp(z.string().parse(pass.json['secret']),f.now),deviceKey:a.deviceKey});assert.equal(completed.response.status,503);
 assert.equal((await f.db.prepare('SELECT auth_version FROM users WHERE id=?').bind(a.accountID).first<{auth_version:number}>())?.auth_version,1);
 assert.equal((await f.signed('/session/current',{},a.accessToken,a.keys)).response.status,200);
 assert.equal((await f.login(a.passkey)).response.status,200);
 }finally{await f.mf.dispose();}
});

test('expired partial enrolment and abandoned recovery cannot create or alter accounts',async()=>{
 const f=await accountFixture();try{
 const a=await f.enroll(),identity=await f.identity(a.email,'recover');f.advance(300);
 assert.equal((await f.request('/recovery/options',{flowToken:identity.json['flowToken'],backupCode:a.backups[0]})).response.status,401);
 assert.equal((await f.login(a.passkey)).response.status,200);
 const fresh=await f.identity('new@example.com'),options=await f.request('/passkey/enroll/options',{flowToken:fresh.json['flowToken']}),opts=z.object({challenge:z.string(),user:z.object({id:z.string()})}).parse(options.json['options']);
 const key=await SoftwarePasskey.create();const pass=await f.request('/passkey/enroll/verify',{flowToken:options.json['flowToken'],credential:await key.registration(opts.challenge,opts.user.id,origin)});
 f.advance(300);
 assert.equal((await f.request('/enroll/complete',{flowToken:pass.json['flowToken'],code:await totp(z.string().parse(pass.json['secret']),f.now),deviceKey:a.deviceKey})).response.status,401);
 assert.equal((await f.db.prepare('SELECT COUNT(*) AS n FROM users').first<{n:number}>())?.n,1);
 assert.ok(base64URLToBytes(opts.user.id).length>0);
 }finally{await f.mf.dispose();}
});

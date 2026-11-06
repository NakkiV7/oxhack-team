import test from 'node:test';
import assert from 'node:assert/strict';
import { fixture, accountFixture, origin } from './native-fixture.ts';
import { createAuthHandler } from '../src/auth.ts';
import { randomToken, hashToken, encryptSecret, bytesToBase64URL } from '../src/crypto.ts';
async function websiteSession(f:Awaited<ReturnType<typeof fixture>>,accountID:string) {
 const raw=randomToken(),hash=await hashToken('session:'+raw,f.env.AUTH_TOKEN_PEPPER);
 await f.db.prepare('INSERT INTO sessions VALUES(?,?,?,?,?)').bind(hash,accountID,1,f.now,f.now+600000).run();
 return {Origin:origin,Cookie:'__Host-spottr_session='+raw,'X-Spottr-CSRF':await hashToken('csrf:'+raw,f.env.AUTH_TOKEN_PEPPER),'Content-Type':'application/json'};
}
test('a fresh website MFA session can explicitly link verified email and a stale session cannot',async()=>{
 const f=await accountFixture();try{
 const a=await f.seed(),headers=await websiteSession(f,a.accountID);
 const start=await f.request('/identity/email/start',{email:'legacy@example.com',purpose:'link'},headers);assert.equal(start.response.status,200);
 const code=/\b\d{6}\b/.exec(f.mails.at(-1)??'')?.[0];
 const verified=await f.request('/identity/email/verify',{flowToken:start.json['flowToken'],code});assert.equal(verified.response.status,200);
 assert.equal((await f.request('/identity/link/complete',{flowToken:verified.json['flowToken']},headers)).response.status,200);
 f.advance(301);assert.equal((await f.request('/identity/email/start',{email:'stale@example.com',purpose:'link'},headers)).response.status,401);
 }finally{await f.mf.dispose();}
});
test('legacy website deletion revokes linked Apple grant and fails closed on provider failure',async()=>{
 const f=await fixture();try{
 const a=await f.seed(),headers=await websiteSession(f,a.accountID);
 const key=await crypto.subtle.generateKey({name:'ECDSA',namedCurve:'P-256'},true,['sign','verify']);
 Object.assign(f.env,{APPLE_CLIENT_ID:'com.example.spottr',APPLE_TEAM_ID:'TESTTEAM01',APPLE_KEY_ID:'TESTKEY001',APPLE_PRIVATE_KEY:bytesToBase64URL(new Uint8Array(await crypto.subtle.exportKey('pkcs8',key.privateKey)))});
 await f.db.prepare('INSERT INTO native_identities VALUES(?,?,?,?)').bind('apple','test-subject',a.accountID,await encryptSecret('test-provider-refresh',f.env.AUTH_ENCRYPTION_KEY,'apple:test-subject')).run();
 let calls=0,ok=false;
 const handler=createAuthHandler(f.env,()=>f.now,async(url,init)=>{calls++;assert.equal(String(url),'https://appleid.apple.com/auth/revoke');assert.equal(new URLSearchParams(String(init?.body)).get('token'),'test-provider-refresh');return new Response('',{status:ok?200:503});});
 const request=()=>new Request(origin+'/api/account/delete',{method:'POST',headers,body:JSON.stringify({confirm:'DELETE'})});
 assert.equal((await handler(request())).status,503);assert.equal(calls,1);assert.ok(await f.db.prepare('SELECT id FROM users WHERE id=?').bind(a.accountID).first());
 ok=true;assert.equal((await handler(request())).status,200);assert.equal(calls,2);assert.equal(await f.db.prepare('SELECT id FROM users WHERE id=?').bind(a.accountID).first(),null);
 }finally{await f.mf.dispose();}
});

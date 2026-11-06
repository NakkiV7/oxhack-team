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

for(const surface of ['native','legacy']) for(const change of ['new-link','replacement']) {
 test(`${surface} deletion retains a ${change} grant linked during revocation and revokes it on retry`,async()=>{
 let duringRevoke:(()=>Promise<void>)|undefined;
 const revoked:string[]=[];
 const fetcher:typeof fetch=async(url,init)=>{
 assert.equal(String(url),'https://appleid.apple.com/auth/revoke');
 const token=new URLSearchParams(String(init?.body)).get('token');assert.ok(token);revoked.push(token);
 const action=duringRevoke;duringRevoke=undefined;if(action) await action();
 return new Response('',{status:200});
 };
 const f=await fixture(fetcher);try{
 const a=await f.seed(),headers=await websiteSession(f,a.accountID);
 const key=await crypto.subtle.generateKey({name:'ECDSA',namedCurve:'P-256'},true,['sign','verify']);
 Object.assign(f.env,{APPLE_CLIENT_ID:'com.example.spottr',APPLE_TEAM_ID:'TESTTEAM01',APPLE_KEY_ID:'TESTKEY001',APPLE_PRIVATE_KEY:bytesToBase64URL(new Uint8Array(await crypto.subtle.exportKey('pkcs8',key.privateKey)))});
 const oldSubject='existing-subject',newSubject=change==='new-link'?'new-subject':oldSubject;
 await f.db.prepare('INSERT INTO native_identities VALUES(?,?,?,?)').bind('apple',oldSubject,a.accountID,await encryptSecret('old-test-grant',f.env.AUTH_ENCRYPTION_KEY,'apple:'+oldSubject)).run();
 const {newFlow}=await import('../src/identity.ts'),{context}=await import('../src/native-sessions.ts');
 const cipher=await encryptSecret('new-test-grant',f.env.AUTH_ENCRYPTION_KEY,'apple:'+newSubject);
 const pending=await newFlow(context(f.env,{clock:()=>f.now}),'identity',{provider:'apple',subject:newSubject,purpose:'link',userID:a.accountID,authVersion:1,providerCipher:cipher,linkSession:'native:'+await hashToken('native:access:'+a.accessToken,f.env.AUTH_TOKEN_PEPPER)});
 await f.db.prepare('UPDATE native_flows SET user_id=? WHERE id=?').bind(a.accountID,await hashToken('flow:'+pending.flowToken,f.env.AUTH_TOKEN_PEPPER)).run();
 duringRevoke=async()=>{const linked=await f.signed('/identity/link/complete',{flowToken:pending.flowToken},a.accessToken,a.keys);assert.equal(linked.response.status,200);};
 const legacy=createAuthHandler(f.env,()=>f.now,fetcher);
 const remove=async()=>surface==='native'?(await f.signed('/account/delete',{confirm:'DELETE'},a.accessToken,a.keys)).response:legacy(new Request(origin+'/api/account/delete',{method:'POST',headers,body:JSON.stringify({confirm:'DELETE'})}));
 assert.equal((await remove()).status,503);
 assert.deepEqual(revoked,['old-test-grant']);
 assert.ok(await f.db.prepare('SELECT id FROM users WHERE id=?').bind(a.accountID).first());
 assert.equal((await f.db.prepare('SELECT provider_cipher FROM native_identities WHERE provider=? AND subject=? AND user_id=?').bind('apple',newSubject,a.accountID).first<{provider_cipher:string}>())?.provider_cipher,cipher);
 assert.equal((await f.signed('/session/current',{},a.accessToken,a.keys)).response.status,200);
 assert.equal((await remove()).status,200);
 assert.ok(revoked.includes('new-test-grant'));
 assert.equal(await f.db.prepare('SELECT id FROM users WHERE id=?').bind(a.accountID).first(),null);
 }finally{await f.mf.dispose();}
 });
}

for(const surface of ['native','legacy']) test(`${surface} deletion rechecks MFA freshness after provider I/O`,async()=>{
 let advance:()=>void=()=>{};
 const fetcher:typeof fetch=async()=>{advance();return new Response('',{status:200});};
 const f=await fixture(fetcher);try{
 const a=await f.seed(),headers=await websiteSession(f,a.accountID);
 const key=await crypto.subtle.generateKey({name:'ECDSA',namedCurve:'P-256'},true,['sign','verify']);
 Object.assign(f.env,{APPLE_CLIENT_ID:'com.example.spottr',APPLE_TEAM_ID:'TESTTEAM01',APPLE_KEY_ID:'TESTKEY001',APPLE_PRIVATE_KEY:bytesToBase64URL(new Uint8Array(await crypto.subtle.exportKey('pkcs8',key.privateKey)))});
 await f.db.prepare('INSERT INTO native_identities VALUES(?,?,?,?)').bind('apple','test-subject',a.accountID,await encryptSecret('test-grant',f.env.AUTH_ENCRYPTION_KEY,'apple:test-subject')).run();
 advance=()=>f.advance(301);
 const response=surface==='native'?(await f.signed('/account/delete',{confirm:'DELETE'},a.accessToken,a.keys)).response:await createAuthHandler(f.env,()=>f.now,fetcher)(new Request(origin+'/api/account/delete',{method:'POST',headers,body:JSON.stringify({confirm:'DELETE'})}));
 assert.equal(response.status,401);assert.ok(await f.db.prepare('SELECT id FROM users WHERE id=?').bind(a.accountID).first());
 }finally{await f.mf.dispose();}
});

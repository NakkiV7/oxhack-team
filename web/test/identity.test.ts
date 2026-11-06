import test from 'node:test';
import assert from 'node:assert/strict';
import { z } from 'zod';
import { fixture } from './native-fixture.ts';
import { bytesToBase64URL, base64URLToBytes } from '../src/crypto.ts';
const encode=(value:unknown)=>bytesToBase64URL(new TextEncoder().encode(JSON.stringify(value)));
test('Apple bootstrap verifies actual RSA signatures, exact nonce, issuer, audience and expiry before exchanging code',async()=>{
 const signing=await crypto.subtle.generateKey({name:'RSASSA-PKCS1-v1_5',modulusLength:2048,publicExponent:new Uint8Array([1,0,1]),hash:'SHA-256'},true,['sign','verify']);
 const appleKey={...await crypto.subtle.exportKey('jwk',signing.publicKey),kid:'apple-test',alg:'RS256',use:'sig'};
 const client=await crypto.subtle.generateKey({name:'ECDSA',namedCurve:'P-256'},true,['sign','verify']);
 const pkcs8=bytesToBase64URL(new Uint8Array(await crypto.subtle.exportKey('pkcs8',client.privateKey)));
 let exchanged='',exchanges=0;
 const f=await fixture(async(url,init)=>{
  if(String(url).endsWith('/auth/keys')) return Response.json({keys:[appleKey]});
  if(String(url).endsWith('/auth/token')) {
 const secret=new URLSearchParams(String(init?.body)).get('client_secret')??'';
 const parts=secret.split('.');assert.equal(parts.length,3);
 assert.ok(await crypto.subtle.verify({name:'ECDSA',hash:'SHA-256'},client.publicKey,base64URLToBytes(parts[2]??''),new TextEncoder().encode(parts.slice(0,2).join('.'))));
 const claims=JSON.parse(new TextDecoder().decode(base64URLToBytes(parts[1]??'')));
 assert.equal(claims.iss,'TESTTEAM01');assert.equal(claims.sub,'com.example.spottr');assert.equal(claims.aud,'https://appleid.apple.com');
 exchanges++;assert.equal(new URLSearchParams(String(init?.body)).get('grant_type'),'authorization_code');return Response.json({id_token:exchanged,refresh_token:'test-apple-refresh'});}
  return new Response('',{status:500});
 });try{
 Object.assign(f.env,{APPLE_CLIENT_ID:'com.example.spottr',APPLE_TEAM_ID:'TESTTEAM01',APPLE_KEY_ID:'TESTKEY001',APPLE_PRIVATE_KEY:'-----BEGIN PRIVATE KEY-----\n'+pkcs8+'\n-----END PRIVATE KEY-----'});
 async function jwt(nonce:string,overrides:Record<string,unknown>={}) {
  const unsigned=encode({alg:'RS256',kid:'apple-test'})+'.'+encode({iss:'https://appleid.apple.com',aud:'com.example.spottr',sub:'apple-user',nonce,iat:Math.floor(f.now/1000),exp:Math.floor(f.now/1000)+300,...overrides});
  return unsigned+'.'+bytesToBase64URL(new Uint8Array(await crypto.subtle.sign('RSASSA-PKCS1-v1_5',signing.privateKey,new TextEncoder().encode(unsigned))));
 }
 for(const bad of [{aud:'wrong'},{iss:'https://evil.example'},{nonce:'wrong'},{exp:1},{iat:Math.floor(f.now/1000)+120}]) {
  const start=await f.request('/identity/apple/start',{purpose:'enroll'});assert.equal(start.response.status,200);
  const token=await jwt(z.string().parse(start.json['nonce']),bad);
  assert.equal((await f.request('/identity/apple/verify',{flowToken:start.json['flowToken'],identityToken:token,authorizationCode:'test-code'})).response.status,401);
 }
 const invalidStart=await f.request('/identity/apple/start',{purpose:'enroll'});
 const invalidToken=(await jwt(z.string().parse(invalidStart.json['nonce']))).split('.').slice(0,2).join('.')+'.'+bytesToBase64URL(new Uint8Array(256));
 assert.equal((await f.request('/identity/apple/verify',{flowToken:invalidStart.json['flowToken'],identityToken:invalidToken,authorizationCode:'invalid-code'})).response.status,401);
 assert.equal(exchanges,0);
 const start=await f.request('/identity/apple/start',{purpose:'enroll'});exchanged=await jwt(z.string().parse(start.json['nonce']));
 const body={flowToken:start.json['flowToken'],identityToken:exchanged,authorizationCode:'test-code'};
 assert.equal((await f.request('/identity/apple/verify',body)).response.status,200);
 assert.equal((await f.request('/identity/apple/verify',body)).response.status,401);assert.equal(exchanges,1);
 const mismatch=await f.request('/identity/apple/start',{purpose:'enroll'});
 const nonce=z.string().parse(mismatch.json['nonce']),supplied=await jwt(nonce);exchanged=await jwt(nonce,{sub:'different-subject'});
 assert.equal((await f.request('/identity/apple/verify',{flowToken:mismatch.json['flowToken'],identityToken:supplied,authorizationCode:'mismatched-code'})).response.status,401);
 assert.equal((await f.db.prepare('SELECT COUNT(*) AS n FROM users').first<{n:number}>())?.n,0);
 }finally{await f.mf.dispose();}
});

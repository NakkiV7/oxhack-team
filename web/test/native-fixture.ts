import { readFile } from 'node:fs/promises';
import { Miniflare } from 'miniflare';
import { z } from 'zod';
import { createNativeAuthHandler, type NativeEnv } from '../src/native-auth.ts';
import { bytesToBase64URL, hashToken, randomToken, encryptSecret } from '../src/crypto.ts';
export const origin = 'https://spottr.example';
export const dictionary = z.record(z.string(), z.unknown());
export async function digest(value: string) { return bytesToBase64URL(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value)))); }
export async function fixture(fetcher: typeof fetch = async () => new Response('{}', {status:503})) {
  const mf = new Miniflare({ modules:true, script:'export default {fetch(){return new Response("test")}}', d1Databases:['DB'] });
  const db = await mf.getD1Database('DB');
  for (const name of ['0001_accounts.sql','0002_native_accounts.sql','0003_analytics.sql']) await db.exec((await readFile(new URL('../migrations/'+name, import.meta.url),'utf8')).replace(/\n/g,' '));
  let now = 1_800_000_000_000;
  const env: NativeEnv = {DB:db,ORIGIN:origin,AUTH_ENCRYPTION_KEY:randomToken(),AUTH_TOKEN_PEPPER:randomToken(),RESEND_API_KEY:'test-only',RESEND_FROM:'auth@spottr.example'};
  const handler = () => createNativeAuthHandler(env, {clock:()=>now,fetch:fetcher});
  async function request(path: string, body: unknown = {}, headers: Record<string,string> = {}) {
    const response = await handler()(new Request(origin+'/api/native/v1'+path,{method:'POST',headers:{'Content-Type':'application/json',...headers},body:JSON.stringify(body)}));
    return {response,json:dictionary.parse(await response.json())};
  }
  async function seed() {
    const accountID=crypto.randomUUID(),deviceID=crypto.randomUUID(),accessToken=randomToken(),refreshToken=randomToken();
    const keys=await crypto.subtle.generateKey({name:'ECDSA',namedCurve:'P-256'},true,['sign','verify']);
    const jwk=await crypto.subtle.exportKey('jwk',keys.publicKey);
    const deviceKey={kty:'EC',crv:'P-256',x:jwk.x,y:jwk.y};
    await db.prepare('INSERT INTO users VALUES(?,?,?,?,?,?)').bind(accountID,'native-'+accountID,await encryptSecret('JBSWY3DPEHPK3PXP',env.AUTH_ENCRYPTION_KEY,accountID),0,1,now).run();
    await db.prepare('INSERT INTO native_devices(id,user_id,auth_version,public_key,access_hash,access_expires,refresh_hash,refresh_expires,mfa_at) VALUES(?,?,?,?,?,?,?,?,?)').bind(deviceID,accountID,1,JSON.stringify(deviceKey),await hashToken('native:access:'+accessToken,env.AUTH_TOKEN_PEPPER),now+900000,await hashToken('native:refresh:'+refreshToken,env.AUTH_TOKEN_PEPPER),now+180*86400000,now).run();
    return {accountID,deviceID,accessToken,refreshToken,keys,deviceKey};
  }
  async function signed(path: string, body: unknown, token: string, keys: CryptoKeyPair) {
    const ch=await request('/session/challenge',{token});
    if(ch.response.status!==200) return ch;
    const challenge=z.string().parse(ch.json['challenge']),nonce=randomToken(),issuedAt=new Date(now).toISOString();
    const canonical=['spottr-native-v1','POST','/api/native/v1'+path,await digest(JSON.stringify(body)),await digest(token),challenge,nonce,issuedAt].join('\n');
    const signature=bytesToBase64URL(new Uint8Array(await crypto.subtle.sign({name:'ECDSA',hash:'SHA-256'},keys.privateKey,new TextEncoder().encode(canonical))));
    return request(path,body,{Authorization:'Bearer '+token,'X-Spottr-Proof':JSON.stringify({challenge,nonce,issuedAt,signature})});
  }
  return {mf,db,env,handler,request,seed,signed,get now(){return now;},advance:(seconds:number)=>{now+=seconds*1000;}};
}
export async function accountFixture() {
 const mails:string[]=[];
 const f=await fixture(async(_url,init)=>{mails.push(String(init?.body));return Response.json({id:'test-mail'});});
 async function identity(email:string,purpose='enroll') {
  const start=await f.request('/identity/email/start',{email,purpose});
  const code=/\b\d{6}\b/.exec(mails.at(-1)??'')?.[0];
  return f.request('/identity/email/verify',{flowToken:start.json['flowToken'],code});
 }
 async function enroll() {
  const {SoftwarePasskey}=await import('./passkey.ts');const {totp}=await import('../src/crypto.ts');
  const email=crypto.randomUUID()+'@example.com',verified=await identity(email);
  const keys=await crypto.subtle.generateKey({name:'ECDSA',namedCurve:'P-256'},true,['sign','verify']);
  const jwk=await crypto.subtle.exportKey('jwk',keys.publicKey),deviceKey={kty:'EC',crv:'P-256',x:jwk.x,y:jwk.y};
  const options=await f.request('/passkey/enroll/options',{flowToken:verified.json['flowToken']});
  const opts=z.object({challenge:z.string(),user:z.object({id:z.string()})}).parse(options.json['options']);
  const passkey=await SoftwarePasskey.create();
  const pass=await f.request('/passkey/enroll/verify',{flowToken:options.json['flowToken'],credential:await passkey.registration(opts.challenge,opts.user.id,origin)});
  const secret=z.string().parse(pass.json['secret']);
  const completed=await f.request('/enroll/complete',{flowToken:pass.json['flowToken'],code:await totp(secret,f.now),deviceKey});
  if(completed.response.status!==200) throw new Error('Test enrollment failed');
  return {email,passkey,secret,keys,deviceKey,accountID:z.string().parse(completed.json['accountID']),accessToken:z.string().parse(completed.json['accessToken']),refreshToken:z.string().parse(completed.json['refreshToken']),backups:z.array(z.string()).parse(completed.json['backupCodes'])};
 }
 async function login(passkey:import('./passkey.ts').SoftwarePasskey) {
  const start=await f.request('/passkey/login/options',{}),options=z.object({challenge:z.string()}).parse(start.json['options']);
  return f.request('/passkey/login/verify',{flowToken:start.json['flowToken'],credential:await passkey.authentication(options.challenge,origin)});
 }
 return {...f,identity,enroll,login,mails,get now(){return f.now;}};
}

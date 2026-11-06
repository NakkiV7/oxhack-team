import { z } from 'zod';
import { decryptSecret, encryptSecret, randomToken, equalText, base64URLToBytes, bytesToBase64URL } from './crypto.ts';
import { denied, NativeError, tokenSchema, type Context } from './native-sessions.ts';
import { sendOwnershipCode } from './mail.ts';
export type Flow={id:string;stage:string;payload:string;expires_at:number;attempts:number};
export const identityProof=z.object({provider:z.enum(['email','apple']),subject:z.string(),purpose:z.enum(['enroll','recover','link']),userID:z.string(),authVersion:z.number().int(),providerCipher:z.string().nullable(),linkSession:z.string().optional(),backupHash:z.string().optional()}).strict();
export async function newFlow(c:Context,stage:string,payload:unknown) {
 const flowToken=randomToken(),id=await c.hash('flow:'+flowToken);
 await c.sql('INSERT INTO native_flows(id,stage,payload,expires_at) VALUES(?,?,?,?)',id,stage,await encryptSecret(JSON.stringify(payload),c.env.AUTH_ENCRYPTION_KEY,'flow:'+id),c.now()+300000).run();
 return {flowToken,expiresAt:new Date(c.now()+300000).toISOString()};
}
export async function readFlow(c:Context,token:string,stage:string) {
 const flow=await c.sql('UPDATE native_flows SET attempts=attempts+1 WHERE id=? AND stage=? AND expires_at>? AND attempts<5 RETURNING *',await c.hash('flow:'+token),stage,c.now()).first<Flow>();
 if(!flow) return denied();
 const data:unknown=JSON.parse(await decryptSecret(flow.payload,c.env.AUTH_ENCRYPTION_KEY,'flow:'+flow.id));
 return {flow,data};
}
export async function advanceFlow(c:Context,flow:Flow,stage:string,payload:unknown,userID:string|null=null) {
 const result=await c.sql('UPDATE native_flows SET stage=?,payload=?,user_id=COALESCE(?,user_id),attempts=0 WHERE id=? AND stage=? AND payload=? AND expires_at>?',stage,await encryptSecret(JSON.stringify(payload),c.env.AUTH_ENCRYPTION_KEY,'flow:'+flow.id),userID,flow.id,flow.stage,flow.payload,c.now()).run();
 if(result.meta.changes!==1) return denied();
}
const purposeSchema=z.enum(['enroll','recover','link']);
const emailPending=z.object({email:z.string(),codeHash:z.string(),purpose:purposeSchema,linkUser:z.string().optional(),linkVersion:z.number().optional(),linkSession:z.string().optional()}).strict();
export type LinkAuthority={userID:string;version:number;session:string};
export async function emailStart(c:Context,input:unknown,link?:LinkAuthority) {
 const {email,purpose}=z.object({email:z.email().max(254).transform(v=>v.toLowerCase()),purpose:purposeSchema}).strict().parse(input);
 if(purpose==='link'&&!link) return denied();
 const bytes=crypto.getRandomValues(new Uint32Array(1));
 const code=String((bytes[0]??0)%1000000).padStart(6,'0');
 const challenge=randomToken();
 const result=await newFlow(c,'email',{email,codeHash:await c.hash('email:'+challenge+':'+code),purpose,...link?{linkUser:link.userID,linkVersion:link.version,linkSession:link.session}:{},challenge});
 try {await sendOwnershipCode(c,email,code);}catch(error){await c.sql('DELETE FROM native_flows WHERE id=?',await c.hash('flow:'+result.flowToken)).run();throw error;}
 return {...result,accepted:true};
}
export async function acceptIdentity(c:Context,flow:Flow,provider:'email'|'apple',subject:string,purpose:z.infer<typeof purposeSchema>,providerCipher:string|null,link?:LinkAuthority) {
 const existing=await c.sql('SELECT i.user_id,u.auth_version FROM native_identities i JOIN users u ON i.user_id=u.id WHERE provider=? AND subject=?',provider,subject).first<{user_id:string;auth_version:number}>();
 if(purpose==='enroll'&&existing || purpose==='recover'&&!existing || purpose==='link'&&(!link || existing&&existing.user_id!==link.userID)) return denied();
 const proof={provider,subject,purpose,userID:link?.userID??existing?.user_id??crypto.randomUUID(),authVersion:link?.version??existing?.auth_version??1,providerCipher,...link?{linkSession:link.session}:{}};
 await advanceFlow(c,flow,'identity',proof,purpose==='enroll'?null:proof.userID);
 return {verified:true};
}
export async function emailVerify(c:Context,input:unknown) {
 const {flowToken,code}=z.object({flowToken:tokenSchema,code:z.string().max(20)}).strict().parse(input);
 const {flow,data}=await readFlow(c,flowToken,'email');
 const proof=emailPending.extend({challenge:tokenSchema}).parse(data);
 if(!equalText(proof.codeHash,await c.hash('email:'+proof.challenge+':'+code))) return denied();
 const link=proof.linkUser&&proof.linkVersion&&proof.linkSession?{userID:proof.linkUser,version:proof.linkVersion,session:proof.linkSession}:undefined;
 await acceptIdentity(c,flow,'email',await c.hash('email-subject:'+proof.email),proof.purpose,null,link);
 return {flowToken,verified:true};
}

const applePending=z.object({nonce:tokenSchema,purpose:purposeSchema,linkUser:z.string().optional(),linkVersion:z.number().optional(),linkSession:z.string().optional()}).strict();
function appleConfiguration(c:Context) {
 const {APPLE_CLIENT_ID,APPLE_TEAM_ID,APPLE_KEY_ID,APPLE_PRIVATE_KEY}=c.env;
 if(!APPLE_CLIENT_ID||!APPLE_TEAM_ID||!APPLE_KEY_ID||!APPLE_PRIVATE_KEY) throw new NativeError(503,'temporarily_unavailable');
 return {clientID:APPLE_CLIENT_ID,teamID:APPLE_TEAM_ID,keyID:APPLE_KEY_ID,privateKey:APPLE_PRIVATE_KEY};
}
export async function appleStart(c:Context,input:unknown,link?:LinkAuthority) {
 const {purpose}=z.object({purpose:purposeSchema}).strict().parse(input);
 appleConfiguration(c);
 if(purpose==='link'&&!link) return denied();
 const nonce=randomToken();
 return {...await newFlow(c,'apple',{nonce,purpose,...link?{linkUser:link.userID,linkVersion:link.version,linkSession:link.session}:{}}),nonce};
}
const appleClaims=z.object({iss:z.literal('https://appleid.apple.com'),aud:z.string(),sub:z.string().min(1).max(255),nonce:z.string(),iat:z.number().int(),exp:z.number().int()});
export async function verifyAppleToken(c:Context,token:string,nonce:string) {
 const config=appleConfiguration(c),parts=token.split('.');
 const [encodedHeader,encodedClaims,signature]=parts;
 if(parts.length!==3||!encodedHeader||!encodedClaims||!signature) return denied();
 try {
 const header=z.object({alg:z.literal('RS256'),kid:z.string().min(1).max(128)}).parse(JSON.parse(new TextDecoder().decode(base64URLToBytes(encodedHeader))));
 const claims=appleClaims.parse(JSON.parse(new TextDecoder().decode(base64URLToBytes(encodedClaims))));
 const now=Math.floor(c.now()/1000);
 if(claims.aud!==config.clientID || !equalText(claims.nonce,nonce) || claims.exp<=now || claims.iat>now+60 || claims.iat<now-3600 || claims.exp>claims.iat+3600) return denied();
 const response=await c.fetch('https://appleid.apple.com/auth/keys');
 if(!response.ok) throw new NativeError(503,'temporarily_unavailable');
 const keys=z.object({keys:z.array(z.object({kid:z.string(),kty:z.literal('RSA'),alg:z.literal('RS256'),use:z.literal('sig'),n:z.string(),e:z.string()}))}).parse(await response.json());
 const matches=keys.keys.filter(key=>key.kid===header.kid);if(matches.length!==1||!matches[0]) return denied();
 const key=await crypto.subtle.importKey('jwk',matches[0],{name:'RSASSA-PKCS1-v1_5',hash:'SHA-256'},false,['verify']);
 if(!await crypto.subtle.verify('RSASSA-PKCS1-v1_5',key,base64URLToBytes(signature),new TextEncoder().encode(encodedHeader+'.'+encodedClaims))) return denied();
 return claims;
 }catch(error){if(error instanceof NativeError&&error.status===503) throw error;return denied();}
}
async function appleClientSecret(c:Context) {
 const config=appleConfiguration(c),now=Math.floor(c.now()/1000);
 const encode=(value:unknown)=>bytesToBase64URL(new TextEncoder().encode(JSON.stringify(value)));
 const unsigned=encode({alg:'ES256',kid:config.keyID})+'.'+encode({iss:config.teamID,iat:now,exp:now+300,aud:'https://appleid.apple.com',sub:config.clientID});
 const pem=config.privateKey.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g,'').replaceAll('+','-').replaceAll('/','_').replace(/=+$/,'');
 const key=await crypto.subtle.importKey('pkcs8',base64URLToBytes(pem),{name:'ECDSA',namedCurve:'P-256'},false,['sign']);
 return unsigned+'.'+bytesToBase64URL(new Uint8Array(await crypto.subtle.sign({name:'ECDSA',hash:'SHA-256'},key,new TextEncoder().encode(unsigned))));
}
export async function appleVerify(c:Context,input:unknown) {
 const {flowToken,identityToken,authorizationCode}=z.object({flowToken:tokenSchema,identityToken:z.string().max(16000),authorizationCode:z.string().min(1).max(4096)}).strict().parse(input);
 const {flow,data}=await readFlow(c,flowToken,'apple'),proof=applePending.parse(data);
 const claims=await verifyAppleToken(c,identityToken,proof.nonce);
 const consumed=await c.sql("UPDATE native_flows SET stage='apple-exchange' WHERE id=? AND stage='apple' AND payload=? AND expires_at>?",flow.id,flow.payload,c.now()).run();
 if(consumed.meta.changes!==1) return denied();
 const config=appleConfiguration(c);
 const response=await c.fetch('https://appleid.apple.com/auth/token',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({client_id:config.clientID,client_secret:await appleClientSecret(c),code:authorizationCode,grant_type:'authorization_code'}).toString()});
 if(!response.ok) return denied();
 const tokens=z.object({id_token:z.string(),refresh_token:z.string().min(1).max(8192)}).parse(await response.json());
 const exchanged=await verifyAppleToken(c,tokens.id_token,proof.nonce);
 if(exchanged.sub!==claims.sub) return denied();
 const subject=await c.hash('apple-subject:'+claims.sub),cipher=await encryptSecret(tokens.refresh_token,c.env.AUTH_ENCRYPTION_KEY,'apple:'+subject);
 const link=proof.linkUser&&proof.linkVersion&&proof.linkSession?{userID:proof.linkUser,version:proof.linkVersion,session:proof.linkSession}:undefined;
 await acceptIdentity(c,{...flow,stage:'apple-exchange'},'apple',subject,proof.purpose,cipher,link);
 return {flowToken,verified:true};
}
export async function revokeApple(c:Context,subject:string,cipher:string) {
 const config=appleConfiguration(c),token=await decryptSecret(cipher,c.env.AUTH_ENCRYPTION_KEY,'apple:'+subject);
 const response=await c.fetch('https://appleid.apple.com/auth/revoke',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({client_id:config.clientID,client_secret:await appleClientSecret(c),token,token_type_hint:'refresh_token'}).toString()});
 if(!response.ok) throw new NativeError(503,'temporarily_unavailable');
}

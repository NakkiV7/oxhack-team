import { z } from 'zod';
import type { AuthEnv, Statement } from './auth.ts';
import { base64URLToBytes, bytesToBase64URL, decryptSecret, encryptSecret, hashToken, randomToken } from './crypto.ts';
export type NativeEnv = AuthEnv & { RESEND_API_KEY?: string; RESEND_FROM?: string; APPLE_CLIENT_ID?: string; APPLE_TEAM_ID?: string; APPLE_KEY_ID?: string; APPLE_PRIVATE_KEY?: string };
export type Dependencies = { clock?: () => number; fetch?: typeof fetch };
export class NativeError extends Error { constructor(readonly status: number, readonly code: string) {super(code);} }
export function denied(): never { throw new NativeError(401,'verification_failed'); }
export const tokenSchema=z.string().regex(/^[A-Za-z0-9_-]{43}$/);
export const deviceKeySchema=z.object({kty:z.literal('EC'),crv:z.literal('P-256'),x:tokenSchema,y:tokenSchema}).strict();
export const isoDateSchema=z.iso.datetime({offset:false});
export async function digest(value:string):Promise<string>{return bytesToBase64URL(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(value))));}
export function context(env:NativeEnv,deps:Dependencies={}) {
 const now=deps.clock??Date.now;
 return {env,now,fetch:deps.fetch??fetch,sql:(sql:string,...args:(string|number|null)[])=>env.DB.prepare(sql).bind(...args),hash:(value:string)=>hashToken(value,env.AUTH_TOKEN_PEPPER)};
}
export type Context=ReturnType<typeof context>;
export type Device={id:string;user_id:string;auth_version:number;public_key:string;access_hash:string;access_expires:number;refresh_hash:string;refresh_expires:number;mfa_at:number};
const accessTTL=900000,refreshTTL=180*86400000;
export async function sessionMaterial(c:Context,userID:string,version:number,deviceKey:z.infer<typeof deviceKeySchema>) {
 try{await crypto.subtle.importKey('jwk',deviceKey,{name:'ECDSA',namedCurve:'P-256'},false,['verify']);}catch{throw new NativeError(400,'invalid_request');}
 const accessToken=randomToken(),refreshToken=randomToken(),id=crypto.randomUUID(),now=c.now();
 const accessHash=await c.hash('native:access:'+accessToken),refreshHash=await c.hash('native:refresh:'+refreshToken);
 const appAccountToken=z.uuid().parse(userID);
 const reply={authenticated:true,appAccountToken,accountID:userID,deviceID:id,accessToken,refreshToken,accessExpiresAt:new Date(now+accessTTL).toISOString(),refreshExpiresAt:new Date(now+refreshTTL).toISOString()};
 const insert=(guard:string,args:(string|number|null)[]):Statement=>c.sql(`INSERT INTO native_devices(id,user_id,auth_version,public_key,access_hash,access_expires,refresh_hash,refresh_expires,mfa_at) SELECT ?,?,?,?,?,?,?,?,? WHERE ${guard}`,id,userID,version,JSON.stringify(deviceKey),accessHash,now+accessTTL,refreshHash,now+refreshTTL,now,...args);
 return {reply,insert};
}
export const deviceGuard='EXISTS(SELECT 1 FROM native_devices d JOIN users u ON u.id=d.user_id WHERE d.id=? AND d.access_hash=? AND d.access_expires>? AND d.auth_version=u.auth_version AND d.auth_version=?)';
export const deviceArgs=(c:Context,d:Device)=>([d.id,d.access_hash,c.now(),d.auth_version]);
export async function challenge(c:Context,input:unknown) {
 const {token}=z.object({token:tokenSchema}).strict().parse(input);
 const ah=await c.hash('native:access:'+token),rh=await c.hash('native:refresh:'+token);
 const d=await c.sql('SELECT d.* FROM native_devices d JOIN users u ON u.id=d.user_id WHERE d.auth_version=u.auth_version AND ((d.access_hash=? AND d.access_expires>?) OR (d.refresh_hash=? AND d.refresh_expires>?) OR EXISTS(SELECT 1 FROM native_refresh_history h WHERE h.device_id=d.id AND h.token_hash=? AND h.expires_at>?))',ah,c.now(),rh,c.now(),rh,c.now()).first<Device>();
 if(!d) return denied();
 const challenge=randomToken();
 await c.sql('INSERT INTO native_challenges(id,device_id,token_hash,expires_at) VALUES(?,?,?,?)',await c.hash('challenge:'+challenge),d.id,await digest(token),c.now()+60000).run();
 return {challenge,expiresAt:new Date(c.now()+60000).toISOString()};
}
const proofSchema=z.object({challenge:tokenSchema,nonce:tokenSchema,issuedAt:isoDateSchema,signature:z.string().regex(/^[A-Za-z0-9_-]{86}$/)}).strict();
export async function authorize(c:Context,request:Request,rawBody:string,refresh=false):Promise<Device & { presentedHash:string }> {
 const authorization=request.headers.get('Authorization');
 const token=tokenSchema.safeParse(authorization?.startsWith('Bearer ')?authorization.slice(7):undefined);
 if(!token.success) return denied();
 let proof:z.infer<typeof proofSchema>;
 try {proof=proofSchema.parse(JSON.parse(request.headers.get('X-Spottr-Proof')??''));}catch{return denied();}
 if(Math.abs(c.now()-Date.parse(proof.issuedAt))>60000) return denied();
 const presentedHash=await c.hash('native:'+(refresh?'refresh:':'access:')+token.data);
 const d=await c.sql(`SELECT d.* FROM native_devices d JOIN users u ON u.id=d.user_id WHERE d.auth_version=u.auth_version AND ${refresh?'((d.refresh_hash=? AND d.refresh_expires>?) OR EXISTS(SELECT 1 FROM native_refresh_history h WHERE h.device_id=d.id AND h.token_hash=? AND h.expires_at>?))':'d.access_hash=? AND d.access_expires>?'}`, ...refresh?[presentedHash,c.now(),presentedHash,c.now()]:[presentedHash,c.now()]).first<Device>();
 if(!d) return denied();
 const canonical=['spottr-native-v1',request.method,new URL(request.url).pathname,await digest(rawBody),await digest(token.data),proof.challenge,proof.nonce,proof.issuedAt].join('\n');
 try {
 const key=await crypto.subtle.importKey('jwk',deviceKeySchema.parse(JSON.parse(d.public_key)),{name:'ECDSA',namedCurve:'P-256'},false,['verify']);
 if(!await crypto.subtle.verify({name:'ECDSA',hash:'SHA-256'},key,base64URLToBytes(proof.signature),new TextEncoder().encode(canonical))) return denied();
 }catch{return denied();}
 const id=await c.hash('challenge:'+proof.challenge);
 try {
 const result=await c.env.DB.batch([
 c.sql('INSERT INTO native_proof_nonces(device_id,nonce,expires_at) SELECT ?,?,? WHERE EXISTS(SELECT 1 FROM native_challenges WHERE id=? AND device_id=? AND token_hash=? AND expires_at>?)',d.id,proof.nonce,c.now()+120000,id,d.id,await digest(token.data),c.now()),
 c.sql('DELETE FROM native_challenges WHERE id=? AND device_id=?',id,d.id)
 ]);
 if(result[0]?.meta.changes!==1) return denied();
 }catch(error){if(error instanceof NativeError) throw error;if(error instanceof Error&&error.message.includes('UNIQUE constraint failed: native_proof_nonces')) return denied();throw error;}
 return {...d,presentedHash};
}
async function resolveRotation(c:Context,d:Device & {presentedHash:string},requestHash:string) {
 const cached=await c.sql('SELECT h.reply_cipher FROM native_refresh_history h JOIN native_devices d ON d.id=h.device_id JOIN users u ON u.id=d.user_id WHERE h.token_hash=? AND d.id=? AND d.user_id=? AND d.auth_version=? AND d.auth_version=u.auth_version AND d.refresh_expires>? AND h.expires_at>? AND h.request_id=? AND h.retry_until>? AND h.successor_hash=d.refresh_hash AND h.reply_cipher<>?',d.presentedHash,d.id,d.user_id,d.auth_version,c.now(),c.now(),requestHash,c.now(),'').first<{reply_cipher:string}>();
 if(cached) return JSON.parse(await decryptSecret(cached.reply_cipher,c.env.AUTH_ENCRYPTION_KEY,'refresh:'+d.id));
 await c.sql('DELETE FROM native_devices WHERE id=? AND user_id=? AND auth_version=? AND refresh_expires>? AND EXISTS(SELECT 1 FROM users u WHERE u.id=native_devices.user_id AND u.auth_version=native_devices.auth_version) AND EXISTS(SELECT 1 FROM native_refresh_history h WHERE h.device_id=native_devices.id AND h.token_hash=? AND h.expires_at>? AND (h.request_id<>? OR h.retry_until<=? OR h.successor_hash<>native_devices.refresh_hash))',d.id,d.user_id,d.auth_version,c.now(),d.presentedHash,c.now(),requestHash,c.now()).run();
 return denied();
}
export async function rotate(c:Context,d:Device & {presentedHash:string},input:unknown) {
 const {requestID}=z.object({requestID:z.uuid()}).strict().parse(input),requestHash=await c.hash('rotation:'+requestID);
 const current=await c.sql('SELECT d.* FROM native_devices d JOIN users u ON d.user_id=u.id WHERE d.id=? AND d.user_id=? AND d.auth_version=? AND d.auth_version=u.auth_version AND d.refresh_expires>?',d.id,d.user_id,d.auth_version,c.now()).first<Device>();
 if(!current) return denied();
 if(current.refresh_hash!==d.presentedHash) return resolveRotation(c,d,requestHash);
 const material=await sessionMaterial(c,current.user_id,current.auth_version,deviceKeySchema.parse(JSON.parse(current.public_key)));
 const reply={...material.reply,deviceID:current.id};
 const successor=await c.hash('native:refresh:'+reply.refreshToken);
 const guard='EXISTS(SELECT 1 FROM native_devices d JOIN users u ON d.user_id=u.id WHERE d.id=? AND d.refresh_hash=? AND d.refresh_expires>? AND d.auth_version=? AND d.auth_version=u.auth_version)';
 const result=await c.env.DB.batch([
 c.sql(`INSERT OR IGNORE INTO native_refresh_history(token_hash,device_id,request_id,reply_cipher,retry_until,expires_at,successor_hash) SELECT ?,?,?,?,?,?,? WHERE ${guard}`,d.presentedHash,current.id,requestHash,await encryptSecret(JSON.stringify(reply),c.env.AUTH_ENCRYPTION_KEY,'refresh:'+current.id),c.now()+60000,current.refresh_expires,successor,current.id,d.presentedHash,c.now(),current.auth_version),
 c.sql('UPDATE native_devices SET access_hash=?,access_expires=?,refresh_hash=?,refresh_expires=? WHERE id=? AND refresh_hash=? AND EXISTS(SELECT 1 FROM native_refresh_history WHERE token_hash=? AND successor_hash=?)',await c.hash('native:access:'+reply.accessToken),Date.parse(reply.accessExpiresAt),successor,Date.parse(reply.refreshExpiresAt),current.id,d.presentedHash,d.presentedHash,successor)
 ]);
 if(result[1]?.meta.changes!==1) return resolveRotation(c,d,requestHash);
 return reply;
}

export async function cleanupNative(c:Context) {
 await c.env.DB.batch([
 c.sql("UPDATE native_refresh_history SET reply_cipher='',request_id='',successor_hash='' WHERE retry_until<=? AND (reply_cipher<>'' OR request_id<>'' OR successor_hash<>'')",c.now()),
 ...['native_flows','native_challenges','native_proof_nonces','native_refresh_history'].map(table=>c.sql(`DELETE FROM ${table} WHERE expires_at<=?`,c.now())),
 c.sql('DELETE FROM native_devices WHERE refresh_expires<=?',c.now()),
 c.sql('DELETE FROM native_mail_reservations WHERE created_at<?',c.now()-38*86400000)
 ]);
}

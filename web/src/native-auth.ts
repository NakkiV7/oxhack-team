import { z } from 'zod';
import { plans } from './account-plans.ts';
import { context, challenge, authorize, rotate, NativeError, denied, tokenSchema, deviceKeySchema, sessionMaterial, deviceGuard, deviceArgs, type Device, type Context, type NativeEnv, type Dependencies } from './native-sessions.ts';
import { generateRegistrationOptions, verifyRegistrationResponse, generateAuthenticationOptions, verifyAuthenticationResponse } from '@simplewebauthn/server';
import { registrationSchema, authenticationSchema } from './auth.ts';
import { newTOTPSecret, encryptSecret, decryptSecret, verifyTOTP, recoveryCodes, normalizeRecovery, bytesToBase64URL, base64URLToBytes, randomToken, equalText } from './crypto.ts';
import { emailStart, emailVerify, appleStart, appleVerify, deleteAfterAppleRevocation, newFlow, readFlow, advanceFlow, identityProof, type LinkAuthority } from './identity.ts';
export type { NativeEnv } from './native-sessions.ts';
const nativeRegistration=registrationSchema.strict().extend({response:registrationSchema.shape.response.strict(),clientExtensionResults:z.object({credProps:z.object({rk:z.boolean().optional()}).strict().optional()}).strict()});
const credentialSchema=z.object({id:z.string(),publicKey:z.string(),counter:z.number()}).strict();
const enrollmentProof=identityProof.extend({cipher:z.string(),credential:credentialSchema});
async function enrollOptions(c:Context,input:unknown,recovery=false) {
 const {flowToken,backupCode}=z.object({flowToken:tokenSchema,backupCode:z.string().max(64).optional()}).strict().parse(input);
 const {flow,data}=await readFlow(c,flowToken,'identity'),proof=identityProof.parse(data);
 if(proof.purpose!==(recovery?'recover':'enroll') || !recovery&&backupCode) return denied();
 const backupHash=recovery?await c.hash('backup:'+proof.userID+':'+normalizeRecovery(backupCode??'')):undefined;
 if(backupHash&&!await c.sql('SELECT 1 FROM backup_codes b JOIN users u ON u.id=b.user_id WHERE b.code_hash=? AND b.user_id=? AND u.auth_version=?',backupHash,proof.userID,proof.authVersion).first()) return denied();
 const options=await generateRegistrationOptions({rpName:'Spottr',rpID:new URL(c.env.ORIGIN).hostname,userID:new TextEncoder().encode(proof.userID),userName:'Spottr account',attestationType:'none',supportedAlgorithmIDs:[-7,-257],authenticatorSelection:{residentKey:'required',userVerification:'required'}});
 await advanceFlow(c,flow,'registration',{...proof,...backupHash?{backupHash}:{},challenge:options.challenge});
 return {flowToken,options};
}
async function enrollVerify(c:Context,input:unknown) {
 const {flowToken,credential}=z.object({flowToken:tokenSchema,credential:nativeRegistration}).strict().parse(input);
 const {flow,data}=await readFlow(c,flowToken,'registration');
 const proof=identityProof.extend({challenge:z.string()}).parse(data);
 let result;
 try{result=await verifyRegistrationResponse({response:credential,expectedChallenge:proof.challenge,expectedOrigin:c.env.ORIGIN,expectedRPID:new URL(c.env.ORIGIN).hostname,requireUserVerification:true});}catch{return denied();}
 if(!result.verified||!result.registrationInfo) return denied();
 const secret=newTOTPSecret(),key=result.registrationInfo.credential;
 const {challenge:_,...identity}=proof;
 await advanceFlow(c,flow,'enrollment',{...identity,cipher:await encryptSecret(secret,c.env.AUTH_ENCRYPTION_KEY,proof.userID),credential:{id:key.id,publicKey:bytesToBase64URL(key.publicKey),counter:key.counter}});
 return {flowToken,secret,uri:`otpauth://totp/Spottr:account?secret=${secret}&issuer=Spottr&algorithm=SHA1&digits=6&period=30`};
}
async function enrollComplete(c:Context,input:unknown) {
 const {flowToken,code,deviceKey}=z.object({flowToken:tokenSchema,code:z.string().max(20),deviceKey:deviceKeySchema}).strict().parse(input);
 const {flow,data}=await readFlow(c,flowToken,'enrollment'),proof=enrollmentProof.parse(data);
 const step=await verifyTOTP(await decryptSecret(proof.cipher,c.env.AUTH_ENCRYPTION_KEY,proof.userID),code,c.now());
 if(step===null) return denied();
 const marker=randomToken(),guard="EXISTS(SELECT 1 FROM native_flows WHERE id=? AND stage='committed' AND payload=?)",args=[flow.id,marker];
 const recovering=proof.purpose==='recover';
 if(proof.purpose==='link' || recovering&&!proof.backupHash) return denied();
 const version=recovering?proof.authVersion+1:1;
 const codes=recoveryCodes(),session=await sessionMaterial(c,proof.userID,version,deviceKey);
 const backups=await Promise.all(codes.map(async code=>c.sql(`INSERT INTO backup_codes(code_hash,user_id) SELECT ?,? WHERE ${guard}`,await c.hash('backup:'+proof.userID+':'+normalizeRecovery(code)),proof.userID,...args)));
 const result=await c.env.DB.batch([
 c.sql(`UPDATE native_flows SET stage='committed',payload=? WHERE id=? AND stage=? AND payload=? AND expires_at>? ${recovering?'AND EXISTS(SELECT 1 FROM users u JOIN backup_codes b ON b.user_id=u.id WHERE u.id=? AND u.auth_version=? AND b.code_hash=?)':''}`,marker,flow.id,flow.stage,flow.payload,c.now(),...recovering?[proof.userID,proof.authVersion,proof.backupHash??'']:[]),
 ...recovering?[
 c.sql(`UPDATE users SET totp_cipher=?,last_totp_step=?,auth_version=? WHERE id=? AND ${guard}`,proof.cipher,step,version,proof.userID,...args),
 ...['credentials','sessions','native_devices','backup_codes'].map(table=>c.sql(`DELETE FROM ${table} WHERE user_id=? AND ${guard}`,proof.userID,...args)),
 c.sql(`UPDATE native_identities SET provider_cipher=? WHERE provider=? AND subject=? AND user_id=? AND ${guard}`,proof.providerCipher,proof.provider,proof.subject,proof.userID,...args)
 ]:[
 c.sql(`INSERT INTO users(id,username,totp_cipher,last_totp_step,auth_version,created_at) SELECT ?,?,?,?,1,? WHERE ${guard}`,proof.userID,'native-'+proof.userID,proof.cipher,step,c.now(),...args),
 c.sql(`INSERT INTO native_identities(provider,subject,user_id,provider_cipher) SELECT ?,?,?,? WHERE ${guard}`,proof.provider,proof.subject,proof.userID,proof.providerCipher,...args)
 ],
 c.sql(`INSERT INTO credentials(id,user_id,public_key,counter) SELECT ?,?,?,? WHERE ${guard}`,proof.credential.id,proof.userID,proof.credential.publicKey,proof.credential.counter,...args),
 ...backups,session.insert(guard,args),c.sql(`DELETE FROM native_flows WHERE id=? AND ${guard}`,flow.id,...args)
 ]);
 if(result[0]?.meta.changes!==1) return denied();
 return {...session.reply,backupCodes:codes};
}
const nativeAuthentication=authenticationSchema.strict().extend({response:authenticationSchema.shape.response.strict(),clientExtensionResults:z.object({appid:z.boolean().optional()}).strict()});
const loginProof=z.object({userID:z.string(),authVersion:z.number(),passkeyAt:z.number()}).strict();
async function loginOptions(c:Context,input:unknown) {
 z.object({}).strict().parse(input);
 const options=await generateAuthenticationOptions({rpID:new URL(c.env.ORIGIN).hostname,userVerification:'required'});
 return {...await newFlow(c,'login',{challenge:options.challenge}),options};
}
async function loginVerify(c:Context,input:unknown) {
 const {flowToken,credential:response}=z.object({flowToken:tokenSchema,credential:nativeAuthentication}).strict().parse(input);
 const {flow,data}=await readFlow(c,flowToken,'login'),proof=z.object({challenge:z.string()}).strict().parse(data);
 const credential=await c.sql('SELECT c.*,u.auth_version FROM credentials c JOIN users u ON c.user_id=u.id WHERE c.id=?',response.id).first<{id:string;user_id:string;public_key:string;counter:number;auth_version:number}>();
 if(!credential || response.response.userHandle!==bytesToBase64URL(new TextEncoder().encode(credential.user_id))) return denied();
 let result;
 try{result=await verifyAuthenticationResponse({response,expectedChallenge:proof.challenge,expectedOrigin:c.env.ORIGIN,expectedRPID:new URL(c.env.ORIGIN).hostname,requireUserVerification:true,credential:{id:credential.id,publicKey:base64URLToBytes(credential.public_key),counter:credential.counter}});}catch{return denied();}
 if(!result.verified) return denied();
 const updated=await c.sql('UPDATE credentials SET counter=? WHERE id=? AND counter=? AND EXISTS(SELECT 1 FROM users WHERE id=? AND auth_version=?)',result.authenticationInfo.newCounter,credential.id,credential.counter,credential.user_id,credential.auth_version).run();
 if(updated.meta.changes!==1) return denied();
 await advanceFlow(c,flow,'mfa',{userID:credential.user_id,authVersion:credential.auth_version,passkeyAt:c.now()},credential.user_id);
 return {flowToken,needsSecondFactor:true};
}
async function mfaComplete(c:Context,input:unknown) {
 const inputSchema=z.object({flowToken:tokenSchema,code:z.string().max(20).optional(),backupCode:z.string().max(64).optional(),deviceKey:deviceKeySchema}).strict();
 const value=inputSchema.parse(input);
 if((value.code===undefined)===(value.backupCode===undefined)) return denied();
 const {flow,data}=await readFlow(c,value.flowToken,'mfa'),proof=loginProof.parse(data);
 const user=await c.sql('SELECT * FROM users WHERE id=? AND auth_version=?',proof.userID,proof.authVersion).first<{totp_cipher:string;last_totp_step:number}>();
 if(!user || c.now()-proof.passkeyAt>=300000) return denied();
 const step=value.code?await verifyTOTP(await decryptSecret(user.totp_cipher,c.env.AUTH_ENCRYPTION_KEY,proof.userID),value.code,c.now()):null;
 const backup=value.backupCode?await c.hash('backup:'+proof.userID+':'+normalizeRecovery(value.backupCode)):null;
 if(!backup&&step===null) return denied();
 const marker=randomToken(),guard="EXISTS(SELECT 1 FROM native_flows WHERE id=? AND stage='committed' AND payload=?)",args=[flow.id,marker];
 const session=await sessionMaterial(c,proof.userID,proof.authVersion,value.deviceKey);
 const result=await c.env.DB.batch([
 c.sql(`UPDATE native_flows SET stage='committed',payload=? WHERE id=? AND stage=? AND payload=? AND expires_at>? AND EXISTS(SELECT 1 FROM users WHERE id=? AND auth_version=? AND ${backup?'EXISTS(SELECT 1 FROM backup_codes WHERE user_id=? AND code_hash=?)':'last_totp_step<?'})`,marker,flow.id,flow.stage,flow.payload,c.now(),proof.userID,proof.authVersion,...backup?[proof.userID,backup]:[step]),
 backup?c.sql(`DELETE FROM backup_codes WHERE user_id=? AND code_hash=? AND ${guard}`,proof.userID,backup,...args):c.sql(`UPDATE users SET last_totp_step=? WHERE id=? AND ${guard}`,step,proof.userID,...args),
 session.insert(guard,args),c.sql(`DELETE FROM native_flows WHERE id=? AND ${guard}`,flow.id,...args)
 ]);
 if(result[0]?.meta.changes!==1) return denied();
 return {...session.reply,usedBackupCode:Boolean(backup)};
}
async function linkAuthority(c:Context,request:Request,raw:string):Promise<LinkAuthority> {
 if(request.headers.has('Authorization')) {
 const d=await authorize(c,request,raw);if(c.now()-d.mfa_at>=300000) return denied();
 return {userID:d.user_id,version:d.auth_version,session:'native:'+d.access_hash};
 }
 if(request.headers.get('Origin')!==c.env.ORIGIN) return denied();
 const cookies=(request.headers.get('Cookie')??'').split(';').map(v=>v.trim()).filter(v=>v.startsWith('__Host-spottr_session='));
 if(cookies.length!==1) return denied();
 const rawToken=tokenSchema.safeParse(cookies[0]?.slice('__Host-spottr_session='.length));if(!rawToken.success) return denied();
 if(!equalText(request.headers.get('X-Spottr-CSRF')??'',await c.hash('csrf:'+rawToken.data))) return denied();
 const hash=await c.hash('session:'+rawToken.data);
 const session=await c.sql('SELECT s.user_id,s.auth_version FROM sessions s JOIN users u ON u.id=s.user_id WHERE s.token_hash=? AND s.expires_at>? AND s.mfa_at>? AND s.auth_version=u.auth_version',hash,c.now(),c.now()-300000).first<{user_id:string;auth_version:number}>();
 if(!session) return denied();
 return {userID:session.user_id,version:session.auth_version,session:'web:'+hash};
}
function isLink(input:unknown) {return z.object({purpose:z.literal('link')}).safeParse(input).success;}
async function completeLink(c:Context,input:unknown,authority:LinkAuthority) {
 const {flowToken}=z.object({flowToken:tokenSchema}).strict().parse(input),{flow,data}=await readFlow(c,flowToken,'identity'),proof=identityProof.parse(data);
 if(proof.purpose!=='link'||proof.userID!==authority.userID||proof.authVersion!==authority.version||proof.linkSession!==authority.session) return denied();
 const native=authority.session.startsWith('native:'),sessionHash=authority.session.slice(native?7:4);
 const authorization=native?'EXISTS(SELECT 1 FROM native_devices s JOIN users u ON u.id=s.user_id WHERE s.access_hash=? AND s.user_id=? AND s.auth_version=? AND s.auth_version=u.auth_version AND s.access_expires>? AND s.mfa_at>?)':'EXISTS(SELECT 1 FROM sessions s JOIN users u ON u.id=s.user_id WHERE s.token_hash=? AND s.user_id=? AND s.auth_version=? AND s.auth_version=u.auth_version AND s.expires_at>? AND s.mfa_at>?)';
 const marker=randomToken(),guard="EXISTS(SELECT 1 FROM native_flows WHERE id=? AND stage='committed' AND payload=?)",args=[flow.id,marker];
 const result=await c.env.DB.batch([
 c.sql(`UPDATE native_flows SET stage='committed',payload=? WHERE id=? AND stage=? AND payload=? AND expires_at>? AND ${authorization} AND NOT EXISTS(SELECT 1 FROM native_identities WHERE provider=? AND subject=? AND user_id<>?)`,marker,flow.id,flow.stage,flow.payload,c.now(),sessionHash,proof.userID,proof.authVersion,c.now(),c.now()-300000,proof.provider,proof.subject,proof.userID),
 c.sql(`INSERT INTO native_identities(provider,subject,user_id,provider_cipher) SELECT ?,?,?,? WHERE ${guard} ON CONFLICT(provider,subject) DO UPDATE SET provider_cipher=excluded.provider_cipher WHERE native_identities.user_id=excluded.user_id`,proof.provider,proof.subject,proof.userID,proof.providerCipher,...args),
 c.sql(`DELETE FROM native_flows WHERE id=? AND ${guard}`,flow.id,...args)
 ]);
 if(result[0]?.meta.changes!==1) return denied();
 return {linked:true};
}
async function readBody(request:Request) {
 if(!request.headers.get('Content-Type')?.toLowerCase().startsWith('application/json')) throw new NativeError(415,'json_required');
 if(Number(request.headers.get('Content-Length')??0)>32768) throw new NativeError(413,'body_too_large');
 const reader=request.body?.getReader();if(!reader) throw new NativeError(400,'invalid_request');
 const chunks:Uint8Array[]=[];let size=0;
 while(true){const next=await reader.read();if(next.done) break;size+=next.value.length;if(size>32768){await reader.cancel();throw new NativeError(413,'body_too_large');}chunks.push(next.value);}
 const bytes=new Uint8Array(size);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}
 try {const raw=new TextDecoder('utf-8',{fatal:true}).decode(bytes);const body:unknown=JSON.parse(raw);return {raw,body};}catch{throw new NativeError(400,'invalid_request');}
}
async function limit(c:Context,request:Request) {
 const bucket=Math.floor(c.now()/600000),id=await c.hash('native-rate:'+(request.headers.get('CF-Connecting-IP')??'local')+':'+bucket);
 const row=await c.sql('INSERT INTO rate_limits(id,count,expires_at) VALUES(?,1,?) ON CONFLICT(id) DO UPDATE SET count=count+1 RETURNING count',id,(bucket+1)*600000).first<{count:number}>();
 if(!row||row.count>60) throw new NativeError(429,'rate_limited');
}
async function revokeDevice(c:Context,d:Device,input:unknown,self=false) {
 const target=self?(z.object({}).strict().parse(input),d.id):z.object({deviceID:z.uuid()}).strict().parse(input).deviceID;
 if(!self&&c.now()-d.mfa_at>=300000) return denied();
 const removed=await c.sql(`DELETE FROM native_devices WHERE id=? AND user_id=? AND ${deviceGuard} RETURNING id`,target,d.user_id,...deviceArgs(c,d)).first();
 if(!removed) return denied();
 return {signedOut:true};
}
async function deleteAccount(c:Context,d:Device,input:unknown) {
 z.object({confirm:z.literal('DELETE')}).strict().parse(input);
 if(c.now()-d.mfa_at>=300000) return denied();
 const result=await deleteAfterAppleRevocation(c,{userID:d.user_id,authorization:`${deviceGuard} AND EXISTS(SELECT 1 FROM native_devices WHERE id=? AND mfa_at>?)`,authorizationArgs:()=>[...deviceArgs(c,d),d.id,c.now()-300000]});
 if(result==='retry') throw new NativeError(503,'temporarily_unavailable');
 if(result!=='deleted') return denied();
 return {deleted:true,phoneHistoryUnchanged:true};
}
export function createNativeAuthHandler(env:NativeEnv,deps:Dependencies={}) {
 const c=context(env,deps);
 async function dispatch(path:string,body:unknown,request:Request,raw:string):Promise<unknown> {
 switch(path){
 case '/identity/apple/start':return appleStart(c,body,isLink(body)?await linkAuthority(c,request,raw):undefined);
 case '/identity/apple/verify':return appleVerify(c,body);
 case '/identity/email/start':return emailStart(c,body,isLink(body)?await linkAuthority(c,request,raw):undefined);
 case '/identity/email/verify':return emailVerify(c,body);
 case '/identity/link/complete':return completeLink(c,body,await linkAuthority(c,request,raw));
 case '/recovery/options':return enrollOptions(c,body,true);
 case '/passkey/enroll/options':return enrollOptions(c,body);
 case '/passkey/enroll/verify':return enrollVerify(c,body);
 case '/enroll/complete':return enrollComplete(c,body);
 case '/passkey/login/options':return loginOptions(c,body);
 case '/passkey/login/verify':return loginVerify(c,body);
 case '/mfa/complete':return mfaComplete(c,body);
 case '/session/challenge':return challenge(c,body);
 case '/session/refresh':return rotate(c,await authorize(c,request,raw,true),body);
 case '/session/current':{z.object({}).strict().parse(body);const d=await authorize(c,request,raw);return {authenticated:true,accountID:d.user_id,appAccountToken:z.uuid().parse(d.user_id),deviceID:d.id,accessExpiresAt:new Date(d.access_expires).toISOString(),refreshExpiresAt:new Date(d.refresh_expires).toISOString()};}
 case '/session/sign-out':return revokeDevice(c,await authorize(c,request,raw),body,true);
 case '/session/revoke':return revokeDevice(c,await authorize(c,request,raw),body);
 case '/plans/read':case '/plans/write':case '/plans/withdraw':return plans(c,await authorize(c,request,raw),path,body);
 case '/account/delete':return deleteAccount(c,await authorize(c,request,raw),body);
 default:throw new NativeError(404,'not_found');
 }
 }
 return async(request:Request):Promise<Response>=>{
 const headers={'Cache-Control':'no-store','X-Content-Type-Options':'nosniff','Referrer-Policy':'no-referrer','Content-Security-Policy':"default-src 'none'; frame-ancestors 'none'"};
 try {
 const url=new URL(request.url),origin=request.headers.get('Origin');
 if(url.origin!==env.ORIGIN || origin!==null&&origin!==env.ORIGIN || request.headers.get('Sec-Fetch-Site')==='cross-site') throw new NativeError(403,'origin_rejected');
 if(request.method!=='POST'||!url.pathname.startsWith('/api/native/v1/')||url.search) throw new NativeError(404,'not_found');
 await limit(c,request);
 const {raw,body}=await readBody(request);
 return Response.json(await dispatch(url.pathname.slice('/api/native/v1'.length),body,request,raw),{headers});
 }catch(error){return Response.json({error:error instanceof NativeError?error.code:error instanceof z.ZodError?'invalid_request':'temporarily_unavailable'},{status:error instanceof NativeError?error.status:error instanceof z.ZodError?400:503,headers});}
 };
}

import assert from 'node:assert/strict';
import { writeFile } from 'node:fs/promises';
import { z } from 'zod';
import { SoftwarePasskey } from '../test/passkey.ts';
import { totp } from '../src/crypto.ts';
if (!process.argv.includes('--live')) throw new Error('Pass --live to create and delete an ephemeral smoke-test account');
const origin = 'https://spottr.omarchoudhry.co.uk';
const username = 'smoke_' + Date.now().toString(36);
const passkey = await SoftwarePasskey.create();
const cookies = new Map<string,string>();
let csrf = '';
const checks: string[] = [];
async function request(path: string, body?: unknown, expected = 200): Promise<Record<string,unknown>> {
  const headers: Record<string,string> = {Origin:origin,Cookie:Array.from(cookies,([k,v])=>`${k}=${v}`).join('; ')};
  if (body !== undefined) headers['Content-Type']='application/json';
  if (csrf) headers['X-Spottr-CSRF']=csrf;
  const response=await fetch(origin+path,{method:body===undefined?'GET':'POST',headers,body:body===undefined?undefined:JSON.stringify(body)});
  for(const cookie of response.headers.getSetCookie()) {
    const pair=cookie.split(';')[0]??'',i=pair.indexOf('=');
    if(i>0)cookies.set(pair.slice(0,i),pair.slice(i+1));
  }
  assert.equal(response.status,expected,`${path} status ${response.status}`);
  assert.equal(response.headers.get('Cache-Control'),'no-store');
  const json=z.record(z.string(),z.unknown()).parse(await response.json());
  if(typeof json['csrf']==='string')csrf=json['csrf'];
  return json;
}
async function prove():Promise<void> {
  const options=await request('/api/auth/login/options',{});
  const challenge=z.object({challenge:z.string()}).parse(options['options']).challenge;
  await request('/api/auth/login/verify',{credential:await passkey.authentication(challenge,origin)});
}
let created=false,deleted=false;
try {
  const begin=await request('/api/auth/register/options',{username});
  const options=z.object({challenge:z.string(),user:z.object({id:z.string()})}).parse(begin['options']);
  const setup=await request('/api/auth/register/verify',{credential:await passkey.registration(options.challenge,options.user.id,origin)});
  await request('/api/auth/session',undefined,401);checks.push('Passkey setup alone has no session');
  const secret=z.string().parse(setup['secret']);
  const enrolled=await request('/api/auth/enroll',{code:await totp(secret,Date.now())});created=true;
  const codes=z.array(z.string()).length(10).parse(enrolled['backupCodes']);
  assert.equal((await request('/api/auth/session'))['username'],username);checks.push('Passkey plus Authenticator creates account');
  await request('/api/auth/logout',{});csrf='';await prove();
  await request('/api/auth/session',undefined,401);checks.push('Passkey-only login has no session');
  await request('/api/auth/mfa',{backupCode:codes[0]});
  assert.equal((await request('/api/auth/session'))['backupCodesRemaining'],9);checks.push('Backup code provides second factor once');
  const rotated=await request('/api/account/backup-codes',{});
  assert.equal(z.array(z.string()).parse(rotated['backupCodes']).length,10);checks.push('Fresh account session rotates recovery codes');
  const replacement=await request('/api/account/authenticator/options',{});
  const replaced=await request('/api/account/authenticator/verify',{code:await totp(z.string().parse(replacement['secret']),Date.now())});
  assert.equal(z.array(z.string()).parse(replaced['backupCodes']).length,10);checks.push('Authenticator replacement establishes fresh session');
  const data=await request('/api/account/export');assert.equal(data['storedHealthData'],false);checks.push('Export confirms no health or workout upload');
  await request('/api/account/delete',{confirm:'DELETE'});deleted=true;
  await request('/api/auth/session',undefined,401);checks.push('Account deletion revokes session');
} finally {
  if(created&&!deleted) {
    try { await request('/api/account/delete',{confirm:'DELETE'});deleted=true; }
    catch { console.error('Smoke account cleanup requires attention: '+username); }
  }
}
assert.equal(deleted,true,'Ephemeral account was removed');
const receipt={checkedAt:new Date().toISOString(),origin,softwareAuthenticator:true,hardwarePasskeyAcceptance:false,checks,ephemeralAccountDeleted:deleted};
await writeFile('../.local/production-foundation/live-account-smoke.json',JSON.stringify(receipt,null,2)+'\n');
console.log(JSON.stringify(receipt,null,2));

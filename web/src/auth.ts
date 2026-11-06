import { z } from 'zod';
import { context } from './native-sessions.ts';
import { revokeApple } from './identity.ts';
import { generateRegistrationOptions, verifyRegistrationResponse, generateAuthenticationOptions, verifyAuthenticationResponse } from '@simplewebauthn/server';
import { randomToken, hashToken, encryptSecret, decryptSecret, newTOTPSecret, verifyTOTP, recoveryCodes, normalizeRecovery, bytesToBase64URL, base64URLToBytes, equalText } from './crypto.ts';

type SQLValue = string | number | null;
export interface Statement {
  bind(...values: SQLValue[]): Statement;
  first<T>(): Promise<T | null>;
  all<T>(): Promise<{ results: T[] }>;
  run(): Promise<{ meta: { changes: number } }>;
}
export interface Database { prepare(sql: string): Statement; batch(statements: Statement[]): Promise<{ meta: { changes: number } }[]>; }
export interface AuthEnv { DB: Database; ORIGIN: string; AUTH_ENCRYPTION_KEY: string; AUTH_TOKEN_PEPPER: string; }
const pendingCookie = '__Host-spottr_pending', sessionCookie = '__Host-spottr_session';
const pendingTTL = 5 * 60_000, sessionTTL = 12 * 3600_000, freshTTL = 5 * 60_000;
class AuthError extends Error { constructor(readonly status: number, message: string) { super(message); } }
const fail = (): never => { throw new AuthError(401, 'Sign-in could not be verified. Try again with a new code.'); };
const publicKeyString = z.string().min(1).max(20_000).regex(/^[A-Za-z0-9_-]+$/);
const clientExtensions = z.object({ credProps: z.object({ rk: z.boolean().optional() }).optional(), appid: z.boolean().optional() }).passthrough();
export const registrationSchema = z.object({ id: publicKeyString, rawId: publicKeyString, type: z.literal('public-key'), clientExtensionResults: clientExtensions, authenticatorAttachment: z.enum(['platform', 'cross-platform']).optional(), response: z.object({ clientDataJSON: publicKeyString, attestationObject: publicKeyString, transports: z.array(z.enum(['usb','nfc','ble','internal','hybrid','smart-card','cable'])).optional() }) });
export const authenticationSchema = z.object({ id: publicKeyString, rawId: publicKeyString, type: z.literal('public-key'), clientExtensionResults: clientExtensions, authenticatorAttachment: z.enum(['platform', 'cross-platform']).optional(), response: z.object({ clientDataJSON: publicKeyString, authenticatorData: publicKeyString, signature: publicKeyString, userHandle: publicKeyString.optional() }) });
const credentialSchema = z.object({ id: z.string(), publicKey: z.string(), counter: z.number().int().nonnegative() });
const registrationPending = z.object({ userID: z.string(), username: z.string(), challenge: z.string() });
const enrollmentPending = z.object({ userID: z.string(), username: z.string(), cipher: z.string(), credential: credentialSchema });
const loginPending = z.object({ userID: z.string(), authVersion: z.number(), passkeyAt: z.number() });
const replacementPending = z.object({ userID: z.string(), authVersion: z.number(), cipher: z.string() });
interface Pending { id: string; stage: string; payload: string; expires_at: number; attempts: number; }
interface User { id: string; username: string; totp_cipher: string; last_totp_step: number; auth_version: number; created_at: number; }
interface Session extends User { token_hash: string; mfa_at: number; expires_at: number; }
function cookie(name: string, value: string, seconds: number): string { return `${name}=${value}; Path=/; Max-Age=${seconds}; Secure; HttpOnly; SameSite=Strict`; }
function cookieValue(request: Request, name: string): string | null {
  const pairs = (request.headers.get('Cookie') ?? '').split(';').map(v => v.trim());
  const values = pairs.filter(v => v.startsWith(name + '='));
  if (values.length !== 1) return null;
  const value = values[0]?.slice(name.length + 1) ?? '';
  return /^[A-Za-z0-9_-]{43}$/.test(value) ? value : null;
}
function json(body: unknown, status = 200, cookies: string[] = []): Response {
  const headers = new Headers({ 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', 'Content-Security-Policy': "default-src 'none'; frame-ancestors 'none'", 'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer' });
  for (const value of cookies) headers.append('Set-Cookie', value);
  return new Response(JSON.stringify(body), { status, headers });
}
async function readJSON(request: Request): Promise<unknown> {
  if (!request.headers.get('Content-Type')?.toLowerCase().startsWith('application/json')) throw new AuthError(415, 'Use a JSON request.');
  if (Number(request.headers.get('Content-Length') ?? 0) > 32_768) throw new AuthError(413, 'The request is too large.');
  const reader = request.body?.getReader();
  if (!reader) throw new AuthError(400, 'Missing request.');
  const chunks: Uint8Array[] = []; let size = 0;
  while (true) {
    const next = await reader.read(); if (next.done) break;
    size += next.value.length;
    if (size > 32_768) { await reader.cancel(); throw new AuthError(413, 'The request is too large.'); }
    chunks.push(next.value);
  }
  const bytes = new Uint8Array(size); let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  try { return JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes)); }
  catch { throw new AuthError(400, 'The request is not valid JSON.'); }
}
export async function cleanup(env: AuthEnv, now = Date.now()): Promise<void> {
  await env.DB.batch(['pending','sessions','rate_limits'].map(table => env.DB.prepare(`DELETE FROM ${table} WHERE expires_at < ?`).bind(now)));
}
export function createAuthHandler(env: AuthEnv, clock: () => number = Date.now, fetcher: typeof fetch = fetch): (request: Request) => Promise<Response> {
  const rpID = new URL(env.ORIGIN).hostname;
  const statement = (sql: string, ...args: SQLValue[]): Statement => env.DB.prepare(sql).bind(...args);
  const tokenHash = (value: string): Promise<string> => hashToken(value, env.AUTH_TOKEN_PEPPER);
  async function pending(request: Request, stage: string, consume = false): Promise<Pending> {
    const raw = cookieValue(request, pendingCookie); if (!raw) return fail();
    const id = await tokenHash('pending:' + raw);
    const sql = consume ? 'DELETE FROM pending WHERE id=? AND stage=? AND expires_at>? RETURNING *' : 'UPDATE pending SET attempts=attempts+1 WHERE id=? AND stage=? AND expires_at>? AND attempts<5 RETURNING *';
    const value = await statement(sql, id, stage, clock()).first<Pending>();
    if (!value) return fail();
    return value;
  }
  async function issuePending(stage: string, payload: unknown, body: Record<string, unknown>, userID: string | null = null): Promise<Response> {
    const raw = randomToken();
    await statement('INSERT INTO pending(id,user_id,stage,payload,expires_at) VALUES(?,?,?,?,?)', await tokenHash('pending:' + raw), userID, stage, JSON.stringify(payload), clock() + pendingTTL).run();
    return json(body, 200, [cookie(pendingCookie, raw, pendingTTL / 1000)]);
  }
  async function session(request: Request, csrf = false, fresh = false): Promise<Session> {
    const raw = cookieValue(request, sessionCookie); if (!raw) return fail();
    const hash = await tokenHash('session:' + raw);
    const value = await statement('SELECT u.*,s.token_hash,s.mfa_at,s.expires_at FROM sessions s JOIN users u ON u.id=s.user_id WHERE s.token_hash=? AND s.expires_at>? AND s.auth_version=u.auth_version', hash, clock()).first<Session>();
    if (!value || (fresh && clock() - value.mfa_at > freshTTL)) return fail();
    if (csrf && !equalText(request.headers.get('X-Spottr-CSRF') ?? '', await tokenHash('csrf:' + raw))) throw new AuthError(403, 'Refresh this page before trying again.');
    return value;
  }
  async function newSession(userID: string, authVersion: number): Promise<{ raw: string; hash: string; insert: Statement }> {
    const raw = randomToken(), hash = await tokenHash('session:' + raw);
    return { raw, hash, insert: statement('INSERT INTO sessions(token_hash,user_id,auth_version,mfa_at,expires_at) VALUES(?,?,?,?,?)', hash, userID, authVersion, clock(), clock() + sessionTTL) };
  }
  async function signedIn(raw: string, extras: Record<string, unknown> = {}): Promise<Response> {
    return json({ authenticated: true, csrf: await tokenHash('csrf:' + raw), ...extras }, 200, [cookie(sessionCookie, raw, sessionTTL / 1000), cookie(pendingCookie, '', 0)]);
  }
  async function backupStatements(userID: string, codes: string[]): Promise<Statement[]> {
    return Promise.all(codes.map(async code => statement('INSERT INTO backup_codes(code_hash,user_id) VALUES(?,?)', await tokenHash('backup:' + userID + ':' + normalizeRecovery(code)), userID)));
  }
  function setup(secret: string, username: string): Record<string, unknown> {
    return { needsAuthenticator: true, secret, uri: `otpauth://totp/${encodeURIComponent('Spottr:' + username)}?secret=${secret}&issuer=Spottr&algorithm=SHA1&digits=6&period=30` };
  }
  async function rateLimit(request: Request): Promise<void> {
    const ip = request.headers.get('CF-Connecting-IP') ?? 'local';
    const bucket = Math.floor(clock() / 600_000);
    const id = await tokenHash('rate:' + ip + ':' + bucket);
    const row = await statement('INSERT INTO rate_limits(id,count,expires_at) VALUES(?,1,?) ON CONFLICT(id) DO UPDATE SET count=count+1 RETURNING count', id, (bucket + 1) * 600_000).first<{ count: number }>();
    if (!row || row.count > 60) throw new AuthError(429, 'Too many attempts. Wait ten minutes before trying again.');
  }
  return async request => {
    try {
      const url = new URL(request.url), path = url.pathname;
      if (url.origin !== env.ORIGIN || request.headers.get('Sec-Fetch-Site') === 'cross-site') throw new AuthError(403, 'Use Spottr on its own website.');
      if (request.method === 'GET' && path === '/api/auth/session') {
        const current = await session(request);
        const raw = cookieValue(request, sessionCookie) ?? '';
        const backups = await statement('SELECT COUNT(*) AS count FROM backup_codes WHERE user_id=?', current.id).first<{ count: number }>();
        return json({ authenticated: true, username: current.username, createdAt: current.created_at, sessionExpiresAt: current.expires_at, backupCodesRemaining: backups?.count ?? 0, csrf: await tokenHash('csrf:' + raw) });
      }
      if (request.method === 'GET' && path === '/api/account/export') {
        const current = await session(request);
        const credentials = await statement('SELECT id,counter FROM credentials WHERE user_id=?', current.id).all<{ id: string; counter: number }>();
        return json({ username: current.username, createdAt: current.created_at, passkeys: credentials.results, storedWorkoutData: false, storedHealthData: false });
      }
      if (request.method !== 'POST') throw new AuthError(404, 'Page not found.');
      if (request.headers.get('Origin') !== env.ORIGIN) throw new AuthError(403, 'Use Spottr on its own website.');
      await rateLimit(request);
      const body = await readJSON(request);
      if (path === '/api/auth/register/options') {
        const username = z.object({ username: z.string().trim().toLowerCase().regex(/^[a-z0-9][a-z0-9_-]{2,31}$/) }).parse(body).username;
        await cleanup(env, clock());
        if (await statement('SELECT id FROM users WHERE username=?', username).first()) throw new AuthError(409, 'Choose another username.');
        const userID = crypto.randomUUID();
        const options = await generateRegistrationOptions({ rpName: 'Spottr', rpID, userID: new TextEncoder().encode(userID), userName: username, attestationType: 'none', supportedAlgorithmIDs: [-7, -257], authenticatorSelection: { residentKey: 'required', userVerification: 'required' } });
        return issuePending('registration', { userID, username, challenge: options.challenge }, { options });
      }
      if (path === '/api/auth/register/verify') {
        const proof = registrationPending.parse(JSON.parse((await pending(request, 'registration', true)).payload));
        const response = registrationSchema.parse(z.object({ credential: registrationSchema }).parse(body).credential);
        let result;
        try { result = await verifyRegistrationResponse({ response, expectedChallenge: proof.challenge, expectedOrigin: env.ORIGIN, expectedRPID: rpID, requireUserVerification: true }); } catch { return fail(); }
        if (!result.verified || !result.registrationInfo) return fail();
        const credential = result.registrationInfo.credential;
        const secret = newTOTPSecret();
        const payload = { ...proof, cipher: await encryptSecret(secret, env.AUTH_ENCRYPTION_KEY, proof.userID), credential: { id: credential.id, publicKey: bytesToBase64URL(credential.publicKey), counter: credential.counter } };
        return issuePending('enrollment', payload, setup(secret, proof.username));
      }
      if (path === '/api/auth/enroll') {
        const record = await pending(request, 'enrollment');
        const proof = enrollmentPending.parse(JSON.parse(record.payload));
        const code = z.object({ code: z.string().max(20) }).parse(body).code;
        const step = await verifyTOTP(await decryptSecret(proof.cipher, env.AUTH_ENCRYPTION_KEY, proof.userID), code, clock());
        if (step === null) return fail();
        if (!await statement('DELETE FROM pending WHERE id=? AND stage=? AND expires_at>? RETURNING id', record.id, 'enrollment', clock()).first()) return fail();
        const codes = recoveryCodes(), next = await newSession(proof.userID, 1);
        try {
          await env.DB.batch([
            statement('INSERT INTO users(id,username,totp_cipher,last_totp_step,auth_version,created_at) VALUES(?,?,?,?,1,?)', proof.userID, proof.username, proof.cipher, step, clock()),
            statement('INSERT INTO credentials(id,user_id,public_key,counter) VALUES(?,?,?,?)', proof.credential.id, proof.userID, proof.credential.publicKey, proof.credential.counter),
            ...await backupStatements(proof.userID, codes), next.insert
          ]);
        } catch { throw new AuthError(409, 'Setup could not finish. Start again with another username.'); }
        return signedIn(next.raw, { backupCodes: codes });
      }
      if (path === '/api/auth/login/options') {
        await cleanup(env, clock());
        const options = await generateAuthenticationOptions({ rpID, userVerification: 'required' });
        return issuePending('login', { challenge: options.challenge }, { options });
      }
      if (path === '/api/auth/login/verify') {
        const proof = z.object({ challenge: z.string() }).parse(JSON.parse((await pending(request, 'login', true)).payload));
        const response = z.object({ credential: authenticationSchema }).parse(body).credential;
        const credential = await statement('SELECT c.id,c.user_id,c.public_key,c.counter,u.auth_version FROM credentials c JOIN users u ON c.user_id=u.id WHERE c.id=?', response.id).first<{ id: string; user_id: string; public_key: string; counter: number; auth_version: number }>();
        if (!credential || response.response.userHandle !== bytesToBase64URL(new TextEncoder().encode(credential.user_id))) return fail();
        let result;
        try { result = await verifyAuthenticationResponse({ response, expectedChallenge: proof.challenge, expectedOrigin: env.ORIGIN, expectedRPID: rpID, requireUserVerification: true, credential: { id: credential.id, publicKey: base64URLToBytes(credential.public_key), counter: credential.counter } }); } catch { return fail(); }
        if (!result.verified) return fail();
        const updated = await statement('UPDATE credentials SET counter=? WHERE id=? AND counter=?', result.authenticationInfo.newCounter, credential.id, credential.counter).run();
        if (updated.meta.changes !== 1) return fail();
        return issuePending('mfa', { userID: credential.user_id, authVersion: credential.auth_version, passkeyAt: clock() }, { needsSecondFactor: true }, credential.user_id);
      }
      if (path === '/api/auth/mfa') {
        const record = await pending(request, 'mfa');
        const proof = loginPending.parse(JSON.parse(record.payload));
        const input = z.object({ code: z.string().max(20).optional(), backupCode: z.string().max(64).optional() }).parse(body);
        if (Boolean(input.code) === Boolean(input.backupCode)) return fail();
        const user = await statement('SELECT * FROM users WHERE id=? AND auth_version=?', proof.userID, proof.authVersion).first<User>();
        if (!user || clock() - proof.passkeyAt > pendingTTL) return fail();
        const next = await newSession(user.id, user.auth_version);
        let insert: Statement, spend: Statement;
        if (input.backupCode) {
          const hash = await tokenHash('backup:' + user.id + ':' + normalizeRecovery(input.backupCode));
          insert = statement('INSERT INTO sessions(token_hash,user_id,auth_version,mfa_at,expires_at) SELECT ?,u.id,u.auth_version,?,? FROM users u WHERE u.id=? AND u.auth_version=? AND EXISTS(SELECT 1 FROM backup_codes WHERE code_hash=? AND user_id=u.id) AND EXISTS(SELECT 1 FROM pending WHERE id=? AND expires_at>?)', next.hash, clock(), clock()+sessionTTL, user.id, user.auth_version, hash, record.id, clock());
          spend = statement('DELETE FROM backup_codes WHERE code_hash=? AND user_id=? AND EXISTS(SELECT 1 FROM sessions WHERE token_hash=?)', hash, user.id, next.hash);
        } else {
          const step = await verifyTOTP(await decryptSecret(user.totp_cipher, env.AUTH_ENCRYPTION_KEY, user.id), input.code ?? '', clock());
          if (step === null) return fail();
          insert = statement('INSERT INTO sessions(token_hash,user_id,auth_version,mfa_at,expires_at) SELECT ?,u.id,u.auth_version,?,? FROM users u WHERE u.id=? AND u.auth_version=? AND u.last_totp_step<? AND EXISTS(SELECT 1 FROM pending WHERE id=? AND expires_at>?)', next.hash, clock(), clock()+sessionTTL, user.id, user.auth_version, step, record.id, clock());
          spend = statement('UPDATE users SET last_totp_step=? WHERE id=? AND EXISTS(SELECT 1 FROM sessions WHERE token_hash=?)', step, user.id, next.hash);
        }
        const results = await env.DB.batch([insert, spend, statement('DELETE FROM pending WHERE id=? AND EXISTS(SELECT 1 FROM sessions WHERE token_hash=?)', record.id, next.hash)]);
        if (results[0]?.meta.changes !== 1) return fail();
        return signedIn(next.raw, { usedBackupCode: Boolean(input.backupCode) });
      }
      if (path === '/api/auth/logout') {
        const current = await session(request, true);
        await statement('DELETE FROM sessions WHERE token_hash=?', current.token_hash).run();
        return json({ signedOut: true }, 200, [cookie(sessionCookie, '', 0), cookie(pendingCookie, '', 0)]);
      }
      if (path === '/api/account/backup-codes') {
        const current = await session(request, true, true), codes = recoveryCodes();
        const guard = 'EXISTS(SELECT 1 FROM users u JOIN sessions s ON s.user_id=u.id WHERE u.id=? AND u.auth_version=? AND s.auth_version=u.auth_version AND s.token_hash=? AND s.expires_at>? AND s.mfa_at>=?)';
        const authorization = [current.id, current.auth_version, current.token_hash, clock(), clock()-freshTTL];
        const inserts = await Promise.all(codes.map(async code => statement(`INSERT INTO backup_codes(code_hash,user_id) SELECT ?,? WHERE ${guard}`, await tokenHash('backup:' + current.id + ':' + normalizeRecovery(code)), current.id, ...authorization)));
        const results = await env.DB.batch([statement(`DELETE FROM backup_codes WHERE user_id=? AND ${guard}`, current.id, ...authorization), ...inserts]);
        if (results.at(-1)?.meta.changes !== 1) return fail();
        return json({ backupCodes: codes });
      }
      if (path === '/api/account/authenticator/options') {
        const current = await session(request, true, true), secret = newTOTPSecret();
        return issuePending('replacement', { userID: current.id, authVersion: current.auth_version, cipher: await encryptSecret(secret, env.AUTH_ENCRYPTION_KEY, current.id) }, setup(secret, current.username), current.id);
      }
      if (path === '/api/account/authenticator/verify') {
        const current = await session(request, true, true), record = await pending(request, 'replacement');
        const proof = replacementPending.parse(JSON.parse(record.payload));
        if (proof.userID !== current.id || proof.authVersion !== current.auth_version) return fail();
        const step = await verifyTOTP(await decryptSecret(proof.cipher, env.AUTH_ENCRYPTION_KEY, proof.userID), z.object({code:z.string().max(20)}).parse(body).code, clock());
        if (step === null) return fail();
        if (!await statement('DELETE FROM pending WHERE id=? AND expires_at>? RETURNING id', record.id, clock()).first()) return fail();
        const codes = recoveryCodes(), next = await newSession(current.id, current.auth_version + 1);
        const marker = 'EXISTS(SELECT 1 FROM users WHERE id=? AND auth_version=? AND totp_cipher=?)';
        const ownership = [current.id, current.auth_version + 1, proof.cipher];
        const inserts = await Promise.all(codes.map(async code => statement(`INSERT INTO backup_codes(code_hash,user_id) SELECT ?,? WHERE ${marker}`, await tokenHash('backup:' + current.id + ':' + normalizeRecovery(code)), current.id, ...ownership)));
        const results = await env.DB.batch([
          statement('UPDATE users SET totp_cipher=?,last_totp_step=?,auth_version=auth_version+1 WHERE id=? AND auth_version=? AND EXISTS(SELECT 1 FROM sessions WHERE token_hash=? AND auth_version=? AND expires_at>? AND mfa_at>=?)', proof.cipher, step, current.id, current.auth_version, current.token_hash, current.auth_version, clock(), clock()-freshTTL),
          statement(`DELETE FROM sessions WHERE user_id=? AND ${marker}`, current.id, ...ownership),
          statement(`DELETE FROM backup_codes WHERE user_id=? AND ${marker}`, current.id, ...ownership),
          ...inserts,
          statement(`INSERT INTO sessions(token_hash,user_id,auth_version,mfa_at,expires_at) SELECT ?,?,?,?,? WHERE ${marker}`, next.hash, current.id, current.auth_version+1, clock(), clock()+sessionTTL, ...ownership)
        ]);
        if (results[0]?.meta.changes !== 1) return fail();
        return signedIn(next.raw, { backupCodes: codes });
      }
      if (path === '/api/account/delete') {
        const current = await session(request, true, true);
        if (z.object({confirm:z.literal('DELETE')}).parse(body).confirm !== 'DELETE') return fail();
        const identities = await statement("SELECT subject,provider_cipher FROM native_identities WHERE user_id=? AND provider='apple'", current.id).all<{subject:string;provider_cipher:string}>();
        for (const identity of identities.results) await revokeApple(context(env,{clock,fetch:fetcher}),identity.subject,identity.provider_cipher);
        const deleted = await statement('DELETE FROM users WHERE id=? AND auth_version=? AND EXISTS(SELECT 1 FROM sessions WHERE token_hash=? AND auth_version=? AND expires_at>? AND mfa_at>=?) RETURNING id', current.id, current.auth_version, current.token_hash, current.auth_version, clock(), clock()-freshTTL).first<{id:string}>();
        if (!deleted) return fail();
        return json({ deleted: true, phoneHistoryUnchanged: true }, 200, [cookie(sessionCookie,'',0),cookie(pendingCookie,'',0)]);
      }
      throw new AuthError(404, 'Page not found.');
    } catch (error) {
      if (error instanceof AuthError) return json({ error: error.message }, error.status);
      if (error instanceof z.ZodError) return json({ error: 'Check the information entered and try again.' }, 400);
      return json({ error: 'The account service is temporarily unavailable. Please try again later.' }, 503);
    }
  };
}

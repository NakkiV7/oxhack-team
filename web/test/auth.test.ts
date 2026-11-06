import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { Miniflare } from 'miniflare';
import { z } from 'zod';
import { createAuthHandler, type AuthEnv, type Database, type Statement } from '../src/auth.ts';
import { SoftwarePasskey } from './passkey.ts';
import { totp } from '../src/crypto.ts';

const origin = 'https://spottr.example';
const dictionary = z.record(z.string(), z.unknown());
async function fixture() {
  const mf = new Miniflare({ modules: true, script: 'export default { fetch() { return new Response("test"); }}', d1Databases: ['DB'] });
  const db = await mf.getD1Database('DB');
  await db.exec((await readFile(new URL('../migrations/0001_accounts.sql', import.meta.url), 'utf8')).replace(/\n/g, ' '));
  await db.exec((await readFile(new URL('../migrations/0002_native_accounts.sql', import.meta.url), 'utf8')).replace(/\n/g, ' '));
  let afterSessionRead: (() => Promise<void>) | null = null;
  const originals = new WeakMap<Statement, Statement>();
  const instrument = (real: Statement, sql: string): Statement => {
    const wrapped: Statement = {
      bind: (...args) => instrument(real.bind(...args), sql),
      first: async <T>() => {
        const value = await real.first<T>();
        if (sql.startsWith('SELECT u.*,s.token_hash') && afterSessionRead) {
          const action = afterSessionRead; afterSessionRead = null; await action();
        }
        return value;
      },
      all: <T>() => real.all<T>(), run: () => real.run()
    };
    originals.set(wrapped, real); return wrapped;
  };
  const database: Database = { prepare: sql => instrument(db.prepare(sql), sql), batch: values => db.batch(values.map(v => originals.get(v) ?? v)) };
  const env: AuthEnv = { DB: database, ORIGIN: origin, AUTH_ENCRYPTION_KEY: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA', AUTH_TOKEN_PEPPER: 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB' };
  let now = 1_800_000_000_000;
  const handle = createAuthHandler(env, () => now);
  let cookies = new Map<string, string>();
  let csrf = '';
  async function request(path: string, body?: unknown, extra: Record<string, string> = {}) {
    const headers: Record<string, string> = { Origin: origin, Cookie: Array.from(cookies, ([k,v]) => `${k}=${v}`).join('; '), ...extra };
    if (body !== undefined) headers['Content-Type'] = 'application/json';
    if (csrf) headers['X-Spottr-CSRF'] = csrf;
    const response = await handle(new Request(origin + path, { method: body === undefined ? 'GET' : 'POST', headers, body: body === undefined ? undefined : JSON.stringify(body) }));
    for (const value of response.headers.getSetCookie()) {
      const pair = value.split(';')[0] ?? '';
      const i = pair.indexOf('='); if (i > 0) cookies.set(pair.slice(0,i), pair.slice(i+1));
    }
    const json = dictionary.parse(await response.json());
    if (typeof json['csrf'] === 'string') csrf = json['csrf'];
    return { response, json };
  }
  async function enroll(name = 'tester') {
    const passkey = await SoftwarePasskey.create();
    const start = await request('/api/auth/register/options', { username: name });
    assert.equal(start.response.status, 200);
    const opts = z.object({ challenge: z.string(), user: z.object({ id: z.string() }) }).parse(start.json['options']);
    const verified = await request('/api/auth/register/verify', { credential: await passkey.registration(opts.challenge, opts.user.id, origin) });
    assert.equal(verified.response.status, 200);
    const secret = z.string().parse(verified.json['secret']);
    const notSignedIn = await request('/api/auth/session'); assert.equal(notSignedIn.response.status, 401);
    const finished = await request('/api/auth/enroll', { code: await totp(secret, now) });
    assert.equal(finished.response.status, 200);
    const backups = z.array(z.string()).parse(finished.json['backupCodes']);
    return { passkey, secret, backups };
  }
  async function provePasskey(passkey: SoftwarePasskey) {
    const options = await request('/api/auth/login/options', {});
    const challenge = z.object({ challenge: z.string() }).parse(options.json['options']).challenge;
    return request('/api/auth/login/verify', { credential: await passkey.authentication(challenge, origin) });
  }
  return { mf, db, handle, request, enroll, provePasskey, afterSession: (action: () => Promise<void>) => { afterSessionRead = action; }, advance: (seconds: number) => { now += seconds * 1000; }, get now() { return now; }, clear: () => { cookies = new Map(); csrf = ''; }, cookies: () => new Map(cookies) };
}

test('registration needs passkey and Authenticator and stores no raw session/backup/seed', async () => {
  const f = await fixture();
  try {
    const { secret, backups } = await f.enroll();
    const session = await f.request('/api/auth/session'); assert.equal(session.response.status, 200);
    assert.equal(session.json['username'], 'tester'); assert.equal(session.json['backupCodesRemaining'], 10);
    const users = await f.db.prepare('SELECT * FROM users').all();
    const sessions = await f.db.prepare('SELECT * FROM sessions').all();
    const codes = await f.db.prepare('SELECT * FROM backup_codes').all();
    const stored = JSON.stringify([users.results, sessions.results, codes.results]);
    assert.ok(!stored.includes(secret)); assert.ok(!stored.includes(backups[0] ?? 'missing'));
    assert.ok(!stored.includes(f.cookies().get('__Host-spottr_session') ?? 'missing'));
    assert.match(session.response.headers.get('Cache-Control') ?? '', /no-store/);
    assert.match(session.response.headers.get('Content-Security-Policy') ?? '', /default-src 'none'/);
  } finally { await f.mf.dispose(); }
});
test('every login requires both factors and a TOTP step cannot be replayed', async () => {
  const f = await fixture();
  try {
    const { passkey, secret } = await f.enroll();
    await f.request('/api/auth/logout', {}); f.clear();
    assert.equal((await f.provePasskey(passkey)).response.status, 200);
    assert.equal((await f.request('/api/auth/session')).response.status, 401);
    assert.equal((await f.request('/api/auth/mfa', { code: await totp(secret, f.now) })).response.status, 401);
    f.advance(30);
    assert.equal((await f.request('/api/auth/mfa', { code: await totp(secret, f.now) })).response.status, 200);
    assert.equal((await f.request('/api/auth/session')).response.status, 200);
    f.advance(12 * 3600 + 1);
    assert.equal((await f.request('/api/auth/session')).response.status, 401);
  } finally { await f.mf.dispose(); }
});
test('backup codes can replace only the second factor and only once', async () => {
  const f = await fixture();
  try {
    const { passkey, backups } = await f.enroll();
    await f.request('/api/auth/logout', {}); f.clear();
    assert.equal((await f.request('/api/auth/mfa', { backupCode: backups[0] })).response.status, 401);
    await f.provePasskey(passkey);
    assert.equal((await f.request('/api/auth/mfa', { backupCode: backups[0] })).response.status, 200);
    await f.request('/api/auth/logout', {}); f.clear(); await f.provePasskey(passkey);
    assert.equal((await f.request('/api/auth/mfa', { backupCode: backups[0] })).response.status, 401);
  } finally { await f.mf.dispose(); }
});
test('challenge replay, wrong origin and unverified authenticator are rejected', async () => {
  const f = await fixture();
  try {
    const passkey = await SoftwarePasskey.create();
    const start = await f.request('/api/auth/register/options', { username: 'security' });
    const options = z.object({ challenge: z.string(), user: z.object({ id: z.string() }) }).parse(start.json['options']);
    const bad = await f.request('/api/auth/register/verify', { credential: await passkey.registration(options.challenge, options.user.id, origin, false) });
    assert.equal(bad.response.status, 401);
    const replay = await f.request('/api/auth/register/verify', { credential: await passkey.registration(options.challenge, options.user.id, origin) });
    assert.equal(replay.response.status, 401);
    const cross = await f.request('/api/auth/login/options', {}, { Origin: 'https://evil.example' }); assert.equal(cross.response.status, 403);
  } finally { await f.mf.dispose(); }
});
test('state changes need CSRF and deletion needs fresh two-factor proof', async () => {
  const f = await fixture();
  try {
    await f.enroll();
    const forged = await f.handle(new Request(origin + '/api/account/delete', { method: 'POST', headers: { Origin: origin, 'Content-Type': 'application/json', Cookie: Array.from(f.cookies(), ([k,v]) => `${k}=${v}`).join('; ') }, body: JSON.stringify({ confirm: 'DELETE' }) }));
    assert.equal(forged.status, 403);
    f.advance(301);
    assert.equal((await f.request('/api/account/delete', { confirm: 'DELETE' })).response.status, 401);
  } finally { await f.mf.dispose(); }
});
test('deletion removes credentials, backups and sessions and does not remove local phone history', async () => {
  const f = await fixture();
  try {
    await f.enroll();
    assert.equal((await f.request('/api/account/delete', { confirm: 'DELETE' })).response.status, 200);
    for (const table of ['users','credentials','backup_codes','sessions']) {
      const row = await f.db.prepare(`SELECT COUNT(*) AS count FROM ${table}`).first<{count:number}>(); assert.equal(row?.count, 0);
    }
    assert.equal((await f.request('/api/auth/session')).response.status, 401);
  } finally { await f.mf.dispose(); }
});

test('stale deletion never reports success after a concurrent authentication change', async () => {
  const f = await fixture();
  try {
    await f.enroll();
    f.afterSession(async () => { await f.db.prepare('UPDATE users SET auth_version=auth_version+1').run(); });
    const result = await f.request('/api/account/delete', { confirm: 'DELETE' });
    assert.equal(result.response.status, 401);
    assert.equal((await f.db.prepare('SELECT COUNT(*) AS count FROM users').first<{count:number}>())?.count, 1);
  } finally { await f.mf.dispose(); }
});
test('revoked sessions cannot rotate backup codes after their initial authorization read', async () => {
  const f = await fixture();
  try {
    await f.enroll();
    const before = await f.db.prepare('SELECT code_hash FROM backup_codes ORDER BY code_hash').all();
    f.afterSession(async () => { await f.db.prepare('DELETE FROM sessions').run(); });
    assert.equal((await f.request('/api/account/backup-codes', {})).response.status, 401);
    assert.deepEqual((await f.db.prepare('SELECT code_hash FROM backup_codes ORDER BY code_hash').all()).results, before.results);
  } finally { await f.mf.dispose(); }
});
test('stale Authenticator replacement cannot delete or replace newer authentication state', async () => {
  const f = await fixture();
  try {
    await f.enroll();
    const setup = await f.request('/api/account/authenticator/options', {});
    const secret = z.string().parse(setup.json['secret']);
    const before = await f.db.prepare('SELECT totp_cipher FROM users').first<{totp_cipher:string}>();
    const backups = await f.db.prepare('SELECT code_hash FROM backup_codes ORDER BY code_hash').all();
    f.afterSession(async () => { await f.db.prepare('UPDATE users SET auth_version=auth_version+1').run(); });
    assert.equal((await f.request('/api/account/authenticator/verify', { code: await totp(secret, f.now) })).response.status, 401);
    const after = await f.db.prepare('SELECT totp_cipher,auth_version FROM users').first<{totp_cipher:string;auth_version:number}>();
    assert.equal(after?.auth_version, 2); assert.equal(after?.totp_cipher, before?.totp_cipher);
    assert.deepEqual((await f.db.prepare('SELECT code_hash FROM backup_codes ORDER BY code_hash').all()).results, backups.results);
  } finally { await f.mf.dispose(); }
});

test('Authenticator replacement signs in with the new seed and revokes old sessions and recovery codes', async () => {
  const f = await fixture();
  try {
    const { passkey, backups } = await f.enroll();
    const oldCookies = Array.from(f.cookies(), ([k,v]) => `${k}=${v}`).join('; ');
    const setup = await f.request('/api/account/authenticator/options', {});
    const secret = z.string().parse(setup.json['secret']);
    const replacement = await f.request('/api/account/authenticator/verify', { code: await totp(secret, f.now) });
    assert.equal(replacement.response.status, 200);
    const newBackups = z.array(z.string()).parse(replacement.json['backupCodes']);
    assert.equal(newBackups.length, 10);
    assert.equal((await f.request('/api/auth/session')).response.status, 200);
    assert.equal((await f.handle(new Request(origin + '/api/auth/session', { headers: { Cookie: oldCookies } }))).status, 401);
    await f.request('/api/auth/logout', {}); f.clear();
    await f.provePasskey(passkey);
    assert.equal((await f.request('/api/auth/mfa', { backupCode: backups[0] })).response.status, 401);
    f.advance(30);
    assert.equal((await f.request('/api/auth/mfa', { code: await totp(secret, f.now) })).response.status, 200);
    await f.request('/api/auth/logout', {}); f.clear();
    await f.provePasskey(passkey);
    assert.equal((await f.request('/api/auth/mfa', { backupCode: newBackups[0] })).response.status, 200);
  } finally { await f.mf.dispose(); }
});

test('rotating backup codes invalidates the old set while preserving the current session', async () => {
  const f = await fixture();
  try {
    const { passkey, backups } = await f.enroll();
    const rotated = await f.request('/api/account/backup-codes', {});
    assert.equal(rotated.response.status, 200);
    const newBackups = z.array(z.string()).parse(rotated.json['backupCodes']);
    assert.equal(newBackups.length, 10);
    assert.equal((await f.request('/api/auth/session')).response.status, 200);
    await f.request('/api/auth/logout', {}); f.clear();
    await f.provePasskey(passkey);
    assert.equal((await f.request('/api/auth/mfa', { backupCode: backups[0] })).response.status, 401);
    assert.equal((await f.request('/api/auth/mfa', { backupCode: newBackups[0] })).response.status, 200);
    assert.equal((await f.request('/api/auth/session')).json['backupCodesRemaining'], 9);
  } finally { await f.mf.dispose(); }
});

test('concurrent sign-ins using one backup code issue exactly one authenticated session', async () => {
  const f = await fixture();
  try {
    const { passkey, backups } = await f.enroll();
    await f.request('/api/auth/logout', {}); f.clear();
    await f.provePasskey(passkey);
    const firstCookies = Array.from(f.cookies(), ([k,v]) => `${k}=${v}`).join('; ');
    await f.provePasskey(passkey);
    const secondCookies = Array.from(f.cookies(), ([k,v]) => `${k}=${v}`).join('; ');
    const responses = await Promise.all([firstCookies, secondCookies].map(Cookie => f.handle(new Request(origin + '/api/auth/mfa', {
      method: 'POST', headers: { Cookie, Origin: origin, 'Content-Type': 'application/json' }, body: JSON.stringify({ backupCode: backups[0] })
    }))));
    assert.deepEqual(responses.map(response => response.status).sort(), [200, 401]);
    const winner = responses.find(response => response.status === 200);
    assert.ok(winner);
    const sessionCookies = winner.headers.getSetCookie().map(value => value.split(';')[0]).join('; ');
    assert.equal((await f.handle(new Request(origin + '/api/auth/session', { headers: { Cookie: sessionCookies } }))).status, 200);
    assert.equal((await f.db.prepare('SELECT COUNT(*) AS count FROM sessions').first<{count:number}>())?.count, 1);
    assert.equal((await f.db.prepare('SELECT COUNT(*) AS count FROM backup_codes').first<{count:number}>())?.count, 9);
  } finally { await f.mf.dispose(); }
});

test('five failed second-factor attempts exhaust that passkey proof', async () => {
  const f = await fixture();
  try {
    const { passkey, secret } = await f.enroll();
    await f.request('/api/auth/logout', {}); f.clear();
    await f.provePasskey(passkey); f.advance(30);
    for (let attempt = 0; attempt < 5; attempt += 1) {
      assert.equal((await f.request('/api/auth/mfa', { code: 'invalid' })).response.status, 401);
    }
    assert.equal((await f.request('/api/auth/mfa', { code: await totp(secret, f.now) })).response.status, 401);
    assert.equal((await f.request('/api/auth/session')).response.status, 401);
    await f.provePasskey(passkey);
    assert.equal((await f.request('/api/auth/mfa', { code: await totp(secret, f.now) })).response.status, 200);
  } finally { await f.mf.dispose(); }
});

test('expired passkey challenges and expired second-factor proofs cannot create a session', async () => {
  const f = await fixture();
  try {
    const { passkey, backups } = await f.enroll();
    await f.request('/api/auth/logout', {}); f.clear();
    const start = await f.request('/api/auth/login/options', {});
    const challenge = z.object({ challenge: z.string() }).parse(start.json['options']).challenge;
    const credential = await passkey.authentication(challenge, origin);
    f.advance(300);
    assert.equal((await f.request('/api/auth/login/verify', { credential })).response.status, 401);
    await f.provePasskey(passkey); f.advance(300);
    assert.equal((await f.request('/api/auth/mfa', { backupCode: backups[0] })).response.status, 401);
    assert.equal((await f.request('/api/auth/session')).response.status, 401);
    await f.provePasskey(passkey);
    assert.equal((await f.request('/api/auth/mfa', { backupCode: backups[0] })).response.status, 200);
  } finally { await f.mf.dispose(); }
});

test('the mutation rate limit rejects excess requests and recovers in the next window', async () => {
  const f = await fixture();
  try {
    for (let attempt = 0; attempt < 60; attempt += 1) {
      assert.equal((await f.request('/api/auth/login/options', {})).response.status, 200);
    }
    assert.equal((await f.request('/api/auth/login/options', {})).response.status, 429);
    f.advance(600);
    assert.equal((await f.request('/api/auth/login/options', {})).response.status, 200);
  } finally { await f.mf.dispose(); }
});

test('malformed and oversized account requests cannot create authentication state', async () => {
  const f = await fixture();
  try {
    for (const input of [
      { body: '{', type: 'application/json', expected: 400 },
      { body: new Uint8Array([255]), type: 'application/json', expected: 400 },
      { body: JSON.stringify({ username: 'x'.repeat(33_000) }), type: 'application/json', expected: 413 },
      { body: 'username=tester', type: 'application/x-www-form-urlencoded', expected: 415 }
    ]) {
      const response = await f.handle(new Request(origin+'/api/auth/register/options', { method: 'POST', headers: { Origin: origin, 'Content-Type': input.type }, body: input.body }));
      assert.equal(response.status, input.expected);
    }
    assert.equal((await f.db.prepare('SELECT COUNT(*) AS count FROM pending').first<{ count: number }>())?.count, 0);
    assert.equal((await f.db.prepare('SELECT COUNT(*) AS count FROM users').first<{ count: number }>())?.count, 0);
  } finally { await f.mf.dispose(); }
});

import test from 'node:test';
import assert from 'node:assert/strict';
import { totp, verifyTOTP, encryptSecret, decryptSecret, randomToken, hashToken, recoveryCodes } from '../src/crypto.ts';

const key = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
test('TOTP follows RFC6238 and accepts a bounded adjacent step only', async () => {
  const secret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';
  assert.equal(await totp(secret, 59_000), '287082');
  assert.equal(await verifyTOTP(secret, '287082', 59_000), 1);
  assert.equal(await verifyTOTP(secret, '287082', 89_000), 1);
  assert.equal(await verifyTOTP(secret, '287082', 120_000), null);
  assert.equal(await verifyTOTP(secret, '0000000', 59_000), null);
});
test('TOTP secrets are encrypted and bound to the correct account', async () => {
  const encrypted = await encryptSecret('PRIVATE-TOTP-SEED', key, 'account-a');
  assert.ok(!encrypted.includes('PRIVATE-TOTP-SEED'));
  assert.equal(await decryptSecret(encrypted, key, 'account-a'), 'PRIVATE-TOTP-SEED');
  await assert.rejects(decryptSecret(encrypted, key, 'account-b'));
  await assert.rejects(decryptSecret(encrypted.slice(0, -3) + 'xyz', key, 'account-a'));
});
test('session and backup values are high entropy and never stored as raw tokens', async () => {
  const token = randomToken();
  assert.ok(token.length >= 43);
  const hashed = await hashToken(token, key);
  assert.notEqual(hashed, token);
  assert.equal(await hashToken(token, key), hashed);
  assert.notEqual(await hashToken(randomToken(), key), hashed);
  const codes = recoveryCodes();
  assert.equal(codes.length, 10);
  assert.equal(new Set(codes).size, 10);
  assert.ok(codes.every(c => /^[A-F0-9]{5}(?:-[A-F0-9]{5}){3}$/.test(c)));
});

import { z } from 'zod';

const encoder = new TextEncoder();
export function bytesToBase64URL(bytes: Uint8Array): string {
  return btoa(Array.from(bytes, byte => String.fromCharCode(byte)).join('')).replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/, '');
}
export function base64URLToBytes(value: string): Uint8Array<ArrayBuffer> {
  if (!/^[A-Za-z0-9_-]+$/.test(value)) throw new Error('Invalid encoding');
  return Uint8Array.from(atob(value.replaceAll('-', '+').replaceAll('_', '/') + '='.repeat((4 - value.length % 4) % 4)), c => c.charCodeAt(0));
}
export function randomToken(bytes = 32): string { return bytesToBase64URL(crypto.getRandomValues(new Uint8Array(bytes))); }
export function equalText(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let difference = 0;
  for (let i = 0; i < a.length; i += 1) difference |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return difference === 0;
}
export async function hashToken(value: string, pepper: string): Promise<string> {
  const key = await crypto.subtle.importKey('raw', base64URLToBytes(pepper), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  return bytesToBase64URL(new Uint8Array(await crypto.subtle.sign('HMAC', key, encoder.encode(value))));
}
const base32Alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
export function base32(bytes: Uint8Array): string {
  let value = 0, bits = 0, result = '';
  for (const byte of bytes) {
    value = (value << 8) | byte; bits += 8;
    while (bits >= 5) { bits -= 5; result += base32Alphabet[(value >>> bits) & 31]; }
  }
  if (bits > 0) result += base32Alphabet[(value << (5 - bits)) & 31];
  return result;
}
function decodeBase32(value: string): Uint8Array<ArrayBuffer> {
  let accumulator = 0, bits = 0;
  const bytes: number[] = [];
  for (const char of value.toUpperCase().replace(/=+$/, '')) {
    const digit = base32Alphabet.indexOf(char);
    if (digit < 0) throw new Error('Invalid seed');
    accumulator = (accumulator << 5) | digit; bits += 5;
    if (bits >= 8) { bits -= 8; bytes.push((accumulator >>> bits) & 255); }
  }
  return new Uint8Array(bytes);
}
export function newTOTPSecret(): string { return base32(crypto.getRandomValues(new Uint8Array(20))); }
export async function totp(secret: string, timeMS: number): Promise<string> {
  if (!Number.isFinite(timeMS) || timeMS < 0) throw new Error('Invalid time');
  const counter = new ArrayBuffer(8);
  new DataView(counter).setBigUint64(0, BigInt(Math.floor(timeMS / 30_000)));
  const key = await crypto.subtle.importKey('raw', decodeBase32(secret), { name: 'HMAC', hash: 'SHA-1' }, false, ['sign']);
  const digest = new Uint8Array(await crypto.subtle.sign('HMAC', key, counter));
  const offset = (digest.at(-1) ?? 0) & 15;
  return String((new DataView(digest.buffer).getUint32(offset) & 0x7fff_ffff) % 1_000_000).padStart(6, '0');
}
export async function verifyTOTP(secret: string, code: string, timeMS: number): Promise<number | null> {
  if (!/^\d{6}$/.test(code)) return null;
  for (const drift of [0, -1, 1]) {
    const time = timeMS + drift * 30_000;
    if (time >= 0 && equalText(await totp(secret, time), code)) return Math.floor(time / 30_000);
  }
  return null;
}
const cipherSchema = z.object({ version: z.literal(1), iv: z.string(), ciphertext: z.string() });
async function encryptionKey(value: string): Promise<CryptoKey> {
  const bytes = base64URLToBytes(value);
  if (bytes.length !== 32) throw new Error('Invalid encryption configuration');
  return crypto.subtle.importKey('raw', bytes, 'AES-GCM', false, ['encrypt', 'decrypt']);
}
export async function encryptSecret(secret: string, keyValue: string, accountID: string): Promise<string> {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ciphertext = await crypto.subtle.encrypt({ name: 'AES-GCM', iv, additionalData: encoder.encode('spottr:totp:' + accountID) }, await encryptionKey(keyValue), encoder.encode(secret));
  return JSON.stringify({ version: 1, iv: bytesToBase64URL(iv), ciphertext: bytesToBase64URL(new Uint8Array(ciphertext)) });
}
export async function decryptSecret(encrypted: string, keyValue: string, accountID: string): Promise<string> {
  const value = cipherSchema.parse(JSON.parse(encrypted));
  const bytes = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: base64URLToBytes(value.iv), additionalData: encoder.encode('spottr:totp:' + accountID) }, await encryptionKey(keyValue), base64URLToBytes(value.ciphertext));
  return new TextDecoder().decode(bytes);
}
export function recoveryCodes(): string[] {
  return Array.from({ length: 10 }, () => {
    const text = Array.from(crypto.getRandomValues(new Uint8Array(10)), n => n.toString(16).padStart(2, '0')).join('').toUpperCase();
    return [text.slice(0, 5), text.slice(5, 10), text.slice(10, 15), text.slice(15)].join('-');
  });
}
export function normalizeRecovery(value: string): string { return value.replace(/[\s-]/g, '').toUpperCase(); }

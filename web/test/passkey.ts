import { isoCBOR } from '@simplewebauthn/server/helpers';
import type { RegistrationResponseJSON, AuthenticationResponseJSON } from '@simplewebauthn/server';
import { bytesToBase64URL, base64URLToBytes } from '../src/crypto.ts';

function join(...arrays: Uint8Array[]): Uint8Array<ArrayBuffer> {
  const result = new Uint8Array(arrays.reduce((n, a) => n + a.length, 0));
  let offset = 0;
  for (const a of arrays) { result.set(a, offset); offset += a.length; }
  return result;
}
function derSignature(raw: Uint8Array): Uint8Array<ArrayBuffer> {
  const integer = (bytes: Uint8Array): Uint8Array<ArrayBuffer> => {
    let start = 0;
    while (start < bytes.length - 1 && bytes[start] === 0) start += 1;
    const trimmed = bytes.slice(start);
    const positive = ((trimmed[0] ?? 0) & 0x80) !== 0 ? join(new Uint8Array([0]), trimmed) : trimmed;
    return join(new Uint8Array([2, positive.length]), positive);
  };
  const values = join(integer(raw.slice(0, 32)), integer(raw.slice(32)));
  return join(new Uint8Array([0x30, values.length]), values);
}
export class SoftwarePasskey {
  readonly id = crypto.getRandomValues(new Uint8Array(32));
  private counter = 0;
  private userID = '';
  private constructor(private readonly keys: CryptoKeyPair) {}
  static async create(): Promise<SoftwarePasskey> {
    return new SoftwarePasskey(await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']));
  }
  async registration(challenge: string, userID: string, origin: string, verified = true): Promise<RegistrationResponseJSON> {
    this.userID = userID;
    const jwk = await crypto.subtle.exportKey('jwk', this.keys.publicKey);
    if (!jwk.x || !jwk.y) throw new Error('Missing curve coordinates');
    const cose = isoCBOR.encode(new Map<number, number | Uint8Array>([[1, 2], [3, -7], [-1, 1], [-2, base64URLToBytes(jwk.x)], [-3, base64URLToBytes(jwk.y)]]));
    const hash = new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(new URL(origin).hostname)));
    const length = new Uint8Array(2); new DataView(length.buffer).setUint16(0, this.id.length);
    const authData = join(hash, new Uint8Array([verified ? 0x45 : 0x41]), new Uint8Array(4), new Uint8Array(16), length, this.id, cose);
    const attestation = isoCBOR.encode(new Map<string, string | Uint8Array | Map<string, never>>([['fmt', 'none'], ['attStmt', new Map<string, never>()], ['authData', authData]]));
    return { id: bytesToBase64URL(this.id), rawId: bytesToBase64URL(this.id), type: 'public-key', clientExtensionResults: {}, response: { attestationObject: bytesToBase64URL(attestation), clientDataJSON: bytesToBase64URL(new TextEncoder().encode(JSON.stringify({ type: 'webauthn.create', challenge, origin, crossOrigin: false }))), transports: ['internal'] } };
  }
  async authentication(challenge: string, origin: string, verified = true): Promise<AuthenticationResponseJSON> {
    this.counter += 1;
    const count = new Uint8Array(4); new DataView(count.buffer).setUint32(0, this.counter);
    const hash = new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(new URL(origin).hostname)));
    const authData = join(hash, new Uint8Array([verified ? 5 : 1]), count);
    const clientData = new TextEncoder().encode(JSON.stringify({ type: 'webauthn.get', challenge, origin, crossOrigin: false }));
    const clientHash = new Uint8Array(await crypto.subtle.digest('SHA-256', clientData));
    const signature = await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, this.keys.privateKey, join(authData, clientHash));
    return { id: bytesToBase64URL(this.id), rawId: bytesToBase64URL(this.id), type: 'public-key', clientExtensionResults: {}, response: { clientDataJSON: bytesToBase64URL(clientData), authenticatorData: bytesToBase64URL(authData), signature: bytesToBase64URL(derSignature(new Uint8Array(signature))), userHandle: this.userID } };
  }
}

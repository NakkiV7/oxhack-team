import { createHash } from 'node:crypto';
import { z } from 'zod';
import { GatewayError } from './errors.mjs';

export const voiceRequest = z.object({
  generationID: z.string().uuid(), sessionID: z.string().uuid(), cueID: z.string().uuid(), playbackToken: z.string().uuid(),
  voice: z.enum(['david', 'arnold']), priority: z.enum(['form', 'pacing', 'rest']),
  tone: z.enum(['calm', 'intense']).optional(),
  text: z.string().trim().min(1).max(500).refine(text => !/[\u0000-\u001f\u007f]/u.test(text)),
  expiresAt: z.iso.datetime({ precision: 3 })
}).strict().refine(data => data.tone !== 'intense' || data.voice === 'david' && data.priority === 'pacing');

const aliases = [['david', 'David', 'ELEVENLABS_DAVID_VOICE_ID'], ['arnold', 'Arnold', 'ELEVENLABS_ARNOLD_VOICE_ID']];
const validID = value => typeof value === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(value);
export const configuredVoices = env => env.ELEVENLABS_API_KEY ? aliases.filter(([, , key]) => validID(env[key])).map(([id, name]) => ({ id, name, ...(id === 'david' && validID(env.ELEVENLABS_DAVID_INTENSE_VOICE_ID) ? { tones: ['calm', 'intense'] } : {}) })) : [];
const failure = (status, code, message) => new GatewayError(status, code, message);

function validMP3(bytes) {
  let offset = 0;
  if (bytes.subarray(0, 3).toString('ascii') === 'ID3') {
    if (bytes.length < 10 || [...bytes.subarray(6, 10)].some(byte => byte & 0x80)) return false;
    offset = 10 + bytes.subarray(6, 10).reduce((size, byte) => (size << 7) | byte, 0);
    if (bytes[3] === 4 && (bytes[5] & 0x10)) offset += 10;
  }
  if (offset + 4 > bytes.length || bytes[offset] !== 0xff || (bytes[offset + 1] & 0xfe) !== 0xf2 ||
      (bytes[offset + 2] & 0x0c) !== 0) return false;
  const bitrate = [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0][bytes[offset + 2] >> 4];
  const frameLength = Math.floor(72_000 * bitrate / 22_050) + ((bytes[offset + 2] >> 1) & 1);
  return bitrate > 0 && offset + frameLength <= bytes.length;
}

export function createVoiceService({ env, fetchImpl, now }) {
  const cache = new Map();
  let cachedBytes = 0, active = false;
  const remove = key => { cachedBytes -= cache.get(key).audio.length; cache.delete(key); };
  return {
    async synthesize(data, { reserve, demoExpiresAt, signal: clientSignal } = {}) {
      if (demoExpiresAt !== undefined && now() >= demoExpiresAt) throw failure(503, 'demo_expired', 'The owner demo session has expired.');
      const expiresAt = Date.parse(data.expiresAt), remaining = expiresAt - now();
      if (!(remaining > 0 && remaining <= 6000)) throw failure(422, 'invalid_request', 'Voice requires the original future cue expiry within six seconds.');
      const keyName = data.tone === 'intense' ? 'ELEVENLABS_DAVID_INTENSE_VOICE_ID' : aliases.find(([id]) => id === data.voice)?.[2], voiceID = env[keyName];
      const timeout = Number(env.ELEVENLABS_TIMEOUT_MS ?? 5000);
      if (!env.ELEVENLABS_API_KEY || !validID(voiceID) || !Number.isInteger(timeout) || timeout < 1 || timeout > 6000) {
        throw failure(503, 'missing_configuration', 'Configure the selected account-enabled voice and a voice timeout from 1 to 6000 milliseconds.');
      }
      const key = createHash('sha256').update(`${voiceID}\0eleven_flash_v2_5\0${data.text}`).digest('hex');
      for (const [cachedKey, entry] of cache) if (now() >= entry.until) remove(cachedKey);
      const cached = cache.get(key);
      if (cached) { cache.delete(key); cache.set(key, cached); return cached.audio; }
      if (active) throw failure(429, 'voice_busy', 'One voice synthesis request is already active.');
      const release = reserve?.();
      active = true;
      const demoRemaining = demoExpiresAt === undefined ? Infinity : demoExpiresAt - now();
      const deadline = AbortSignal.timeout(Math.max(1, Math.min(timeout, remaining, demoRemaining)));
      const signal = clientSignal ? AbortSignal.any([deadline, clientSignal]) : deadline;
      let reader, onAbort;
      const timedOut = () => {
        if (clientSignal?.aborted) return failure(499, 'voice_cancelled', 'The voice request was cancelled.');
        if (demoExpiresAt !== undefined && (now() >= demoExpiresAt || demoRemaining <= Math.min(timeout, remaining))) return failure(503, 'demo_expired', 'The owner demo session has expired.');
        if (now() >= expiresAt || remaining <= timeout) return failure(409, 'voice_expired', 'The original cue has expired.');
        return failure(504, 'voice_timeout', 'Voice synthesis timed out.');
      };
      const aborted = new Promise((_, reject) => {
        onAbort = () => reject(timedOut());
        signal.addEventListener('abort', onAbort, { once: true });
        if (signal.aborted) onAbort();
      });
      try {
        const result = await Promise.race([fetchImpl(`https://api.elevenlabs.io/v1/text-to-speech/${encodeURIComponent(voiceID)}?output_format=mp3_22050_32`, {
          method: 'POST', redirect: 'error', signal,
          headers: { 'content-type': 'application/json', 'xi-api-key': env.ELEVENLABS_API_KEY },
          body: JSON.stringify({ text: data.text, model_id: 'eleven_flash_v2_5' })
        }), aborted]);
        if (!result.ok) { await result.body?.cancel(); throw failure(503, 'voice_unavailable', 'Voice synthesis is unavailable.'); }
        if (result.headers.get('content-type')?.split(';')[0].trim().toLowerCase() !== 'audio/mpeg') {
          await result.body?.cancel(); throw failure(502, 'invalid_voice_response', 'The voice audio failed validation.');
        }
        reader = result.body?.getReader();
        if (!reader) throw failure(502, 'invalid_voice_response', 'The voice audio failed validation.');
        const chunks = []; let size = 0;
        while (true) {
          const { done, value } = await Promise.race([reader.read(), aborted]);
          if (done) break;
          size += value.length;
          if (size > 262_144) throw failure(502, 'invalid_voice_response', 'The voice audio failed validation.');
          chunks.push(value);
        }
        if (signal.aborted || now() >= expiresAt || (demoExpiresAt !== undefined && now() >= demoExpiresAt)) throw timedOut();
        const audio = Buffer.concat(chunks);
        if (!validMP3(audio)) throw failure(502, 'invalid_voice_response', 'The voice audio failed validation.');
        cache.set(key, { audio, until: now() + 600_000 }); cachedBytes += audio.length;
        while (cache.size > 32 || cachedBytes > 4_194_304) remove(cache.keys().next().value);
        return audio;
      } catch (error) {
        if (signal.aborted) throw timedOut();
        if (error instanceof GatewayError) throw error;
        throw failure(503, 'voice_unavailable', 'Voice synthesis is unavailable.');
      } finally {
        signal.removeEventListener('abort', onAbort);
        if (reader) reader.cancel().catch(() => {});
        active = false; release?.();
      }
    }
  };
}

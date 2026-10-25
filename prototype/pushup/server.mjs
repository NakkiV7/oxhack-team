import http from 'node:http';
import os from 'node:os';
import { readFile, writeFile, rename, rm, mkdir } from 'node:fs/promises';
import { randomBytes, timingSafeEqual, createHash } from 'node:crypto';
import { createAsker } from './ask.mjs';
import { parseCsv } from './profile.mjs';
import { createProfileService } from './profile-service.mjs';
import { parseSync } from './sync.mjs';

const PORT = Number(process.env.PORT ?? 3001);
const cloudToken = randomBytes(32).toString('hex');
const userId = process.env.PUSHUP_USER_ID || 'local';

const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.mjs': 'text/javascript',
  '.js': 'text/javascript',
  '.wasm': 'application/wasm',
  '.task': 'application/octet-stream',
  '.mp4': 'video/mp4',
};

// URL prefix -> directory. Everything is served locally so only the first model download needs network.
const MOUNTS = {
  '/vendor/': new URL('./node_modules/@mediapipe/tasks-vision/', import.meta.url),
  '/models/': new URL('./models/', import.meta.url),
  '/assets/': new URL('./assets/', import.meta.url),   // tutorial videos
};

// Phone remote control (pause / resume / stop). The phone must send this code, which lives only on the Mac (.control-token,
// gitignored) and is shown on the Mac page and in the terminal. Wrong guesses lock an IP out for a minute.
const TOKEN_FILE = new URL('./.control-token', import.meta.url);
let controlToken = (await readFile(TOKEN_FILE, 'utf8').catch(() => '')).trim();
if (!/^[0-9a-f]{8}$/.test(controlToken)) {
  controlToken = randomBytes(4).toString('hex');
  await writeFile(TOKEN_FILE, controlToken + '\n', { mode: 0o600 });
}
const CONTROL_CMDS = new Set(['pause', 'resume', 'stop']);
const controlFails = new Map(); // ip -> { n, until }
const tokenOk = (given) => {
  const a = Buffer.from(String(given)), b = Buffer.from(controlToken);
  return a.length === b.length && timingSafeEqual(a, b);
};

// Live state from the Mac page, fanned out to phones (the pushup-ios app) over Server-Sent Events.
const clients = new Set();
const watchers = new Set(); // Mac page: coach text only (no video frames, no state)
let lastState = null;
const broadcast = (json) => {
  for (const res of clients) res.write(`data: ${json}\n\n`);
};
setInterval(() => { for (const res of [...clients, ...watchers]) res.write(': ping\n\n'); }, 3000);

// AI coach: occasionally asks Gemini for a short pep talk or tip based on the rep history. The key stays on the Mac (.env).
const GEMINI_KEY = process.env.GEMINI_API_KEY;
const GEMINI_MODEL = process.env.GEMINI_MODEL ?? 'gemini-3.5-flash';
const COACH_EVERY_REPS = 5;     // talk after every N reps...
const COACH_MIN_GAP_MS = 20000; // ...or after repeated bad form, but never more often than this
const coachLog = [];
// Questions asked to the coach, from any device. Kept here so every screen sees the same chat (in memory, last 50).
const qaLog = [];
let qaId = Date.now(); // starts at the clock so ids stay unique across server restarts
let coachBusy = false, coachLastAt = 0, coachLastTotal = 0, coachId = 0;

// Falls back to the lite model when the main one is overloaded, unavailable or slow. Returns null if both fail.
async function callGemini(body) {
  for (const model of [GEMINI_MODEL, 'gemini-3.5-flash-lite']) {
    try {
      const r = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'x-goog-api-key': GEMINI_KEY },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(25000),
      });
      if (r.ok) return await r.json();
      console.error(`gemini: ${model} -> ${r.status}`);
    } catch (e) {
      console.error(`gemini: ${model} -> ${e.message}`);
    }
  }
  return null;
}
// Spoken coach: ElevenLabs text-to-speech, synthesised once per line and cached on disk (voice_cache/, gitignored),
// so the live loop never waits on the API. The key stays on the Mac (.env). No key: the page keeps text only.
const ELEVEN_KEY = process.env.ELEVENLABS_API_KEY;
const ELEVEN_VOICE = process.env.ELEVENLABS_VOICE_ID ?? '2EiwWnXFnvU5JabPnv8n'; // "Clyde": gravelly, intense; a stock voice, not a clone
const VOICE_DIR = new URL('./voice_cache/', import.meta.url);
const voiceJobs = new Map(); // text -> in-flight promise, so a burst of requests makes one API call
let voiceList = null;        // [{ id, name }] from the account: custom voices first, then the default
async function listVoices() {
  if (voiceList) return voiceList;
  if (process.env.ELEVENLABS_VOICES) {   // "Name:voiceId,Name:voiceId" for keys without the voices_read permission
    voiceList = process.env.ELEVENLABS_VOICES.split(',').map((e) => e.trim()).filter(Boolean).map((e) => { const i = e.lastIndexOf(':'); return { name: e.slice(0, i).trim(), id: e.slice(i + 1).trim() }; });
    return voiceList;
  }
  const r = await fetch('https://api.elevenlabs.io/v1/voices', { headers: { 'xi-api-key': ELEVEN_KEY }, signal: AbortSignal.timeout(10000) }).catch(() => null);
  if (!r?.ok) {   // key without the voices_read permission: offer the configured default and remember that
    console.error(`voices: cannot list (${r ? r.status : 'network'}); using ELEVENLABS_VOICE_ID`);
    voiceList = [{ id: ELEVEN_VOICE, name: 'Coach' }];
    return voiceList;
  }
  const all = (await r.json()).voices ?? [];
  const mine = all.filter((v) => !['premade'].includes(v.category)).map((v) => ({ id: v.voice_id, name: v.name }));
  const def = all.find((v) => v.voice_id === ELEVEN_VOICE);
  voiceList = [...mine, ...(def && !mine.some((v) => v.id === def.voice_id) ? [{ id: def.voice_id, name: def.name }] : [])];
  return voiceList;
}
async function sayFile(text, voice = ELEVEN_VOICE) {
  const file = new URL(`${createHash('sha1').update(voice + '|' + text).digest('hex')}.mp3`, VOICE_DIR);
  try { return await readFile(file); } catch { /* not cached yet */ }
  const key = voice + '|' + text;
  if (!voiceJobs.has(key)) {
    voiceJobs.set(key, (async () => {
      const r = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${voice}?output_format=mp3_22050_32`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'xi-api-key': ELEVEN_KEY },
        body: JSON.stringify({ text, model_id: 'eleven_turbo_v2_5', voice_settings: { stability: 0.4, similarity_boost: 0.8, style: 0.6 } }),
        signal: AbortSignal.timeout(20000),
      });
      if (!r.ok) throw new Error(`elevenlabs ${r.status}`);
      const buf = Buffer.from(await r.arrayBuffer());
      await mkdir(VOICE_DIR, { recursive: true });
      await writeFile(file, buf);
      return buf;
    })().finally(() => voiceJobs.delete(key)));
  }
  return voiceJobs.get(key);
}


const ask = createAsker({ callGemini, secrets: [GEMINI_KEY, ELEVEN_KEY] });

const sendCoach = (msg) => {
  for (const res of [...clients, ...watchers]) res.write(`event: coach\ndata: ${JSON.stringify(msg)}\n\n`);
};
const sendQA = (entry) => {
  for (const res of [...clients, ...watchers]) res.write(`event: qa\ndata: ${JSON.stringify(entry)}\n\n`);
};

async function maybeCoach(s) {
  if (!GEMINI_KEY || coachBusy || !s?.running || s.total <= coachLastTotal) return;
  const recent = s.reps.slice(-5);
  const sloppy = recent.length >= 2 && recent.slice(-2).every((r) => !r.counted || !r.good);
  const due = s.total % COACH_EVERY_REPS === 0 || sloppy;
  if (!due || Date.now() - coachLastAt < COACH_MIN_GAP_MS) return;
  coachLastTotal = s.total;
  coachBusy = true;
  try {
    const lines = recent.map((r) => (r.counted
      ? `rep ${r.n}: ${r.good ? 'good form' : 'issue: ' + r.issue} (elbow ${r.minElbow}°, body line ${r.minLine}°)`
      : `not counted: ${r.issue}`));
    const prompt = `You are a ${s.persona || 'friendly, upbeat'} push-up coach speaking to someone mid-workout. Stay in that character; never claim to be a real person.
Exercise: ${s.label}. Reps counted: ${s.count} (${s.good} with good form).
Latest reps:\n${lines.join('\n')}
Reply with ONE or TWO short sentences (max 30 words): either a pep talk or one concrete form tip based on the issues above. Plain text, no markdown, no emoji.`;
    const data = await callGemini({
      contents: [{ parts: [{ text: prompt }] }],
      generationConfig: { maxOutputTokens: 1024, thinkingConfig: { thinkingLevel: 'low' } },
    });
    if (!data) return;
    const text = data.candidates?.[0]?.content?.parts?.map((p) => p.text).join('').trim();
    if (!text) return;
    const msg = { id: ++coachId, time: Date.now(), text, reps: s.total };
    coachLog.push(msg);
    if (coachLog.length > 50) coachLog.shift();
    sendCoach(msg);
  } catch (e) {
    console.error('coach:', e.message);
  } finally {
    coachLastAt = Date.now();
    coachBusy = false;
  }
}

// Personal profile: reads this user's reps from Tiger Data when a connection string is set, else from the mock CSV.
const PROFILE_FILE = new URL('./data/profile.json', import.meta.url);
let tigerPool = null;
async function tigerLib() { // loads pg only when Tiger is used; opens one shared pool
  const lib = await import('./tiger.mjs');
  tigerPool ??= await lib.createPool();
  return lib;
}
const hasTiger = () => !!(process.env.TIGER_DATABASE_URL || process.env.TIGER_DB_ADDRESS);
const profileService = createProfileService({
  async loadRows() {
    if (!hasTiger()) {
      const csv = await readFile(new URL('./data/history-demo.csv', import.meta.url), 'utf8').catch(() => readFile(new URL('./data/history.csv', import.meta.url), 'utf8'));
      return { rows: parseCsv(csv), where: 'mock CSV file', userId, selectedSources: ['mock'] };
    }
    const { readReps } = await tigerLib();
    const selectedSources = [...new Set((process.env.PUSHUP_SOURCES || 'mock,real').split(','))].sort();
    if (selectedSources.some((source) => !['mock', 'real'].includes(source))) throw new Error('PUSHUP_SOURCES must select mock or real');
    const rows = await readReps(tigerPool, { userId, sources: selectedSources });
    return { rows, where: 'Tiger Data', userId, selectedSources };
  },
  async save(profile) {
    const temporary = new URL(`./data/profile-${randomBytes(8).toString('hex')}.tmp`, import.meta.url);
    try {
      await writeFile(temporary, JSON.stringify(profile, null, 2) + '\n', { mode: 0o600, flag: 'wx' });
      await rename(temporary, PROFILE_FILE);
    } finally {
      await rm(temporary, { force: true });
    }
  },
  load: async () => {
    return JSON.parse(await readFile(PROFILE_FILE, 'utf8').catch(() => 'null'));
  },
});
const profileError = (res, e) => {
  const json = JSON.stringify({ error: e.message?.slice(0, 200) ?? 'Failed' });
  res.writeHead(502, { 'Content-Type': 'application/json' }).end(json);
};

const isLoopback = (req) => ['127.0.0.1', '::1', '::ffff:127.0.0.1'].includes(req.socket.remoteAddress);

const localOrigin = (req) => {
  const host = req.headers.host;
  if (!['localhost', '127.0.0.1', '[::1]'].some((name) => host === `${name}:${PORT}`)) return false;
  return !req.headers.origin || req.headers.origin === `http://${host}`;
};
const cloudAuthorized = (req) => {
  const given = Buffer.from(req.headers.authorization ?? '');
  const expected = Buffer.from(`Bearer ${cloudToken}`);
  return given.length === expected.length && timingSafeEqual(given, expected);
};

const readBody = (req) => new Promise((resolve, reject) => {
  let body = '';
  req.on('data', (c) => { body += c; if (body.length > 1e6) req.destroy(); });
  req.on('end', () => resolve(body));
  req.on('error', reject);
});

const server = http.createServer(async (req, res) => {
  try {
    const path = new URL(req.url, 'http://x').pathname;

    // The only routes reachable from other devices on the LAN: read-only state.
    if (req.method === 'GET' && path === '/events') {
      res.useChunkedEncodingByDefault = false; // raw body so the iOS client needs no chunk parsing
      res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache', Connection: 'close' });
      for (const m of coachLog) res.write(`event: coach\ndata: ${JSON.stringify(m)}\n\n`);
      for (const q of qaLog) res.write(`event: qa\ndata: ${JSON.stringify(q)}\n\n`);
      if (lastState) res.write(`data: ${lastState}\n\n`);
      else res.write(': connected\n\n');
      clients.add(res);
      req.on('close', () => clients.delete(res));
      return;
    }
    if (req.method === 'GET' && path === '/state') {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      return res.end(lastState ?? 'null');
    }

    // The one writable route open to the LAN: a short question for the coach. Rate limited and guarded in ask.mjs.
    if (req.method === 'POST' && path === '/ask') {
      let out;
      if (!GEMINI_KEY) out = { status: 503, body: { error: 'Coach is off: no GEMINI_API_KEY on the Mac' } };
      else {
        let q = null;
        try { q = JSON.parse(await readBody(req)).q; } catch { /* handled below */ }
        if (typeof q !== 'string') out = { status: 400, body: { error: 'Bad request' } };
        else {
          // Log the question right away (shown as pending on every device), then fill in the answer.
          const entry = { id: ++qaId, time: Date.now(), question: q.replace(/[\u0000-\u001f]/g, ' ').trim().slice(0, 256), answer: null, sources: [], failed: false };
          qaLog.push(entry);
          if (qaLog.length > 50) qaLog.shift();
          sendQA(entry);
          out = await ask(q, req.socket.remoteAddress);
          entry.answer = out.body.answer ?? out.body.error ?? 'No answer.';
          entry.sources = out.body.sources ?? [];
          entry.failed = !out.body.answer;
          sendQA(entry);
          out = { status: out.status, body: { ...out.body, id: entry.id } };
        }
      }
      const json = JSON.stringify(out.body);
      res.writeHead(out.status, { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(json), Connection: 'close' });
      return res.end(json);
    }

    // Second writable route open to the LAN: phone remote control. Needs the code; the Mac page does the actual work.
    if (req.method === 'POST' && path === '/control') {
      const ip = req.socket.remoteAddress;
      const f = controlFails.get(ip) ?? { n: 0, until: 0 };
      let out;
      if (Date.now() < f.until) out = { status: 429, body: { error: 'Too many wrong codes, wait a minute' } };
      else {
        let b = {};
        try { b = JSON.parse(await readBody(req)); } catch { /* handled below */ }
        if (!tokenOk(b.token ?? '')) {
          f.n += 1;
          if (f.n >= 5) { f.n = 0; f.until = Date.now() + 60000; }
          controlFails.set(ip, f);
          out = { status: 403, body: { error: 'Wrong control code' } };
        } else if (!CONTROL_CMDS.has(b.cmd)) out = { status: 400, body: { error: 'Bad command' } };
        else if (!watchers.size) out = { status: 503, body: { error: 'The Mac page is not open' } };
        else {
          controlFails.delete(ip);
          for (const w of watchers) w.write(`event: control\ndata: ${JSON.stringify({ cmd: b.cmd })}\n\n`);
          out = { status: 200, body: { ok: true } };
        }
      }
      const json = JSON.stringify(out.body);
      res.writeHead(out.status, { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(json), Connection: 'close' });
      return res.end(json);
    }

    // Everything else (page, assets, publishing state) is for the Mac itself.
    if (!isLoopback(req)) return res.writeHead(403).end();

    if (['/cloud-context', '/profile/status', '/profile/train', '/sync'].includes(path)) {
      if (!localOrigin(req)) return res.writeHead(403).end();
      if (req.method === 'POST') {
        if (!cloudAuthorized(req)) return res.writeHead(403).end();
        if (!/^application\/json(?:\s*;|$)/i.test(req.headers['content-type'] ?? '')) return res.writeHead(415).end();
      }
    }
    if (req.method === 'GET' && path === '/cloud-context') {
      return res.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' })
        .end(JSON.stringify({ userId, token: cloudToken, cloudAvailable: hasTiger() }));
    }

    if (req.method === 'GET' && path === '/profile/status') {
      let out;
      try { out = await profileService.status(); } catch (e) { return profileError(res, e); }
      return res.writeHead(200, { 'Content-Type': 'application/json' }).end(JSON.stringify(out));
    }
    if (req.method === 'POST' && path === '/profile/train') {
      let out;
      try { out = await profileService.train(); } catch (e) { return profileError(res, e); }
      return res.writeHead(200, { 'Content-Type': 'application/json' }).end(JSON.stringify(out));
    }

    // A finished camera workout from the page: stored in Tiger Data as real reps. Re-sending the same workout adds nothing.
    if (req.method === 'POST' && path === '/sync') {
      const send = (status, obj) => res.writeHead(status, { 'Content-Type': 'application/json' }).end(JSON.stringify(obj));
      if (!hasTiger()) return send(503, { error: 'Cloud sync is off: no TIGER_DATABASE_URL in .env' });
      let parsed;
      try {
        const body = JSON.parse(await readBody(req));
        if (body.cloudConsent !== true) throw new Error('Cloud upload requires approval');
        parsed = parseSync(body, { userId });
      } catch (e) { return send(422, { error: e.message.slice(0, 200) }); }
      try {
        const { insertReps } = await tigerLib();
        const saved = await insertReps(tigerPool, parsed.rows, { userId, source: 'real', workoutId: parsed.workoutId, contentHash: parsed.contentHash });
        return send(200, { ok: true, saved, total: parsed.rows.length, session: parsed.session, where: 'Tiger Data' });
      } catch (e) { return send(e.code === 'workout_conflict' ? 409 : 502, { error: e.code === 'workout_conflict' ? 'This workout was already saved with different content' : 'Cloud upload failed; keep the workout and retry later' }); }
    }

    if (req.method === 'GET' && path === '/control-code') return res.writeHead(200, { 'Content-Type': 'text/plain' }).end(controlToken);

    if (req.method === 'GET' && path === '/voices') {
      if (!ELEVEN_KEY) return res.writeHead(200, { 'Content-Type': 'application/json' }).end('[]');
      try { return res.writeHead(200, { 'Content-Type': 'application/json' }).end(JSON.stringify(await listVoices())); }
      catch (e) { console.error('voices:', e.message); return res.writeHead(200, { 'Content-Type': 'application/json' }).end(JSON.stringify([{ id: ELEVEN_VOICE, name: 'Coach' }])); }
    }
    if (req.method === 'GET' && path === '/say') {
      const q = new URL(req.url, 'http://x').searchParams;
      const text = (q.get('text') ?? '').replace(/[\u0000-\u001f]/g, ' ').trim().slice(0, 240);
      if (!ELEVEN_KEY) return res.writeHead(503).end();
      if (!text) return res.writeHead(400).end();
      try {
        const wanted = q.get('voice');
        const voices = await listVoices().catch(() => [{ id: ELEVEN_VOICE, name: 'Coach' }]);
        const voice = voices.some((v) => v.id === wanted) || /^[A-Za-z0-9]{10,}$/.test(wanted ?? '') ? wanted : voices[0]?.id ?? ELEVEN_VOICE;
        const buf = await sayFile(text, voice);
        res.writeHead(200, { 'Content-Type': 'audio/mpeg', 'Content-Length': buf.length, 'Cache-Control': 'max-age=86400' });
        return res.end(buf);
      } catch (e) { console.error('voice:', e.message); return res.writeHead(502).end(); }
    }

    if (req.method === 'GET' && path === '/coach-events') {
      res.useChunkedEncodingByDefault = false;
      res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache', Connection: 'close' });
      res.write(`event: status\ndata: ${JSON.stringify({ on: !!GEMINI_KEY, voice: !!ELEVEN_KEY })}\n\n`);
      for (const m of coachLog) res.write(`event: coach\ndata: ${JSON.stringify(m)}\n\n`);
      for (const q of qaLog) res.write(`event: qa\ndata: ${JSON.stringify(q)}\n\n`);
      watchers.add(res);
      req.on('close', () => watchers.delete(res));
      return;
    }

    if (req.method === 'POST' && path === '/state') {
      const body = await readBody(req);
      JSON.parse(body); // reject garbage
      lastState = body.replace(/\n/g, '');
      broadcast(lastState);
      const parsed = JSON.parse(body);
      if (parsed.total < coachLastTotal) coachLastTotal = parsed.total; // reps were reset
      maybeCoach(parsed);
      return res.writeHead(204).end();
    }

    if (req.method === 'POST' && path === '/frame') {
      const body = await readBody(req); // base64 JPEG, not stored: only forwarded to connected phones
      if (clients.size && /^[A-Za-z0-9+/=]+$/.test(body)) {
        for (const res of clients) res.write(`event: frame\ndata: ${body}\n\n`);
      }
      return res.writeHead(204).end();
    }

    let file = null;
    if (path === '/') file = new URL('./index.html', import.meta.url);
    else if (path === '/client-workout.mjs') file = new URL('./client-workout.mjs', import.meta.url);
    else if (path === '/pushup.mjs') file = new URL('./pushup.mjs', import.meta.url);
    else {
      for (const [prefix, dir] of Object.entries(MOUNTS)) {
        if (path.startsWith(prefix) && !path.includes('..')) file = new URL(path.slice(prefix.length), dir);
      }
    }
    if (!file) return res.writeHead(404).end();
    const ext = file.pathname.slice(file.pathname.lastIndexOf('.'));
    res.writeHead(200, { 'Content-Type': TYPES[ext] ?? 'application/octet-stream' });
    res.end(await readFile(file));
  } catch {
    if (!res.headersSent) res.writeHead(400);
    res.end();
  }
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(GEMINI_KEY ? `AI coach: on (${GEMINI_MODEL})` : 'AI coach: off (set GEMINI_API_KEY in .env)');
  console.log(ELEVEN_KEY ? `Voice: on (ElevenLabs voice ${ELEVEN_VOICE})` : 'Voice: off (set ELEVENLABS_API_KEY in .env)');
  console.log(`Mac:    http://localhost:${PORT}`);
  console.log(`Phone control code: ${controlToken} (enter it in the pushup-ios settings to pause/stop from the phone)`);
  const lan = Object.values(os.networkInterfaces()).flat().filter((i) => i.family === 'IPv4' && !i.internal);
  for (const i of lan) console.log(`iPhone: enter ${i.address} in the pushup-ios app (same Wi-Fi), port ${PORT}`);
});

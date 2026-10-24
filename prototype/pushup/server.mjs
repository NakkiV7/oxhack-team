import http from 'node:http';
import os from 'node:os';
import { readFile, writeFile } from 'node:fs/promises';
import { randomBytes, timingSafeEqual } from 'node:crypto';
import { createAsker } from './ask.mjs';
import { parseCsv } from './profile.mjs';
import { createProfileService } from './profile-service.mjs';
import { parseSync } from './sync.mjs';

const PORT = Number(process.env.PORT ?? 3001);

const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.mjs': 'text/javascript',
  '.js': 'text/javascript',
  '.wasm': 'application/wasm',
  '.task': 'application/octet-stream',
};

// URL prefix -> directory. Everything is served locally so only the first model download needs network.
const MOUNTS = {
  '/vendor/': new URL('./node_modules/@mediapipe/tasks-vision/', import.meta.url),
  '/models/': new URL('./models/', import.meta.url),
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
const ask = createAsker({ callGemini, secrets: [GEMINI_KEY] });

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
    const prompt = `You are a friendly, upbeat push-up coach speaking to someone mid-workout.
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
      return { rows: parseCsv(csv), where: 'mock CSV file' };
    }
    const { readReps } = await tigerLib();
    const rows = await readReps(tigerPool, { userId: process.env.PUSHUP_USER_ID || 'local', sources: (process.env.PUSHUP_SOURCES || 'mock,real').split(',') });
    return { rows, where: 'Tiger Data' };
  },
  save: (p) => writeFile(PROFILE_FILE, JSON.stringify(p, null, 2) + '\n'),
  load: async () => {
    const p = JSON.parse(await readFile(PROFILE_FILE, 'utf8').catch(() => 'null'));
    return p && { trainedAt: p.trainedAt, reps: p.reps, sessions: p.sessions, baselines: p.baselines, holdoutAccuracy: p.holdoutAccuracy, rules: p.rules, where: p.where };
  },
});
const profileError = (res, e) => {
  const json = JSON.stringify({ error: e.message?.slice(0, 200) ?? 'Failed' });
  res.writeHead(502, { 'Content-Type': 'application/json' }).end(json);
};

const isLoopback = (req) => ['127.0.0.1', '::1', '::ffff:127.0.0.1'].includes(req.socket.remoteAddress);

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
      try { parsed = parseSync(JSON.parse(await readBody(req))); } catch (e) { return send(422, { error: e.message.slice(0, 200) }); }
      try {
        const { insertReps } = await tigerLib();
        const saved = await insertReps(tigerPool, parsed.rows, { userId: process.env.PUSHUP_USER_ID || 'local', source: 'real' });
        return send(200, { ok: true, saved, total: parsed.rows.length, session: parsed.session, where: 'Tiger Data' });
      } catch (e) { return send(502, { error: String(e.message).slice(0, 200) }); }
    }

    if (req.method === 'GET' && path === '/control-code') return res.writeHead(200, { 'Content-Type': 'text/plain' }).end(controlToken);

    if (req.method === 'GET' && path === '/coach-events') {
      res.useChunkedEncodingByDefault = false;
      res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache', Connection: 'close' });
      res.write(`event: status\ndata: ${JSON.stringify({ on: !!GEMINI_KEY })}\n\n`);
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
  console.log(`Mac:    http://localhost:${PORT}`);
  console.log(`Phone control code: ${controlToken} (enter it in the pushup-ios settings to pause/stop from the phone)`);
  const lan = Object.values(os.networkInterfaces()).flat().filter((i) => i.family === 'IPv4' && !i.internal);
  for (const i of lan) console.log(`iPhone: enter ${i.address} in the pushup-ios app (same Wi-Fi), port ${PORT}`);
});

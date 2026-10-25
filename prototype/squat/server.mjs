import http from 'node:http';
import os from 'node:os';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { randomBytes, timingSafeEqual, createHash } from 'node:crypto';
import { createAsker } from './ask.mjs';
import { createCoachAI } from './coach-gemini.mjs';
import * as coach from './coach.mjs';
import * as store from './coach-store.mjs';
import { ensureProfile, programmeView, sessionReport, generateWeekly, sha256 } from './coach-service.mjs';

const PORT = Number(process.env.PORT ?? 3002);

const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.mjs': 'text/javascript',
  '.js': 'text/javascript',
  '.wasm': 'application/wasm',
  '.task': 'application/octet-stream',
  '.mp4': 'video/mp4',
  '.json': 'application/json',
  '.pdf': 'application/pdf',
};

// URL prefix -> directory. Everything is served locally so only the first model download needs network.
const MOUNTS = {
  '/vendor/': new URL('./node_modules/@mediapipe/tasks-vision/', import.meta.url),
  '/models/': new URL('./models/', import.meta.url),
  '/assets/': new URL('./assets/', import.meta.url),   // tutorial videos
  '/docs/': new URL('./docs/', import.meta.url),       // the technical paper, linked from the evidence dialog
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

// Live state from the Mac page, fanned out to phones over Server-Sent Events.
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
    // "Name:voiceId" or "Name:calmId+loudId": a second id is used for form cues and push lines (shouting), the first for counts and praise.
    voiceList = process.env.ELEVENLABS_VOICES.split(',').map((e) => e.trim()).filter(Boolean).map((e) => {
      const i = e.lastIndexOf(':'), [id, loud] = e.slice(i + 1).split('+').map((x) => x.trim());
      return { name: e.slice(0, i).trim(), id, ...(loud ? { loud } : {}) };
    });
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


// Tiger Data: every analysed frame and rep goes to the database once a second (see ../shared/tiger-stream.mjs).
// Off without TIGER_DATABASE_URL: the page then shows its Tiger card as off and nothing else changes.
const TIGER_URL = process.env.TIGER_DATABASE_URL || process.env.TIGER_DB_ADDRESS;
let tiger = null, tigerFailedAt = 0; // one shared promise of { lib, pool }: concurrent callers never run the migration twice
function tigerLib() {
  if (tiger) return tiger;
  if (Date.now() - tigerFailedAt < 10000) return Promise.reject(new Error('Tiger unavailable, retrying shortly'));
  tiger = (async () => {
    const lib = await import('../shared/tiger-stream.mjs');
    const pg = (await import('pg')).default, { Pool } = pg;
    pg.types.setTypeParser(1082, (v) => v); // DATE columns stay ISO date strings, never local-time Date objects
    const pool = await lib.createPool({ Pool, url: TIGER_URL });
    await lib.migrate(pool); // idempotent schema + rollups
    // Register the shipped forecast model once, so stored predictions can be traced to their artifact.
    for (const key of ['controlled', 'relative', 'slow']) {
      const [model, results] = await Promise.all([`./hrt/model-${key}.json`, `./hrt/results-${key}.json`].map((f) => readFile(new URL(f, import.meta.url), 'utf8').then(JSON.parse).catch(() => null)));
      if (model) await lib.registerModel(pool, model, results).catch((e) => console.error('Tiger model_run:', e.message));
    }
    return { lib, pool };
  })().catch((e) => { tiger = null; tigerFailedAt = Date.now(); throw e; });
  return tiger;
}
if (TIGER_URL) tigerLib().then(() => console.log('Tiger Data: schema ready')).catch((e) => console.error('Tiger:', e.message));

const ask = createAsker({ callGemini, secrets: [GEMINI_KEY, ELEVEN_KEY] });

// Coaching journey (profile, programme, coach -> retry -> verify, reports, weekly review, research). Loopback only; one
// user per machine unless ?user= names another (the demo account is 'demo'). Everything persists in Tiger.
const COACH_USER = /^[a-z0-9_-]{1,64}$/i.test(process.env.SPOTTR_USER_ID ?? '') ? process.env.SPOTTR_USER_ID : 'nakki';
const coachAI = createCoachAI({ callGemini: GEMINI_KEY ? callGemini : null, model: GEMINI_MODEL });
const userOf = (req) => { const u = new URL(req.url, 'http://x').searchParams.get('user'); return u && /^[a-z0-9_-]{1,64}$/i.test(u) ? u : COACH_USER; };
async function coachRoute(req, res, path) {
  const json = (status, o) => { const body = JSON.stringify(o); res.writeHead(status, { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) }); res.end(body); return true; };
  if (!TIGER_URL) return json(503, { error: 'The coaching journey needs Tiger Data: set TIGER_DATABASE_URL in .env' });
  const { pool } = await tigerLib(), user = userOf(req), q = new URL(req.url, 'http://x').searchParams;
  const body = req.method === 'POST' ? JSON.parse((await readBody(req, path === '/coach/research/pdf' ? 12e6 : 1e6)) || '{}') : {};
  try {
    if (path === '/coach/me' && req.method === 'GET') {
      const profile = await ensureProfile(pool, user), programme = await programmeView(pool, user);
      return json(200, { user, profile, programme, catalogue: coach.CATALOG.map((e) => ({ ...e, capability: coach.capability(e.id), prerequisites: coach.prerequisites(e.id) })), contracts: coach.CONTRACTS });
    }
    if (path === '/coach/profile' && req.method === 'POST') return json(200, await store.upsertProfile(pool, user, { timezone: body.timezone, survey: body.survey, goals: body.goals, preferences: body.preferences }));
    if (path === '/coach/programme' && req.method === 'POST') {
      const profile = await ensureProfile(pool, user);
      const attempts = await store.listAttempts(pool, user, { limit: 20 });
      const history = { coachingAttempts: attempts.length, assessed: [...new Set(attempts.filter((a) => a.outcome?.classification && a.outcome.classification !== 'unable').map((a) => a.exercise))] };
      const gen = await coachAI.generateProgramme(profile, history);
      const saved = await store.saveProgramme(pool, user, { programmeId: crypto.randomUUID(), goal: gen.graph.goal, catalogVersion: coach.CATALOG_VERSION, graph: gen.graph, rationale: gen.rationale, provenance: gen.provenance });
      return json(200, { programme: await programmeView(pool, user), provenance: saved.provenance });
    }
    if (path === '/coach/node' && req.method === 'GET') {
      const programme = await programmeView(pool, user), id = q.get('id');
      const node = programme?.graph?.nodes?.find((n) => n.id === id);
      if (!node) return json(404, { error: 'node not in the active programme' });
      const entry = coach.find(node.exerciseId), contract = coach.contractFor(node.exerciseId);
      const progress = programme.progress.find((p) => p.node_id === id) ?? null;
      const attempts = await store.listAttempts(pool, user, { nodeId: id, programmeId: programme.programme_id, limit: 20 });
      const unlocks = programme.graph.nodes.filter((n) => (n.prerequisites ?? []).includes(id)).map((n) => n.id);
      return json(200, { node, entry, capability: coach.capability(node.exerciseId), contract, progress, attempts, unlocks, programmeId: programme.programme_id });
    }
    if (path === '/coach/practice' && req.method === 'POST') return json(200, { node: await store.logPractice(pool, { programmeId: body.programmeId, nodeId: body.nodeId, userId: user, workoutId: body.workoutId }) });
    if (path === '/coach/cue' && req.method === 'POST') {
      const contract = coach.contractFor(body.exercise);
      if (!contract || !Array.isArray(body.baselineReps)) return json(400, { error: 'exercise without a measured contract, or no baseline' });
      const profile = await ensureProfile(pool, user), programme = await programmeView(pool, user);
      const node = programme?.graph?.nodes?.find((n) => n.id === body.nodeId) ?? null;
      const recent = await store.listAttempts(pool, user, { exercise: body.exercise, limit: 5 });
      const ctx = coachAI.buildContext({ profile, programme, node, contract, recentAttempts: recent, milestones: (programme?.progress ?? []).filter((p) => p.verification !== 'none').map((p) => `${p.node_id}: ${p.verification}`), quality: body.quality ?? {} });
      return json(200, { cue: await coachAI.selectCue(ctx, body.baselineReps, contract, body.requestId) });
    }
    if (path === '/coach/attempt' && req.method === 'POST') {
      const a = body.attempt; if (!a) return json(400, { error: 'attempt missing' });
      const snapshot = { ...a, workoutId: body.workoutId, programmeId: body.programmeId ?? null, nodeId: body.nodeId ?? null };
      if (a.status !== 'result') return json(200, { attempt: await store.saveAttempt(pool, user, snapshot) });
      const contract = coach.contractFor(a.exercise), profile = await ensureProfile(pool, user);
      let progress = null;
      if (snapshot.programmeId && snapshot.nodeId) {
        const prior = (await store.listAttempts(pool, user, { nodeId: snapshot.nodeId, programmeId: snapshot.programmeId, limit: 100 })).filter((x) => x.attempt_id !== a.attemptId).map((x) => ({ attemptId: x.attempt_id, workoutId: x.workout_id, createdAt: x.created_at, outcome: x.outcome }));
        const row = (await store.listNodeProgress(pool, snapshot.programmeId)).find((p) => p.node_id === snapshot.nodeId);
        progress = coach.progressFor(contract, [...prior, { attemptId: a.attemptId, workoutId: body.workoutId, createdAt: new Date().toISOString(), outcome: a.outcome }], row?.practice_count ?? 0, profile.timezone);
      }
      const saved = await store.saveAttemptAndProgress(pool, user, snapshot, progress);
      return json(200, { ...saved, progress });
    }
    if (path === '/coach/explain' && req.method === 'POST') {
      const a = await store.getAttempt(pool, body.attemptId);
      if (!a || a.user_id !== user) return json(404, { error: 'attempt not found' });
      if (a.explanation) return json(200, { explanation: a.explanation, cached: true });
      if (!a.outcome) return json(409, { error: 'no outcome yet' });
      const programme = await programmeView(pool, user), node = programme?.graph?.nodes?.find((n) => n.id === a.node_id) ?? null;
      const ctx = coachAI.buildContext({ profile: await ensureProfile(pool, user), programme, node, contract: coach.contractFor(a.exercise) });
      const explanation = await coachAI.explainResult(ctx, { exercise: a.exercise, cue: a.cue, outcome: a.outcome });
      await store.saveAttempt(pool, user, { attemptId: a.attempt_id, workoutId: a.workout_id, programmeId: a.programme_id, nodeId: a.node_id, exercise: a.exercise, variation: a.variation, contractVersion: a.contract_version, status: a.status, target: a.target, baselineReps: a.baseline_reps, retryReps: a.retry_reps, cue: a.cue, outcome: a.outcome, explanation, interventions: a.interventions });
      return json(200, { explanation, cached: false });
    }
    if (path === '/coach/workouts' && req.method === 'GET') { // recent sets for the reports list (this machine's camera and replay workouts)
      const rows = (await pool.query(`SELECT w.workout_id, w.exercise, w.variation, w.source, w.note, w.started_at, w.ended_at, count(*) FILTER (WHERE r.counted)::int AS counted,
        (SELECT count(*)::int FROM spottr_cv.coaching_attempt a WHERE a.workout_id = w.workout_id) AS attempts, (SELECT count(*)::int FROM spottr_cv.prediction p WHERE p.workout_id = w.workout_id) AS forecasts
        FROM spottr_cv.workout w LEFT JOIN spottr_cv.rep r USING (workout_id) WHERE w.exercise = 'squat' GROUP BY w.workout_id ORDER BY w.started_at DESC LIMIT 25`)).rows;
      return json(200, rows);
    }
    if (path === '/coach/report' && req.method === 'GET') { const r = await sessionReport({ pool, ai: coachAI, user, workoutId: q.get('workout'), narrate: q.get('narrate') === '1' }); return r ? json(200, r) : json(404, { error: 'workout not found' }); }
    if (path === '/coach/weekly' && req.method === 'POST') return json(200, await generateWeekly({ pool, ai: coachAI, user, periodStart: body.periodStart ?? null }));
    if (path === '/coach/weekly' && req.method === 'GET') return json(200, q.get('id') ? await store.getWeeklyReport(pool, q.get('id')) : await store.listWeeklyReports(pool, user));
    if (path === '/coach/goals' && req.method === 'POST') {
      const programme = await programmeView(pool, user), goals = (body.goals ?? []).map((g, i) => ({ id: g.id || `g${i + 1}`, kind: g.kind, text: String(g.text ?? '').slice(0, 160), nodeId: g.nodeId || null, target: Number(g.target) }));
      const v = coach.validateGoals(goals, programme?.graph, coach.contractFor(programme?.goal === 'pushup' ? 'pushup' : 'squat'));
      if (!v.ok) return json(422, { error: v.errors.join('; ') });
      const accepted = goals.map((g) => ({ ...g, acceptedAt: new Date().toISOString(), source: body.reportId ?? 'manual' }));
      return json(200, { profile: await store.upsertProfile(pool, user, { goals: accepted }) });
    }
    if (path === '/coach/ask' && req.method === 'POST') {
      const report = body.reportId ? await store.getWeeklyReport(pool, body.reportId) : null;
      const facts = [...(report?.facts?.items ?? []), ...((report?.proposed_goals ?? []).map((g) => ({ id: `goal:${g.id}`, text: `Proposed goal "${g.text}" (${g.kind}${g.nodeId ? `, node ${g.nodeId}` : ''}, target ${g.target}) cites ${g.factIDs?.join(', ')}` })))];
      const a = facts.length ? await coachAI.answer(body.question ?? '', facts, 'Say which recorded facts the goal rests on; a goal is a proposal, not a prescription.') : null;
      return json(200, { answer: a ?? { text: 'I can only answer from a saved report\'s facts, and none matched.', factIds: [], provenance: 'deterministic' } });
    }
    if (path === '/coach/research/pdf' && req.method === 'POST') {
      if (typeof body.base64 !== 'string' || body.base64.length > 11e6) return json(400, { error: 'send { name, mime, base64 } under 8 MB' });
      const buf = Buffer.from(body.base64, 'base64'), sourceId = sha256(buf);
      const cached = await store.getResearch(pool, sourceId);
      if (cached) return json(200, { source: cached, cached: true });
      const found = await coachAI.analyseDocument({ base64: body.base64, mime: body.mime === 'text/plain' ? 'text/plain' : 'application/pdf', name: String(body.name ?? 'document').slice(0, 120) });
      if (!found) return json(502, { error: 'The document could not be analysed' });
      return json(200, { source: await store.saveResearch(pool, { sourceId, owner: user, origin: 'supplied', title: found.title, authors: found.authors, year: found.year, url: null, doi: found.doi, access: found.access, contentHash: sourceId, findings: found.findings, grounding: { generationId: found.generationId, fileName: String(body.name ?? '').slice(0, 120) } }), cached: false });
    }
    if (path === '/coach/research/search' && req.method === 'POST') {
      const out = await coachAI.discover(String(body.question ?? '').slice(0, 300));
      const saved = [];
      for (const s of out.sources.filter((x) => x.grounded)) saved.push(await store.saveResearch(pool, { sourceId: 'web:' + sha256(s.url), owner: 'shared', origin: 'discovered', title: s.title, authors: s.authors, year: s.year, url: s.url, doi: s.doi, access: 'metadata', contentHash: null, findings: { mainFindings: s.finding, relevance: String(body.question ?? '').slice(0, 300), question: '', design: '', population: '', intervention: '', outcomes: '', limitations: 'Only search metadata was read; the full text was not analysed.', evidence: [] }, grounding: { searchEntryPoint: out.searchEntryPoint, grounded: true } }));
      return json(200, { sources: saved, ungrounded: out.sources.filter((x) => !x.grounded).length, searchEntryPoint: out.searchEntryPoint });
    }
    if (path === '/coach/research' && req.method === 'GET') return json(200, q.get('id') ? await store.getResearch(pool, q.get('id')) : await store.listResearch(pool, user));
    return false;
  } catch (e) { console.error('coach:', e.message); return json(500, { error: e.message }); }
}

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
      ? `rep ${r.n}: ${r.good ? 'good form' : 'issue: ' + r.issue} (hip ${r.depth >= 0 ? 'below' : 'above'} knee by ${Math.abs(r.depth)} thigh lengths, lean ${r.lean}°, ${r.secs}s)`
      : `not counted: ${r.issue}`));
    const prompt = `You are a ${s.persona || 'friendly, upbeat'} squat coach speaking to someone mid-workout. Stay in that character; never claim to be a real person.
Exercise: ${s.label}. Reps counted: ${s.count} (${s.good} with good form). Camera view: ${s.view}.
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

const tigerHost = (u) => { try { return new URL(u).host; } catch { return 'configured'; } }; // tests pass a placeholder URL
const isLoopback = (req) => ['127.0.0.1', '::1', '::ffff:127.0.0.1'].includes(req.socket.remoteAddress);

const readBody = (req, limit = 1e6) => new Promise((resolve, reject) => {
  let body = '';
  req.on('data', (c) => { body += c; if (body.length > limit) req.destroy(); });
  req.on('end', () => resolve(body));
  req.on('error', reject);
});

const server = http.createServer(async (req, res) => {
  try {
    const path = new URL(req.url, 'http://x').pathname;

    // The only routes reachable from other devices on the LAN: read-only state.
    if (req.method === 'GET' && path === '/events') {
      res.useChunkedEncodingByDefault = false; // raw body so a phone client needs no chunk parsing
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
        const voice = voices.some((v) => v.id === wanted || v.loud === wanted) || /^[A-Za-z0-9]{10,}$/.test(wanted ?? '') ? wanted : voices[0]?.id ?? ELEVEN_VOICE;
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

    // Tiger Data stream: batches from the page, the live status for its card, and on-demand columnstore conversion.
    if (req.method === 'POST' && path === '/telemetry') {
      const body = await readBody(req);
      if (!TIGER_URL) return res.writeHead(204).end();
      try { const { lib, pool } = await tigerLib(); await lib.ingest(pool, JSON.parse(body)); return res.writeHead(204).end(); }
      catch (e) { console.error('Tiger ingest:', e.message); return res.writeHead(500).end(); }
    }
    if (req.method === 'GET' && path === '/tiger') {
      const json = (o) => res.writeHead(200, { 'Content-Type': 'application/json' }).end(JSON.stringify(o));
      if (!TIGER_URL) return json({ on: false });
      try { const { lib, pool } = await tigerLib(); return json({ on: true, ...(await lib.status(pool, new URL(req.url, 'http://x').searchParams.get('workout'))) }); }
      catch (e) { return json({ on: false, error: e.message }); }
    }
    if (path.startsWith('/coach/') && await coachRoute(req, res, path)) return;

    if (req.method === 'GET' && path === '/hrt/review') { // forecasts and outcomes of one workout, read back from Tiger
      const json = (o) => res.writeHead(200, { 'Content-Type': 'application/json' }).end(JSON.stringify(o));
      if (!TIGER_URL) return json({ persisted: false, rows: [] });
      try { const { lib, pool } = await tigerLib(); return json({ persisted: true, rows: await lib.review(pool, new URL(req.url, 'http://x').searchParams.get('workout')) }); }
      catch (e) { return json({ persisted: false, rows: [], error: e.message }); }
    }
    if (req.method === 'POST' && path === '/tiger/compress') {
      if (!TIGER_URL) return res.writeHead(503).end();
      try { const { lib, pool } = await tigerLib(); return res.writeHead(200, { 'Content-Type': 'application/json' }).end(JSON.stringify(await lib.compress(pool))); }
      catch (e) { console.error('Tiger compress:', e.message); return res.writeHead(500).end(); }
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
    else if (path === '/coach' || path === '/coach.html') file = new URL('./coach.html', import.meta.url);
    else if (/^\/(squat|hrt|hrt-evidence|coach|coach-loop)\.mjs$/.test(path)) file = new URL('.' + path, import.meta.url);
    else if (/^\/hrt\/(model|results)-[a-z]+\.json$/.test(path)) file = new URL('.' + path, import.meta.url); // one artifact pair per target
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
  console.log(TIGER_URL ? `Tiger Data: on (${tigerHost(TIGER_URL)})` : 'Tiger Data: off (set TIGER_DATABASE_URL in .env)');
  console.log(`Mac:    http://localhost:${PORT}`);
  console.log(`Phone control code: ${controlToken}`);
  const lan = Object.values(os.networkInterfaces()).flat().filter((i) => i.family === 'IPv4' && !i.internal);
  for (const i of lan) console.log(`Phone: ${i.address}:${PORT} (same Wi-Fi) for the live state`);
});

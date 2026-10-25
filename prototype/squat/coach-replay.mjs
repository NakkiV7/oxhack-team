// Drives the coach -> retry -> verify loop offline from a recording, through the same modules and server routes the page
// uses: counter -> CoachLoop -> /coach/cue -> (retry) -> /coach/attempt -> /coach/explain. Creates real stored evidence
// (an attempt, node progress, a workout with reps) and prints each transition. Useful for tests and for a replayed demo.
//   node coach-replay.mjs <landmark.json> --node squat --programme <id> [--user nakki] [--server http://localhost:3002] [--note text]
import { readFileSync } from 'node:fs';
import { RepCounter } from './squat.mjs';
import { CoachLoop } from './coach-loop.mjs';
import { contractFor } from './coach.mjs';

const args = process.argv.slice(2), file = args.find((a) => !a.startsWith('--'));
const opt = (k, d) => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : d; };
const server = opt('--server', 'http://localhost:3002'), user = opt('--user', 'nakki'), nodeId = opt('--node', 'squat'), programmeId = opt('--programme', null);
if (!file) { console.error('usage: node coach-replay.mjs <landmark.json> --node squat --programme <id> [--user u]'); process.exit(2); }
const api = async (path, body) => { const r = await fetch(`${server}${path}${path.includes('?') ? '&' : '?'}user=${encodeURIComponent(user)}`, body ? { method: 'POST', body: JSON.stringify(body) } : {}); const j = await r.json(); if (!r.ok) throw new Error(j.error ?? r.statusText); return j; };

const node = await api(`/coach/node?id=${encodeURIComponent(nodeId)}`);
if (node.capability !== 'assessable') { console.log(`${nodeId} is practice-only; nothing to assess`); process.exit(0); }
const contract = contractFor(node.node.exerciseId), clip = JSON.parse(readFileSync(file, 'utf8'));
const workoutId = crypto.randomUUID(), t0 = Date.now() - Math.round((clip.frames.length / clip.fps) * 1000), stamp = (t) => t0 + Math.round(t * 1000);
const tele = (body) => fetch(`${server}/telemetry`, { method: 'POST', body: JSON.stringify({ workoutId, exercise: 'squat', ...body }) });
await tele({ start: { variation: 'standard', source: 'video', client: 'coach-replay', startedAt: new Date(t0).toISOString(), note: opt('--note', `coach replay: ${file.split('/').pop()}`) } });
const loop = new CoachLoop({ contract });
const save = () => api('/coach/attempt', { attempt: loop.snapshot(), workoutId, programmeId: programmeId ?? node.programmeId, nodeId });
const counter = new RepCounter(); let began = false; const reps = [];
for (let i = 0; i < clip.frames.length; i++) {
  const fr = clip.frames[i]; if (!fr) continue;
  const t = i / clip.fps, rep = counter.update(fr.map(([x, y, z, visibility]) => ({ x, y, z, visibility })), t, clip.width / clip.height);
  if (!began && !counter.warn) { began = true; loop.begin(); console.log(`t=${t.toFixed(1)}s setup ok -> baseline`); }
  if (!rep) continue;
  reps.push({ at: stamp(t), n: rep.n, counted: rep.counted, good: rep.good, secs: rep.secs, downSecs: rep.tDown, upSecs: rep.tUp, travel: rep.travel, depth: rep.depth, lean: rep.lean, issue: rep.issue ?? null, faults: rep.faults ?? [] });
  const ev = loop.onRep(rep);
  if (!ev) continue;
  console.log(`t=${t.toFixed(1)}s rep ${rep.n ?? '-'} ${rep.counted ? `lowering ${rep.tDown}s` : 'not counted'} -> ${loop.state}${ev.valid ? ` (${ev.valid} valid)` : ''}`);
  if (ev.event === 'baseline_complete') {
    await save();
    let cue = null;
    try { ({ cue } = await api('/coach/cue', { attemptId: loop.attemptId, requestId: ev.requestId, exercise: contract.exerciseId, baselineReps: ev.baseline, programmeId: programmeId ?? node.programmeId, nodeId, quality: { framing: 'ok', view: counter.view } })); } catch (e) { console.log('cue request failed:', e.message); }
    if (!cue || !loop.cueReady(cue, ev.requestId)) loop.cueFailed();
    console.log(`cue (${loop.cue.provenance}, ${loop.cue.action}): "${loop.cue.text}" | target frozen ${JSON.stringify(loop.target)}`);
    await save();
    loop.startRetry(); console.log('user pressed Start retry');
  } else if (ev.event === 'result') {
    console.log(`result: ${JSON.stringify(ev.outcome)}`);
    await tele({ reps });
    const saved = await save();
    console.log(`saved attempt ${saved.attempt?.status}; node ${saved.node?.node_id}: ${saved.node?.verification}, ${saved.node?.xp} XP, badges ${JSON.stringify(saved.node?.badges)}, availability ${saved.node?.availability}`);
    const { explanation, cached } = await api('/coach/explain', { attemptId: loop.attemptId });
    console.log(`explanation (${explanation.provenance}${cached ? ', cached' : ''}, next ${explanation.nextAction}): ${explanation.text}`);
    break;
  }
}
if (loop.state !== 'result') { console.log(`clip ended in state ${loop.state}: ${loop.validCount('baseline')} baseline, ${loop.validCount('retry')} retry valid reps`); await tele({ reps }); loop.cancel(); await save(); }
await tele({ end: { endedAt: new Date().toISOString() } });
console.log('workout', workoutId, '| attempt', loop.attemptId);

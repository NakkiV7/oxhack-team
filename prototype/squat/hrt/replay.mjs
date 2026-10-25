// Replays a recording through the rep counter and the forecaster exactly as the page would, rep by rep, and posts the
// resulting set to the local squat server (which stores it in Tiger Data as a video-provenance workout). Prefix-only by
// construction: the forecaster sees each rep only after the counter has finished it.
//   node hrt/replay.mjs <landmark.json> [--server http://localhost:3002] [--target relative] [--note name]
import { readFileSync } from 'node:fs';
import { RepCounter } from '../squat.mjs';
import { Forecaster, TARGETS, DEFAULT_TARGET } from '../hrt.mjs';

const args = process.argv.slice(2);
const file = args.find((a) => !a.startsWith('--'));
const opt = (k, d) => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : d; };
const server = opt('--server', 'http://localhost:3002'), key = opt('--target', DEFAULT_TARGET);
if (!file) { console.error('usage: node hrt/replay.mjs <landmark.json> [--server url] [--target key] [--note name]'); process.exit(2); }

const clip = JSON.parse(readFileSync(file, 'utf8'));
const artifact = await fetch(`${server}/hrt/model-${key}.json`).then((r) => (r.ok ? r.json() : null)).catch(() => null);
const counter = new RepCounter(), fc = new Forecaster({ artifact, target: TARGETS[key], mode: 'shadow' });
const workoutId = crypto.randomUUID(), t0 = Date.now() - Math.round((clip.frames.length / clip.fps) * 1000);
const post = (body) => fetch(`${server}/telemetry`, { method: 'POST', body: JSON.stringify({ workoutId, exercise: 'squat', ...body }) }).then((r) => r.status);
const stamp = (t) => t0 + Math.round(t * 1000);
await post({ start: { variation: 'standard', source: 'video', client: 'hrt-replay', startedAt: new Date(t0).toISOString(), note: opt('--note', file.split('/').pop()) } });

const reps = [], forecasts = [], outcomes = [];
clip.frames.forEach((fr, i) => {
  if (!fr) return;
  const t = i / clip.fps;
  const rep = counter.update(fr.map(([x, y, z, visibility]) => ({ x, y, z, visibility })), t, clip.width / clip.height);
  if (!rep) return;
  reps.push({ at: stamp(t), n: rep.n, counted: rep.counted, good: rep.good, secs: rep.secs, downSecs: rep.tDown, upSecs: rep.tUp, travel: rep.travel, depth: rep.depth, lean: rep.lean, issue: rep.issue ?? null, faults: rep.faults ?? [] });
  const { forecast, outcomes: done } = fc.onRep(rep, t);
  if (forecast) forecasts.push({ ...forecast, provenance: 'video', cutoffAt: new Date(stamp(t)).toISOString(), emittedAt: new Date(stamp(t)).toISOString() });
  for (const o of done) outcomes.push({ ...o, observedAt: new Date(stamp(t)).toISOString() });
});
for (const o of fc.end()) outcomes.push(o);
console.log('reps', reps.length, 'forecasts', forecasts.length, 'outcomes', outcomes.length, 'model', artifact?.modelRun ?? 'none');
for (let i = 0; i < reps.length; i += 100) console.log('reps batch', await post({ reps: reps.slice(i, i + 100) }));
console.log('forecasts', await post({ forecasts }));
console.log('outcomes', await post({ outcomes }));
console.log('end', await post({ end: { endedAt: new Date().toISOString() } }));
console.log('workout', workoutId);

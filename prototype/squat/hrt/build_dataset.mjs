// Builds the rep-level dataset for the forecasting experiment from MediaPipe landmark dumps (one JSON per recording:
// { fps, width, height, frames: [[x, y, z, visibility] x 33] | null }). Every recording is run through the same
// RepCounter the page uses, so a rep here is exactly a rep on screen. Nothing is labelled by hand at this stage.
//
//   node hrt/build_dataset.mjs <landmark-dir> [--manifest hrt/data/recordings.json] [--out hrt/data/reps.csv]
//
// The manifest lists each recording's provenance (source, licence, person, split). Recordings missing from it are
// included with split "unassigned" so the audit shows them, and the trainer refuses to use them.
import { readFileSync, readdirSync, writeFileSync, mkdirSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { RepCounter } from '../squat.mjs';

const args = process.argv.slice(2);
const dir = args.find((a) => !a.startsWith('--'));
const opt = (k, d) => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : d; };
const manifestPath = opt('--manifest', new URL('./data/recordings.json', import.meta.url));
const out = opt('--out', new URL('./data/reps.csv', import.meta.url));
if (!dir) { console.error('usage: node hrt/build_dataset.mjs <landmark-dir> [--manifest file] [--out file]'); process.exit(2); }

const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
export const COLUMNS = ['recording', 'split', 'person', 'provenance', 'variation', 'rep_n', 'counted', 'good', 't_end', 'down', 'up', 'secs', 'travel', 'depth', 'lean', 'view', 'faults'];

export function repsFromDump(clip, variation = 'standard') {
  const c = new RepCounter(variation);
  const rows = [];
  clip.frames.forEach((fr, i) => {
    if (!fr) return;
    const t = i / clip.fps;
    const rep = c.update(fr.map(([x, y, z, visibility]) => ({ x, y, z, visibility })), t, clip.width / clip.height);
    if (rep) rows.push({ rep_n: rep.n, counted: rep.counted, good: rep.good, t_end: Math.round(t * 100) / 100, down: rep.tDown, up: rep.tUp, secs: rep.secs,
      travel: rep.travel, depth: rep.depth, lean: rep.lean, view: c.view, faults: (rep.faults ?? []).join('|') });
  });
  return rows;
}

const files = readdirSync(dir).filter((f) => f.endsWith('.json')).sort();
const rows = [], hashes = {};
for (const f of files) {
  const name = f.replace(/\.json$/, '');
  const raw = readFileSync(`${dir}/${f}`);
  hashes[name] = createHash('sha256').update(raw).digest('hex');
  const m = manifest.recordings[name] ?? { split: 'unassigned', person: '?', source: '?', provenance: 'unknown' };
  // A recording of several people in turn is split into one group per person by the time windows in the manifest.
  const seg = (t) => { if (!m.segments) return [name, m.person]; const hit = Object.entries(m.segments).find(([, [a, b]]) => t >= a && t < b); return hit ? [`${name}/${hit[0]}`, hit[0]] : [null, null]; };
  for (const r of repsFromDump(JSON.parse(raw), m.variation ?? 'standard')) {
    const [recording, person] = seg(r.t_end);
    if (recording) rows.push({ recording, split: m.split, person, provenance: m.provenance, variation: m.variation ?? 'standard', ...r });
  }
}
const csv = [COLUMNS.join(','), ...rows.map((r) => COLUMNS.map((k) => r[k] ?? '').join(','))].join('\n') + '\n';
mkdirSync(new URL('./data/', import.meta.url), { recursive: true });
writeFileSync(out, csv);
writeFileSync(new URL('./data/landmark-hashes.json', import.meta.url), JSON.stringify(hashes, null, 2) + '\n');

// Audit printout: per recording, then the lowering-duration distribution of counted reps.
const by = {};
for (const r of rows) (by[r.recording] ??= []).push(r);
console.log('recording'.padEnd(36), 'split'.padEnd(11), 'reps', 'cnt', 'down s (counted reps)');
for (const [name, rs] of Object.entries(by)) {
  const d = rs.filter((r) => r.counted).map((r) => r.down);
  console.log(name.padEnd(36), String(rs[0].split).padEnd(11), String(rs.length).padStart(4), String(d.length).padStart(3), d.join(' '));
}
const all = rows.filter((r) => r.counted).map((r) => r.down).sort((a, b) => a - b);
const q = (p) => all[Math.min(all.length - 1, Math.floor(p * all.length))];
console.log(`\ncounted reps: ${all.length} of ${rows.length} attempts in ${files.length} recordings`);
console.log(`lowering duration: min ${all[0]} p10 ${q(0.1)} p25 ${q(0.25)} median ${q(0.5)} p75 ${q(0.75)} p90 ${q(0.9)} max ${all.at(-1)}`);
console.log(`wrote ${out}`);

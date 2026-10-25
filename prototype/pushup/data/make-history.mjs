// Generates data/history.csv: mock past workouts for developing and testing the profile training.
// Seeded, so re-running gives the same file.
// Usage: node data/make-history.mjs [--sessions 10] [--reps 30] [--start 2026-10-01] [--step 2] [--out history.csv]
// The demo file (3000 reps) is: --sessions 100 --start 2026-07-15 --step 1 --out history-demo.csv
import { writeFileSync } from 'node:fs';

const arg = (name, fallback) => {
  const i = process.argv.indexOf(`--${name}`);
  return i > 0 ? process.argv[i + 1] : fallback;
};
const SESSIONS = Number(arg('sessions', 10));
const REPS = Number(arg('reps', 30)); // one continuous set per session
const START = Date.parse(`${arg('start', '2026-10-01')}T00:00:00Z`);
const STEP_DAYS = Number(arg('step', 2));
const OUT = arg('out', 'history.csv');

// mulberry32: tiny seeded RNG
let s = 20261024;
const rand = () => {
  s = (s + 0x6d2b79f5) | 0;
  let t = Math.imul(s ^ (s >>> 15), 1 | s);
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
};
const gauss = (mean, sd) => mean + sd * Math.sqrt(-2 * Math.log(1 - rand())) * Math.cos(2 * Math.PI * rand());
const between = (a, b) => a + (b - a) * rand();
const r1 = (x) => Math.round(x * 10) / 10;

// Each rep gets a label the current fixed thresholds do not fully give:
//   good      clean rep, like the real log (elbow ~64, body line ~171, ~3.5 s)
//   shallow   not deep enough (elbow 85-110); above 95 the app does not count it
//   sagging   hips drop (body line 150-163)
//   fatigued  late in the set: slower, a little shallower, body line drifting, still "counted"
function makeRep(rep) {
  const lateness = Math.max(0, (rep - 12) / (REPS - 12)); // 0 until rep 12, then up to 1
  const roll = rand();
  if (roll < 0.06) return { elbow: between(85, 110), line: gauss(171, 0.8), seconds: gauss(3.6, 0.8), label: 'shallow' };
  if (roll < 0.12) return { elbow: gauss(66, 3), line: between(150, 163), seconds: gauss(3.8, 0.8), label: 'sagging' };
  if (rand() < 0.15 + 0.7 * lateness) {
    return { elbow: gauss(73, 3), line: gauss(167, 1.2), seconds: gauss(6.5 + 2 * lateness, 1.2), label: 'fatigued' };
  }
  return { elbow: gauss(64.5, 1.8), line: gauss(171.4, 0.6), seconds: Math.max(0.9, gauss(3.5, 0.9)), label: 'good' };
}

const lines = ['session,date,rep,elbow,body_line,seconds,counted,label'];
for (let n = 1; n <= SESSIONS; n++) {
  const date = new Date(START + (n - 1) * STEP_DAYS * 86400000).toISOString().slice(0, 10);
  for (let rep = 1; rep <= REPS; rep++) {
    const m = makeRep(rep);
    lines.push([n, date, rep, r1(m.elbow), r1(m.line), r1(m.seconds), m.elbow <= 95 ? 1 : 0, m.label].join(','));
  }
}
writeFileSync(new URL(OUT, new URL('./', import.meta.url)), lines.join('\n') + '\n');
console.log(`wrote ${SESSIONS * REPS} reps to data/${OUT}`);

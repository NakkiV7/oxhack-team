// Builds data/profile.json from past reps.
// Usage: node train.mjs [history.csv] [profile.json]      reads the CSV
//        node train.mjs --tiger [profile.json]            reads this user's reps from Tiger Data (set PUSHUP_SOURCES=real to skip mock rows)
import { readFileSync, writeFileSync } from 'node:fs';
import { parseCsv, buildProfile, mockShare } from './profile.mjs';

const args = process.argv.slice(2);
const fromTiger = args[0] === '--tiger';
const [src = new URL('./data/history.csv', import.meta.url), out = new URL('./data/profile.json', import.meta.url)] = fromTiger ? [undefined, args[1]] : args;

let rows;
if (fromTiger) {
  const { createPool, readReps } = await import('./tiger.mjs');
  const pool = await createPool();
  try {
    rows = await readReps(pool, { userId: process.env.PUSHUP_USER_ID || 'local', sources: (process.env.PUSHUP_SOURCES || 'mock,real').split(',') });
  } finally { await pool.end(); }
  console.log(`Loaded ${rows.length} reps from Tiger Data...`);
} else {
  rows = parseCsv(readFileSync(src, 'utf8'));
  console.log(`Loaded ${rows.length} reps...`);
}
if (!rows.length) { console.error('No reps to train on.'); process.exit(1); }
const profile = { ...buildProfile(rows), where: fromTiger ? 'Tiger Data' : 'mock CSV file', mockShare: mockShare(rows), trainedAt: new Date().toISOString() };
writeFileSync(out, JSON.stringify(profile, null, 2) + '\n');
const b = profile.baselines;
console.log(`Profile ready: ${profile.reps} reps over ${profile.sessions} sessions`);
console.log(`  usual elbow ${b.elbow.typical}° (±${b.elbow.spread}), body line ${b.body_line.typical}° (±${b.body_line.spread}), ${b.seconds.typical} s per rep`);
console.log(`  tree accuracy on unseen sessions: ${profile.holdoutAccuracy === null ? 'n/a' : Math.round(profile.holdoutAccuracy * 100) + '%'}`);
for (const rule of profile.rules) console.log(`  ${rule}`);

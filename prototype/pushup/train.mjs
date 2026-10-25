// Usage: node train.mjs [history.csv] [profile.json], or --tiger [profile.json].
import { readFileSync, writeFileSync, renameSync, rmSync } from 'node:fs';
import { dirname, basename, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomUUID } from 'node:crypto';
import { parseCsv } from './profile.mjs';
import { createProfileService } from './profile-service.mjs';

const args = process.argv.slice(2);
const fromTiger = args[0] === '--tiger';
const defaultOutput = new URL('./data/profile.json', import.meta.url);
const src = args[0] ?? new URL('./data/history.csv', import.meta.url);
const output = args[1] ?? defaultOutput;
const outputPath = output instanceof URL ? fileURLToPath(output) : resolve(output);
const userId = process.env.PUSHUP_USER_ID || 'local';
const selectedSources = fromTiger ? (process.env.PUSHUP_SOURCES || 'mock,real').split(',') : ['mock'];
const where = fromTiger ? 'Tiger Data' : 'mock CSV file';

async function loadRows() {
  if (!fromTiger) return { rows: parseCsv(readFileSync(src, 'utf8')), where, userId, selectedSources };
  const { createPool, readReps } = await import('./tiger.mjs');
  const pool = await createPool();
  try {
    return { rows: await readReps(pool, { userId, sources: selectedSources }), where, userId, selectedSources };
  } finally { await pool.end(); }
}

function save(profile) {
  const temporary = join(dirname(outputPath), `.${basename(outputPath)}.${randomUUID()}.tmp`);
  try {
    writeFileSync(temporary, JSON.stringify(profile, null, 2) + '\n', { flag: 'wx', mode: 0o600 });
    renameSync(temporary, outputPath);
  } finally { rmSync(temporary, { force: true }); }
}

try {
  const result = await createProfileService({ loadRows, save }).train();
  if (!result.ok) throw new Error(`Not enough usable profile history: ${result.missing.join(', ')}`);
  const profile = result.profile;
  const b = profile.baselines;
  console.log(`Profile ready: ${profile.reps} usable reps over ${profile.sessions} sessions (${result.missingDuration} missing-duration rows excluded)`);
  console.log(`  usual elbow ${b.elbow.typical}° (±${b.elbow.spread}), body line ${b.body_line.typical}° (±${b.body_line.spread}), ${b.seconds.typical} s per rep`);
  console.log(`  tree accuracy on unseen sessions: ${profile.holdoutAccuracy === null ? 'n/a' : Math.round(profile.holdoutAccuracy * 100) + '%'}`);
  for (const rule of profile.rules) console.log(`  ${rule}`);
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}

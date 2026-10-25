import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const csv = readFileSync(new URL('../data/history.csv', import.meta.url), 'utf8');
const [header, ...lines] = csv.trim().split('\n');
const cli = fileURLToPath(new URL('../train.mjs', import.meta.url));

function runCsv(text, check) {
  const directory = mkdtempSync(join(tmpdir(), 'spottr-profile-cli-'));
  const input = join(directory, 'history.csv');
  const output = join(directory, 'profile.json');
  writeFileSync(input, text);
  writeFileSync(output, 'previous profile');
  try {
    const result = spawnSync(process.execPath, [cli, input, output], { encoding: 'utf8', env: {}, timeout: 10000 });
    check(result, readFileSync(output, 'utf8'));
  } finally { rmSync(directory, { recursive: true, force: true }); }
}

test('CLI refuses insufficient, all-bad and malformed rows without replacing the existing profile', () => {
  const allBad = [header, ...lines.map((line) => line.replace(/,[^,]+$/, ',shallow'))].join('\n');
  const malformed = csv.replace(lines[0], lines[0].split(',').map((cell, i) => i === 3 ? 'Infinity' : cell).join(','));
  for (const text of [[header, ...lines.slice(0, 30)].join('\n'), allBad, malformed]) {
    runCsv(text, (result, saved) => {
      assert.notEqual(result.status, 0);
      assert.equal(saved, 'previous profile');
    });
  }
});

test('CLI saves a ready profile with the same context-bound provenance as the service', () => {
  runCsv(csv, (result, saved) => {
    assert.equal(result.status, 0, result.stderr);
    const profile = JSON.parse(saved);
    assert.equal(profile.provenance.userId, 'local');
    assert.deepEqual(profile.provenance.selectedSources, ['mock']);
    assert.match(profile.provenance.datasetSha256, /^[a-f0-9]{64}$/);
    assert.equal(profile.mockShare, 1);
    assert.ok(profile.baselines.goodReps >= 30);
  });
});

test('CLI preserves the existing profile when a good label contradicts an uncounted rep', () => {
  const columns = header.split(',');
  const invalidLine = lines[0].split(',').map((cell, index) => columns[index] === 'counted' ? '0' : columns[index] === 'label' ? 'good' : cell).join(',');
  runCsv(csv.replace(lines[0], invalidLine), (result, saved) => {
    assert.notEqual(result.status, 0);
    assert.equal(saved, 'previous profile');
  });
});

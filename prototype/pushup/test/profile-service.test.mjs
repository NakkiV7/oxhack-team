import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { parseCsv, readiness } from '../profile.mjs';
import { createProfileService } from '../profile-service.mjs';

const rows = parseCsv(readFileSync(new URL('../data/history.csv', import.meta.url), 'utf8'));
const demo = parseCsv(readFileSync(new URL('../data/history-demo.csv', import.meta.url), 'utf8'));

test('300 mock reps is ready; 40 reps asks for more of everything', () => {
  assert.equal(readiness(rows).ready, true);
  const few = readiness(rows.slice(0, 40));
  assert.equal(few.ready, false);
  assert.equal(few.missing.length, 3);
  assert.match(few.missing[0], /260 more reps/);
});

test('bad reps are everything that is not labeled good', () => {
  assert.equal(readiness(demo).bad, demo.filter((r) => r.label !== 'good').length);
});

test('train refuses when there is not enough data and saves nothing', async () => {
  let saved = null;
  const svc = createProfileService({ loadRows: async () => ({ rows: rows.slice(0, 40), where: 'csv' }), save: async (p) => { saved = p; } });
  const out = await svc.train();
  assert.equal(out.ok, false);
  assert.equal(saved, null);
});

test('train builds, saves and reports the stages; demo data is marked as mock', async () => {
  let saved = null;
  const svc = createProfileService({ loadRows: async () => ({ rows: demo, where: 'tiger' }), save: async (p) => { saved = p; } });
  const out = await svc.train();
  assert.equal(out.ok, true);
  assert.equal(out.reps, 3000);
  assert.equal(out.mockShare, 1);
  assert.equal(out.stages.length, 5);
  assert.equal(saved.where, 'tiger');
  assert.ok(saved.baselines.elbow.typical > 60 && saved.baselines.elbow.typical < 70);
});

test('rows with source=real lower the mock share', async () => {
  const mixed = [...demo.map((r) => ({ ...r, source: 'mock' })), ...demo.slice(0, 1000).map((r) => ({ ...r, source: 'real' }))];
  const out = await createProfileService({ loadRows: async () => ({ rows: mixed, where: 'tiger' }) }).status();
  assert.ok(Math.abs(out.mockShare - 0.75) < 1e-9);
});

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
  assert.equal(few.missing.length, 4);
  assert.match(few.missing[0], /260 more reps/);
});

test('bad reps are everything that is not labeled good', () => {
  assert.equal(readiness(demo).bad, demo.filter((r) => r.label !== 'good').length);
});

test('train refuses when there is not enough data and saves nothing', async () => {
  let saved = null;
  const svc = createProfileService({ loadRows: async () => ({ rows: rows.slice(0, 40), where: 'csv', userId: 'local', selectedSources: ['mock'] }), save: async (p) => { saved = p; } });
  const out = await svc.train();
  assert.equal(out.ok, false);
  assert.equal(saved, null);
});

test('train builds, saves and reports the stages; demo data is marked as mock', async () => {
  let saved = null;
  const svc = createProfileService({ loadRows: async () => ({ rows: demo, where: 'tiger', userId: 'local', selectedSources: ['mock'] }), save: async (p) => { saved = p; } });
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
  const out = await createProfileService({ loadRows: async () => ({ rows: mixed, where: 'tiger', userId: 'local', selectedSources: ['mock', 'real'] }) }).status();
  assert.ok(Math.abs(out.mockShare - 0.75) < 1e-9);
});

test('training needs 30 usable good baseline reps and never replaces an old artifact on refusal', async () => {
  const allBad = rows.map((row) => ({ ...row, label: 'shallow' }));
  let saved = { retained: true };
  const svc = createProfileService({
    loadRows: async () => ({ rows: allBad, where: 'csv', userId: 'local', selectedSources: ['mock'] }),
    save: async (profile) => { saved = profile; },
  });
  const result = await svc.train();
  assert.equal(result.ok, false);
  assert.equal(result.good, 0);
  assert.ok(result.missing.includes('30 more good-form reps'));
  assert.deepEqual(saved, { retained: true });
});

test('malformed training rows reject before replacing a saved profile', async () => {
  for (const change of [
    { elbow: Infinity }, { elbow: NaN }, { elbow: -1 }, { body_line: 181 },
    { seconds: -1 }, { seconds: Infinity }, { rep: 1.5 }, { session: 0 },
    { session: '1' }, { counted: 2 }, { label: 'unknown' }, { source: 'unknown' },
    { date: '2026-99-01' }, { measured_at: 'invalid' },
  ]) {
    let saved = { retained: true };
    const svc = createProfileService({
      loadRows: async () => ({ rows: [{ ...rows[0], ...change }, ...rows.slice(1)], where: 'csv', userId: 'local', selectedSources: ['mock'] }),
      save: async (profile) => { saved = profile; },
    });
    await assert.rejects(svc.train(), /Invalid profile row/);
    assert.deepEqual(saved, { retained: true });
  }
});

test('missing durations are disclosed and do not count toward training or the good baseline', async () => {
  const incomplete = rows.map((row) => ({ ...row, seconds: null }));
  const result = await createProfileService({
    loadRows: async () => ({ rows: incomplete, where: 'tiger', userId: 'local', selectedSources: ['mock'] }),
    save: async () => assert.fail('must not save missing-duration training'),
  }).train();
  assert.equal(result.ok, false);
  assert.equal(result.reps, 0);
  assert.equal(result.good, 0);
  assert.equal(result.totalReps, 300);
  assert.equal(result.missingDuration, 300);
});

test('saved profiles bind owner, source selection and dataset while retaining training mock share', async () => {
  let current = { rows, where: 'csv', userId: 'alice', selectedSources: ['real', 'mock'] };
  let saved;
  const svc = createProfileService({ loadRows: async () => current, save: async (p) => { saved = p; }, load: async () => saved });
  await svc.train();
  assert.equal(saved.provenance.userId, 'alice');
  assert.deepEqual(saved.provenance.selectedSources, ['mock', 'real']);
  assert.match(saved.provenance.datasetSha256, /^[a-f0-9]{64}$/);
  const originalHash = saved.provenance.datasetSha256;
  assert.equal((await svc.status()).datasetChanged, false);
  current = { ...current, rows: rows.map((row) => ({ ...row, source: 'real' })) };
  const changed = await svc.status();
  assert.equal(changed.profile.mockShare, 1);
  assert.equal(changed.historyMockShare, 0);
  assert.equal(changed.datasetChanged, true);
  assert.equal(changed.profile.provenance.datasetSha256, originalHash);
  current = { ...current, userId: 'bob' };
  assert.equal((await svc.status()).profile, null);
  assert.equal((await svc.status()).profileReason, 'owner-mismatch');
  current = { ...current, userId: 'alice', selectedSources: ['real'] };
  assert.equal((await svc.status()).profile, null);
  assert.equal((await svc.status()).profileReason, 'sources-mismatch');
});

test('legacy and malformed saved profiles cannot be applied; invalid source context never saves', async () => {
  const context = { rows, where: 'csv', userId: 'local', selectedSources: ['mock'] };
  let saved = { baselines: { elbow: { typical: 60, spread: 3 } } };
  let saves = 0;
  const svc = createProfileService({ loadRows: async () => context, load: async () => saved, save: async (p) => { saved = p; saves++; } });
  assert.equal((await svc.status()).profile, null);
  await svc.train();
  saved = { ...saved, mockShare: NaN };
  assert.equal((await svc.status()).profile, null);
  for (const invalid of [
    { ...context, selectedSources: [] }, { ...context, userId: '' },
    { ...context, selectedSources: ['other'] },
    { ...context, rows: rows.map((r) => ({ ...r, source: 'real' })) },
  ]) {
    await assert.rejects(createProfileService({ loadRows: async () => invalid, save: async () => { saves++; } }).train(), /Invalid profile/);
  }
  assert.equal(saves, 1);
});

test('UUID workouts remain separate for readiness, holdout and dataset provenance', async () => {
  const uuid = (group) => `00000000-0000-4000-8000-${String(group).padStart(12, '0')}`;
  const observed = rows.map((row, i) => ({
    ...row, source: 'real', session: 1792843200, rep: i % 60 + 1, workout_id: uuid(Math.floor(i / 60) + 1),
  }));
  let current = { rows: observed, where: 'tiger', userId: 'local', selectedSources: ['real'] };
  let saved;
  const svc = createProfileService({ loadRows: async () => current, load: async () => saved, save: async (p) => { saved = p; } });
  const result = await svc.train();
  assert.equal(result.ok, true);
  assert.equal(result.sessions, 5);
  assert.equal(saved.sessions, 5);
  assert.notEqual(saved.holdoutAccuracy, null, 'separate workouts must support a held-out evaluation');
  current = { ...current, rows: observed.map((row, i) => ({ ...row, workout_id: uuid(Math.floor(i / 60) + 11) })) };
  assert.equal((await svc.status()).datasetChanged, true);
  assert.equal(readiness(rows.map((row) => ({ ...row, workout_id: null }))).ready, true);
  current = { ...current, rows: [{ ...observed[0], workout_id: 'not-a-uuid' }, ...observed.slice(1)] };
  await assert.rejects(svc.train(), /Invalid profile row/);
});

test('uncounted reps labeled good cannot contribute to a baseline or replace a saved profile', async () => {
  for (const counted of [false, 0]) {
    const contradictory = rows.map((row, i) => i === 0 ? { ...row, counted, label: 'good' } : row);
    let saved = { retained: true };
    const svc = createProfileService({
      loadRows: async () => ({ rows: contradictory, where: 'csv', userId: 'local', selectedSources: ['mock'] }),
      save: async (profile) => { saved = profile; },
    });
    await assert.rejects(svc.train(), /Invalid profile row/);
    assert.deepEqual(saved, { retained: true });
  }
});

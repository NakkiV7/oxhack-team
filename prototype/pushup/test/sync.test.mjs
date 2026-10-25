import test from 'node:test';
import assert from 'node:assert/strict';
import { parseSync, labelOf, MAX_SYNC_REPS } from '../sync.mjs';

const T0 = Date.UTC(2026, 9, 24, 12);
const owner = { userId: 'synthetic-owner', now: T0 + 30000 };
const rep = (o = {}) => ({ observedAt: T0 + 3500, counted: true, good: true, minElbow: 64, minLine: 171, secs: 3.5, issue: null, ...o });
const workout = (o = {}) => ({ workoutId: '5bc9a693-1b37-4401-b382-5a5c9b185b0e', userId: owner.userId, cloudConsent: true, source: 'real', variation: 'standard', startedAt: T0, endedAt: T0 + 30000, timeMs: 20000, reps: [rep(), rep({ observedAt: T0 + 23000, secs: null })], ...o });

test('labels follow the app cues', () => {
  assert.equal(labelOf(rep()), 'good');
  assert.equal(labelOf(rep({ counted: false, good: false, issue: 'Not low enough: bend your elbows more' })), 'shallow');
  assert.equal(labelOf(rep({ good: false, issue: 'Hips sagging: squeeze your core and glutes' })), 'sagging');
  assert.equal(labelOf(rep({ good: false, issue: 'Hips too high: lower them into a straight line' })), 'piking');
  assert.equal(labelOf(rep({ good: false, issue: 'Keep your body in one straight line' })), 'other');
});

test('real sync preserves actual irregular observation times and owner-bound stable identity', () => {
  const out = parseSync(workout(), owner);
  assert.equal(out.workoutId, workout().workoutId);
  assert.equal(out.userId, owner.userId);
  assert.equal(out.session, Math.floor(T0 / 1000));
  assert.deepEqual(out.rows.map(r => r.measured_at), ['2026-10-24T12:00:03.500Z', '2026-10-24T12:00:23.000Z']);
  assert.deepEqual(out.rows.map(r => r.rep), [1, 2]);
  assert.equal(out.rows[1].seconds, null);
  assert.match(out.contentHash, /^[a-f0-9]{64}$/);
});

test('reordered JSON properties replay identically while changed timing or cue evidence changes the content hash', () => {
  const body = workout();
  const reordered = Object.fromEntries(Object.entries(body).reverse());
  reordered.reps = body.reps.map(r => Object.fromEntries(Object.entries(r).reverse()));
  assert.deepEqual(parseSync(body, owner), parseSync(reordered, owner));
  const hash = parseSync(body, owner).contentHash;
  for (const changed of [workout({ timeMs: 19000 }), workout({ endedAt: T0 + 29000 }), workout({ reps: [rep({ issue: 'Synthetic changed cue' }), body.reps[1]] })]) {
    assert.notEqual(parseSync(changed, owner).contentHash, hash);
  }
});

test('owner, consent, source, variation, UUID, strict booleans and unknown claims are rejected before storage', () => {
  for (const body of [workout({ userId: 'another-owner' }), workout({ cloudConsent: false }), workout({ cloudConsent: undefined }), workout({ source: 'mock' }), workout({ source: 'video' }), workout({ variation: 'knee' }), workout({ workoutId: '' }), workout({ extra: true }), workout({ reps: [rep({ counted: 'false' })] }), workout({ reps: [rep({ good: 'false' })] }), workout({ reps: [rep({ counted: false, good: true })] }), workout({ reps: [rep({ extra: true })] })]) {
    assert.throws(() => parseSync(body, owner));
  }
  assert.throws(() => parseSync(workout()));
});

test('missing, fabricated, unordered and out-of-window times and unbounded quantities fail closed', () => {
  for (const body of [null, workout({ reps: [] }), workout({ reps: Array(MAX_SYNC_REPS + 1).fill(rep()) }), workout({ startedAt: 5 }), workout({ endedAt: T0 - 1 }), workout({ endedAt: owner.now + 2001 }), workout({ timeMs: 30001 }), workout({ timeMs: Infinity }), workout({ reps: [rep({ observedAt: undefined })] }), workout({ reps: [rep({ observedAt: T0 - 1 })] }), workout({ reps: [rep({ observedAt: T0 + 30001 })] }), workout({ reps: [rep(), rep()] }), workout({ reps: [rep({ minElbow: 999 })] }), workout({ reps: [rep({ minLine: NaN })] }), workout({ reps: [rep({ secs: 'x' })] }), workout({ reps: [rep({ issue: 'x'.repeat(201) })] })]) {
    assert.throws(() => parseSync(body, owner));
  }
});

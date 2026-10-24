import test from 'node:test';
import assert from 'node:assert/strict';
import { parseSync, labelOf, MAX_SYNC_REPS } from '../sync.mjs';

const T0 = Date.UTC(2026, 9, 24, 12, 0, 0);
const rep = (o = {}) => ({ counted: true, good: true, minElbow: 64, minLine: 171, secs: 3.5, issue: null, ...o });

test('labels follow the app cues', () => {
  assert.equal(labelOf(rep()), 'good');
  assert.equal(labelOf(rep({ counted: false, good: false, issue: 'Not low enough: bend your elbows more' })), 'shallow');
  assert.equal(labelOf(rep({ good: false, issue: 'Hips sagging: squeeze your core and glutes' })), 'sagging');
  assert.equal(labelOf(rep({ good: false, issue: 'Hips too high: lower them into a straight line' })), 'piking');
  assert.equal(labelOf(rep({ good: false, issue: 'Keep your body in one straight line' })), 'other');
});

test('rows get ordered times, rep numbers and a session id from the start time', () => {
  const { session, rows } = parseSync({ startedAt: T0, timeMs: 30000, reps: [rep(), rep({ secs: null }), rep()] });
  assert.equal(session, Math.floor(T0 / 1000));
  assert.deepEqual(rows.map((r) => r.rep), [1, 2, 3]);
  assert.equal(rows[0].measured_at, new Date(T0).toISOString());
  assert.equal(rows[1].measured_at, new Date(T0 + 10000).toISOString());
  assert.equal(rows[1].seconds, null);
  assert.equal(rows[0].elbow, 64);
});

test('the same workout always maps to the same rows, so a retry cannot duplicate it', () => {
  const body = { startedAt: T0, timeMs: 9000, reps: [rep(), rep()] };
  assert.deepEqual(parseSync(body), parseSync(structuredClone(body)));
});

test('bad input is rejected', () => {
  assert.throws(() => parseSync(null), /reps/);
  assert.throws(() => parseSync({ startedAt: T0, reps: [] }), /no reps/);
  assert.throws(() => parseSync({ startedAt: T0, reps: Array(MAX_SYNC_REPS + 1).fill(rep()) }), /more than/);
  assert.throws(() => parseSync({ startedAt: 5, reps: [rep()] }), /startedAt/);
  assert.throws(() => parseSync({ startedAt: T0, reps: [rep({ minElbow: 999 })] }), /elbow/);
  assert.throws(() => parseSync({ startedAt: T0, reps: [rep({ secs: 'x' })] }), /seconds/);
});

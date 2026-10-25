import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';
import * as cv from '../cv-feedback.mjs';
const { repFeedback } = cv;

const scope = {
  ownerId: 'local-demo-owner',
  sessionId: '10000000-0000-4000-8000-000000000001',
  generation: '10000000-0000-4000-8000-000000000002',
};
const input = (overrides = {}) => ({
  id: '10000000-0000-4000-8000-000000000003', scope, exercise: 'squat', source: 'fixture', atMs: 1000,
  record: { n: 1, counted: true, good: true, secs: 2.4, faults: [] }, ...overrides,
});

test('an accepted browser rep preserves its facts and source without copying arbitrary cue text', () => {
  const event = repFeedback(input({ record: { n: 1, counted: true, good: true, secs: null, issue: 'untrusted text' } }));
  assert.deepEqual(event, {
    version: 1, id: input().id, scope, exercise: 'squat', source: 'fixture', atMs: 1000,
    expiresAtMs: 4000, feedback: 'good', text: 'Rep recorded.',
    rep: { number: 1, counted: true, good: true, durationSeconds: null },
  });
});

test('counted form warnings remain counted; a partial attempt never invents a rep number', () => {
  for (const exercise of ['squat', 'pushUp']) {
    const form = repFeedback(input({ exercise, record: { n: 2, counted: true, good: false, secs: 2.1 } }));
    assert.equal(form.feedback, 'form-warning');
    assert.deepEqual(form.rep, { number: 2, counted: true, good: false, durationSeconds: 2.1 });
    const partial = repFeedback(input({ exercise, record: { counted: false, good: false } }));
    assert.equal(partial.feedback, 'form-warning');
    assert.deepEqual(partial.rep, { number: null, counted: false, good: false, durationSeconds: null });
  }
});

test('the existing slow-ascent flag produces pacing feedback, with form taking priority', () => {
  const slow = repFeedback(input({ record: { n: 2, counted: true, good: true, secs: 4.5, faults: ['slow ascent'] } }));
  assert.equal(slow.feedback, 'slow');
  assert.equal(slow.text, 'Your last rep was slower. Pause if you need to.');
  assert.equal(slow.rep.durationSeconds, 4.5);
  assert.equal(repFeedback(input({ record: { counted: false, good: false, faults: ['slow ascent'] } })).feedback, 'form-warning');
  assert.equal(repFeedback(input({ record: { n: 2, counted: true, good: true, secs: 9 } })).feedback, 'good');
});

test('malformed facts and missing provenance are rejected rather than coerced into observations', () => {
  const invalid = [
    { record: null }, { record: { n: 1, counted: 'false', good: true } },
    { record: { n: 1, counted: true, good: 1 } }, { record: { counted: false, good: true } },
    { record: { n: 0, counted: true, good: true } }, { record: { n: 1.5, counted: true, good: true } },
    { record: { n: 1, counted: true, good: true, secs: -1 } },
    { record: { n: 1, counted: true, good: true, secs: NaN } },
    { record: { n: 1, counted: true, good: true, secs: '2' } },
    { record: { n: 1, counted: true, good: true, faults: 'slow ascent' } },
    { record: { n: 1, counted: true, good: true, faults: [false] } },
    { source: 'unknown' }, { source: null }, { exercise: 'running' },
    { id: '' }, { scope: {} }, { scope: { ...scope, ownerId: '' } },
    { scope: { ...scope, generation: '' } }, { atMs: NaN }, { atMs: -1 }, { atMs: '1000' },
  ];
  for (const overrides of invalid) assert.throws(() => repFeedback(input(overrides)), TypeError, JSON.stringify(overrides));
});

test('an explicit discomfort signal creates a stop without inventing an exercise observation', () => {
  const { record, ...envelope } = input();
  const event = cv.stopFeedback(envelope);
  assert.deepEqual(event, { ...envelope, version: 1, expiresAtMs: null, rep: null, feedback: 'stop', text: 'Stop and rest if you feel discomfort.' });
});

const context = (overrides = {}) => ({ scope, exercise: 'squat', source: 'fixture', phase: 'active', ...overrides });
const select = (events, overrides = {}) => cv.selectFeedback({ events, context: context(), nowMs: 1500, ...overrides });

test('selection admits current facts and prioritises stop over form, slow and good', () => {
  const good = repFeedback(input());
  const slow = repFeedback(input({ record: { n: 2, counted: true, good: true, faults: ['slow ascent'] } }));
  const form = repFeedback(input({ record: { n: 3, counted: true, good: false } }));
  const stop = cv.stopFeedback(input());
  assert.deepEqual(select([good]), good);
  assert.deepEqual(select([slow, good]), slow);
  assert.deepEqual(select([form, slow, good]), form);
  assert.deepEqual(select([stop, form, slow, good]), stop);
});

test('late, future and cancelled feedback never crosses an owner, session, generation, exercise or source', () => {
  const good = repFeedback(input());
  for (const phase of ['paused', 'cancelled', 'stopped', 'idle']) {
    assert.equal(select([good], { context: context({ phase }) }), null, phase);
  }
  for (const key of ['ownerId', 'sessionId', 'generation']) {
    assert.equal(select([good], { context: context({ scope: { ...scope, [key]: 'replacement' } }) }), null, key);
  }
  for (const change of [{ source: 'camera' }, { source: 'replay' }, { exercise: 'pushUp' }]) {
    assert.equal(select([good], { context: context(change) }), null);
  }
  for (const nowMs of [999, 4000, NaN, Infinity, -1]) assert.equal(select([good], { nowMs }), null);
  assert.deepEqual(select([good], { nowMs: 3999 }), good);
  const stop = cv.stopFeedback(input());
  assert.deepEqual(select([stop], { nowMs: 10000 }), stop);
  assert.equal(select([stop], { context: context({ phase: 'cancelled' }) }), null);
});

test('camera facts need explicit camera opt-in; provider opt-in never substitutes for it', () => {
  const camera = repFeedback(input({ source: 'camera' }));
  for (const cameraOptIn of [undefined, false, 'true', 1]) {
    assert.equal(select([camera], { context: context({ source: 'camera', cameraOptIn, providerOptIn: true }) }), null);
  }
  assert.deepEqual(select([camera], { context: context({ source: 'camera', cameraOptIn: true, providerOptIn: false }) }), camera);
  assert.equal(select([camera], { context: context({ source: 'camera', cameraOptIn: false }) }), null);
});

test('serialized events are validated again before selection and cannot inject speech or extend cue life', () => {
  const good = repFeedback(input());
  for (const event of [null, {}, { ...good, version: 2 }, { ...good, scope: null },
    { ...good, atMs: NaN }, { ...good, text: 'Pain is just information. Keep going.' },
    { ...good, expiresAtMs: null }, { ...good, expiresAtMs: 999999 },
    { ...good, feedback: 'stop' }, { ...good, rep: { ...good.rep, counted: 'false' } }]) {
    assert.equal(select([event, good]), good);
    assert.equal(select([event]), null);
  }
  assert.equal(select(null), null);
});

test('same-priority feedback uses the newest observation without changing the supplied replay clock', () => {
  const old = repFeedback(input());
  const fresh = repFeedback(input({ id: 'fresh', atMs: 1400 }));
  assert.deepEqual(select([old, fresh]), fresh);
  const loop = repFeedback(input({ id: 'next-loop', atMs: 10, source: 'replay', scope: { ...scope, generation: 'next-loop' } }));
  const replay = context({ source: 'replay', scope: loop.scope });
  assert.deepEqual(select([old, loop], { context: replay, nowMs: 20 }), loop);
  assert.equal(loop.atMs, 10);
  assert.equal(select([loop], { context: replay, nowMs: 0 }), null);
});

test('portable authored fixtures replay exact good, form, slow, partial and stop outputs', async () => {
  const fixture = JSON.parse(await readFile(new URL('../fixtures/cv-feedback.json', import.meta.url), 'utf8'));
  const records = [
    { n: 1, counted: true, good: true, secs: 2.4 },
    { n: 2, counted: true, good: false },
    { n: 2, counted: true, good: true, secs: 4.5, faults: ['slow ascent'] },
    { counted: false, good: false }, null,
  ];
  assert.equal(fixture.events.length, records.length);
  fixture.events.forEach((expected, index) => {
    const event = records[index] ? repFeedback({ ...expected, record: records[index] }) : cv.stopFeedback(expected);
    assert.deepEqual(event, expected);
    assert.deepEqual(select([event], { context: context({ exercise: event.exercise }), nowMs: event.atMs }), expected);
  });
});

import test from 'node:test';
import assert from 'node:assert/strict';
import { angle, measure, RepCounter } from '../pushup.mjs';

// Builds 33 MediaPipe-style landmarks for a person seen from the side (facing right).
// elbowDeg sets the shoulder-elbow-wrist angle; hipY moves the hip up or down (0.5 = straight line).
function pose(elbowDeg, hipY = 0.5) {
  const lm = Array.from({ length: 33 }, () => ({ x: 0, y: 0, visibility: 1 }));
  const rad = (elbowDeg * Math.PI) / 180;
  const set = (i, x, y) => { lm[i] = { x, y, visibility: 1 }; };
  for (const [sh, el, wr, hip, ank] of [[11, 13, 15, 23, 27], [12, 14, 16, 24, 28]]) {
    set(sh, 0.3, 0.5);
    set(el, 0.3, 0.6);
    set(wr, 0.3 + 0.1 * Math.sin(rad), 0.6 - 0.1 * Math.cos(rad));
    set(hip, 0.55, hipY);
    set(ank, 0.8, 0.5);
  }
  return lm;
}

// Moves the elbow through the given angles, several frames per step (the counter smooths landmarks).
function run(counter, variation, elbows, hipY = 0.5) {
  const reps = [];
  for (const target of elbows) {
    for (let i = 0; i < 6; i++) {
      const r = counter.update(measure(pose(target, hipY), 0, variation));
      if (r) reps.push(r);
    }
  }
  return reps;
}

const cycle = (low, n) => Array.from({ length: n }, () => [170, low]).flat().concat(170);

test('angle: right angle is 90 degrees', () => {
  assert.equal(Math.round(angle({ x: 1, y: 0 }, { x: 0, y: 0 }, { x: 0, y: 1 })), 90);
});

test('measure: straight body line, elbow angle follows the pose', () => {
  const m = measure(pose(90), 0, 'standard');
  assert.ok(Math.abs(m.elbow - 90) < 1);
  assert.ok(m.line > 175);
});

test('measure: corrects for image aspect ratio', () => {
  // 1920x1080 frame, pixel coords shoulder (0,0), hip (100,10), ankle (200,0): true body line is about 168.6 deg
  const lm = pose(170);
  const px = (i, x, y) => { lm[i] = { x: (500 + x) / 1920, y: (500 + y) / 1080, visibility: 1 }; };
  px(11, 0, 0); px(23, 100, 10); px(27, 200, 0);
  const raw = measure(lm, 0, 'standard');
  const fixed = measure(lm, 0, 'standard', 1920 / 1080);
  assert.ok(Math.abs(fixed.line - 168.6) < 0.5);
  assert.ok(raw.line < 161);
});

test('full reps with a straight body are counted and good', () => {
  const c = new RepCounter('standard');
  const reps = run(c, 'standard', cycle(70, 3));
  assert.equal(reps.length, 3);
  assert.equal(c.count, 3);
  assert.equal(c.goodCount, 3);
  assert.ok(reps.every((r) => r.issue === null));
});

test('partial reps are not counted and say why', () => {
  const c = new RepCounter('standard');
  const reps = run(c, 'standard', cycle(130, 3));
  assert.equal(c.count, 0);
  assert.equal(reps.length, 3);
  assert.match(reps[0].issue, /Not low enough/);
});

test('sagging hips: rep counts but is not good, with a sag cue', () => {
  const c = new RepCounter('standard');
  const reps = run(c, 'standard', cycle(70, 2), 0.58);
  assert.equal(c.count, 2);
  assert.equal(c.goodCount, 0);
  assert.match(reps[0].issue, /Hips sagging/);
});

test('piked hips give the "too high" cue', () => {
  const c = new RepCounter('standard');
  const reps = run(c, 'standard', cycle(70, 1), 0.42);
  assert.match(reps[0].issue, /Hips too high/);
});

test('low landmark visibility is ignored (no phantom reps)', () => {
  const c = new RepCounter('standard');
  const hidden = pose(70).map((p) => ({ ...p, visibility: 0.1 }));
  for (let i = 0; i < 30; i++) assert.equal(c.update(measure(hidden, 0, 'standard')), null);
  assert.equal(c.count, 0);
});

test('changing the variation resets the count', () => {
  const c = new RepCounter('standard');
  run(c, 'standard', cycle(70, 2));
  c.setVariation('knee');
  assert.equal(c.count, 0);
});

test('rep time: seconds from start of lowering to back up, null without a clock', () => {
  const frames = [[170, 0], [170, 1], [120, 1.5], [70, 2.2], [70, 2.5], [120, 2.8], [170, 3.4], [170, 3.5], [170, 3.6]];
  const f = (e) => ({ elbow: e, line: 178, hipDrop: 0, minVis: 1 });
  const timed = new RepCounter('standard'), untimed = new RepCounter('standard');
  let a, b;
  for (const [e, t] of frames) { a = timed.update(f(e), t) || a; b = untimed.update(f(e)) || b; }
  assert.ok(a.secs > 0 && a.secs < 3);
  assert.equal(b.secs, null);
});

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { RepCounter, measure, angle, grade, GREEN, AMBER, RED } from '../squat.mjs';

// A side-on standing figure in normalized coordinates (x right, y down). hipDrop lowers the hip and bends the knee.
function figure({ hipDrop = 0, lean = 0, leg = 0.5, vis = 1 } = {}) {
  const lm = Array.from({ length: 33 }, () => ({ x: 0.5, y: 0.5, z: 0, visibility: vis }));
  const ankle = { x: 0.5, y: 0.9 }, thigh = leg / 2;
  const hipY = ankle.y - leg * (1 - hipDrop);                      // hip height above the ankle shrinks with the drop
  const cosT = Math.max(0, 1 - hipDrop / 0.55);                    // thigh angle: horizontal (parallel) at 55% travel
  const kneeY = hipY + thigh * cosT, kneeX = 0.5 + thigh * Math.sqrt(1 - cosT ** 2);
  const shoulder = { x: 0.5 + Math.sin((lean * Math.PI) / 180) * 0.3, y: hipY - Math.cos((lean * Math.PI) / 180) * 0.3 };
  for (const [i, p] of [[23, { x: 0.5, y: hipY }], [24, { x: 0.5, y: hipY }], [25, { x: kneeX, y: kneeY }], [26, { x: kneeX, y: kneeY }],
    [27, ankle], [28, ankle], [11, shoulder], [12, shoulder]]) lm[i] = { ...lm[i], ...p };
  return lm;
}

// Feed a drop profile at 30 fps; returns the counter.
function run(profile, opts = {}) {
  const c = new RepCounter(opts.variation ?? 'standard');
  let t = 0;
  for (const hipDrop of profile) { c.update(figure({ hipDrop, lean: opts.lean ?? 0 }), t, 1); t += 1 / 30; }
  return c;
}
const stand = (s) => Array(Math.round(s * 30)).fill(0);
const squat = (depth, s = 2) => { const n = Math.round(s * 30); return Array.from({ length: n }, (_, i) => depth * Math.sin((Math.PI * i) / (n - 1))); };

test('angle and grade helpers', () => {
  assert.equal(Math.round(angle({ x: 0, y: 0 }, { x: 1, y: 0 }, { x: 2, y: 0 })), 180);
  assert.equal(Math.round(angle({ x: 0, y: 0 }, { x: 1, y: 0 }, { x: 1, y: 1 })), 90);
  assert.equal(grade(40, 55, 30), GREEN); assert.equal(grade(40, 55, 50), AMBER); assert.equal(grade(40, 55, 70), RED);
  assert.equal(grade(0.85, 0.7, 0.9), GREEN); assert.equal(grade(0.85, 0.7, 0.6), RED);
});

test('measure reads a standing figure', () => {
  const m = measure(figure(), 1);
  assert.ok(m.hipsOk && m.feetOk && m.kneesIn && m.feetIn);
  assert.ok(m.knee > 170, `straight leg, got ${m.knee}`);
  assert.ok(m.lean < 1);
});

test('three full squats count three, all clean', () => {
  const c = run([...stand(2), ...squat(0.6), ...stand(1), ...squat(0.6), ...stand(1), ...squat(0.6), ...stand(1)]);
  assert.equal(c.count, 3);
  assert.equal(c.goodCount, 3);
  assert.equal(c.dips, 0);
  assert.ok(c.reps.every((r) => r.secs > 1 && r.secs < 3), JSON.stringify(c.reps.map((r) => r.secs)));
});

test('a shallow dip is listed but not counted', () => {
  const c = run([...stand(2), ...squat(0.18), ...stand(1)]);
  assert.equal(c.count, 0);
  assert.equal(c.dips, 1);
  assert.equal(c.reps[0].counted, false);
  assert.match(c.reps[0].issue, /Not low enough/);
});

test('a tiny wobble is ignored entirely', () => {
  const c = run([...stand(2), ...squat(0.08), ...stand(1)]);
  assert.equal(c.reps.length, 0);
});

test('a rep faster than half a second does not count', () => {
  const c = run([...stand(2), ...squat(0.6, 0.3), ...stand(1)]);
  assert.equal(c.count, 0);
});

test('bending over at the hips is a hinge, not a squat', () => {
  // hip barely drops but the torso folds forward far past the lean limit
  const c = new RepCounter();
  let t = 0;
  for (const k of [...stand(2), ...squat(0.3), ...stand(1)]) { c.update(figure({ hipDrop: k, lean: k > 0.05 ? 85 : 0 }), t, 1); t += 1 / 30; }
  assert.equal(c.count, 0);
});

test('hallucinated hips below the frame are not a squat', () => {
  const c = new RepCounter();
  let t = 0;
  for (let i = 0; i < 90; i++) { const lm = figure(); for (const j of [23, 24, 25, 26, 27, 28]) lm[j] = { ...lm[j], y: lm[j].y + 0.8 }; c.update(lm, t, 1); t += 1 / 30; }
  assert.equal(c.reps.length, 0);
  assert.match(c.warn, /Step back/);
});

test('standing closer to the camera re-baselines instead of counting', () => {
  const c = new RepCounter();
  let t = 0;
  for (let i = 0; i < 60; i++) { c.update(figure(), t, 1); t += 1 / 30; }
  for (let i = 0; i < 120; i++) { c.update(figure({ leg: 0.7 }), t, 1); t += 1 / 30; }   // taller in the image: closer
  assert.equal(c.reps.length, 0);
  for (const k of [...squat(0.6), ...stand(1)]) { c.update(figure({ leg: 0.7, hipDrop: k }), t, 1); t += 1 / 30; }
  assert.equal(c.count, 1);
});

test('half-squat variation grades a shallow rep as good, standard does not', () => {
  const profile = [...stand(2), ...squat(0.4), ...stand(1)];
  const half = run(profile, { variation: 'half' }), standard = run(profile);
  assert.equal(half.count, 1); assert.equal(half.reps[0].good, true);
  assert.equal(standard.count, 1); assert.equal(standard.reps[0].good, false); assert.deepEqual(standard.reps[0].faults, ['shallow']);
});

// Real MediaPipe landmarks from a Creative Commons clip (Cavemantraining, CC BY-SA 4.0): five kettlebell racked squats,
// low camera angle. The Python reference counts 5; the port must agree.
test('real clip: five racked squats count five', () => {
  const clip = JSON.parse(readFileSync(new URL('./fixtures/kb_racked_squat_01.json', import.meta.url), 'utf8'));
  const c = new RepCounter();
  clip.frames.forEach((f, i) => { if (f) c.update(f.map(([x, y, z, visibility]) => ({ x, y, z, visibility })), i / clip.fps, clip.width / clip.height); });
  assert.equal(c.count, 5);
  assert.ok(c.reps.filter((r) => r.counted).every((r) => r.good), JSON.stringify(c.reps));
});

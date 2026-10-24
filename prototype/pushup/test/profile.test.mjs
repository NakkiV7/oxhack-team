import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { parseCsv, baselines, trainTree, classify, buildProfile } from '../profile.mjs';

const rows = parseCsv(readFileSync(new URL('../data/history.csv', import.meta.url), 'utf8'));

test('mock history has 300 reps over 10 sessions with all four labels', () => {
  assert.equal(rows.length, 300);
  assert.equal(new Set(rows.map((r) => r.session)).size, 10);
  const labels = new Set(rows.map((r) => r.label));
  for (const l of ['good', 'shallow', 'sagging', 'fatigued']) assert.ok(labels.has(l), l);
});

test('baselines come from good reps only and look like the real log', () => {
  const b = baselines(rows);
  assert.ok(Math.abs(b.elbow.typical - 64.5) < 1.5);
  assert.ok(Math.abs(b.body_line.typical - 171.4) < 1);
  assert.ok(b.seconds.typical > 2.5 && b.seconds.typical < 4.5);
});

test('the tree separates clearly different reps', () => {
  const tree = trainTree(rows);
  assert.equal(classify(tree, { elbow: 64, body_line: 171.5, seconds: 3.5, rep: 5 }), 'good');
  assert.equal(classify(tree, { elbow: 100, body_line: 171, seconds: 3.5, rep: 5 }), 'shallow');
  assert.equal(classify(tree, { elbow: 66, body_line: 155, seconds: 3.5, rep: 5 }), 'sagging');
});

test('profile is measured on sessions held out of training', () => {
  const p = buildProfile(rows);
  assert.ok(p.holdoutAccuracy > 0.85, `accuracy ${p.holdoutAccuracy}`);
  assert.ok(p.rules.length >= 4);
});

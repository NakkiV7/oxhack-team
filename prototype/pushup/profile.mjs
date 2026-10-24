// Personal profile from past reps: baselines (what a good rep looks like for this user) plus a small
// decision tree that reads as if/then rules. Pure functions, no DOM or file access, so it runs in node tests.

export const FEATURES = ['elbow', 'body_line', 'seconds', 'rep'];

export function parseCsv(text) {
  const [head, ...rows] = text.trim().split(/\r?\n/);
  const cols = head.split(',');
  return rows.filter(Boolean).map((line) => {
    const cells = line.split(',');
    const row = Object.fromEntries(cols.map((c, i) => [c, cells[i]]));
    for (const k of ['session', 'rep', 'elbow', 'body_line', 'seconds', 'counted']) row[k] = Number(row[k]);
    return row;
  });
}

const mean = (xs) => xs.reduce((a, b) => a + b, 0) / xs.length;
const sd = (xs) => { const m = mean(xs); return Math.sqrt(mean(xs.map((x) => (x - m) ** 2))); };
const median = (xs) => { const a = [...xs].sort((x, y) => x - y); const h = a.length >> 1; return a.length % 2 ? a[h] : (a[h - 1] + a[h]) / 2; };
const round = (x, d = 1) => Math.round(x * 10 ** d) / 10 ** d;

// Baselines from the user's good reps only. Median is used for time because rep time has long slow outliers.
export function baselines(rows) {
  const good = rows.filter((r) => r.label === 'good');
  if (!good.length) return null;
  const stat = (f, mid = mean) => ({ typical: round(mid(good.map((r) => r[f]))), spread: round(sd(good.map((r) => r[f]))) });
  return { goodReps: good.length, elbow: stat('elbow'), body_line: stat('body_line'), seconds: stat('seconds', median) };
}

const gini = (counts, n) => 1 - Object.values(counts).reduce((t, c) => t + (c / n) ** 2, 0);
const tally = (rows) => rows.reduce((c, r) => ((c[r.label] = (c[r.label] || 0) + 1), c), {});
const majority = (rows) => Object.entries(tally(rows)).sort((a, b) => b[1] - a[1])[0][0];

function bestSplit(rows, minLeaf) {
  let best = null;
  const parent = gini(tally(rows), rows.length);
  for (const feature of FEATURES) {
    const sorted = [...rows].sort((a, b) => a[feature] - b[feature]);
    for (let i = minLeaf; i <= sorted.length - minLeaf; i++) {
      if (sorted[i - 1][feature] === sorted[i][feature]) continue;
      const l = sorted.slice(0, i), r = sorted.slice(i);
      const score = parent - (l.length * gini(tally(l), l.length) + r.length * gini(tally(r), r.length)) / rows.length;
      if (!best || score > best.score) best = { score, feature, threshold: (sorted[i - 1][feature] + sorted[i][feature]) / 2 };
    }
  }
  return best;
}

export function trainTree(rows, { maxDepth = 4, minLeaf = 5 } = {}, depth = 0) {
  const counts = tally(rows);
  const split = depth < maxDepth && Object.keys(counts).length > 1 ? bestSplit(rows, minLeaf) : null;
  if (!split || split.score < 0.005) return { label: majority(rows), n: rows.length };
  const left = rows.filter((r) => r[split.feature] <= split.threshold);
  const right = rows.filter((r) => r[split.feature] > split.threshold);
  return {
    feature: split.feature,
    threshold: round(split.threshold, 2),
    left: trainTree(left, { maxDepth, minLeaf }, depth + 1),
    right: trainTree(right, { maxDepth, minLeaf }, depth + 1),
  };
}

export function classify(tree, rep) {
  let node = tree;
  while (node.feature) node = rep[node.feature] <= node.threshold ? node.left : node.right;
  return node.label;
}

// Tree -> one readable line per leaf, e.g. "elbow > 84.5 -> shallow".
export function rulesOf(tree, path = []) {
  if (!tree.feature) return [`${path.join(' and ') || 'always'} -> ${tree.label} (${tree.n} reps)`];
  return [
    ...rulesOf(tree.left, [...path, `${tree.feature} <= ${tree.threshold}`]),
    ...rulesOf(tree.right, [...path, `${tree.feature} > ${tree.threshold}`]),
  ];
}

export function accuracy(tree, rows) {
  return rows.length ? rows.filter((r) => classify(tree, r) === r.label).length / rows.length : NaN;
}

// Builds the profile. The last `holdoutSessions` sessions are kept out of training to measure the tree on
// sessions it has not seen; the shipped tree is then retrained on everything.
export function buildProfile(rows, { holdoutSessions = 2 } = {}) {
  const ids = [...new Set(rows.map((r) => r.session))].sort((a, b) => a - b);
  const test = new Set(ids.slice(-holdoutSessions));
  const trainRows = rows.filter((r) => !test.has(r.session));
  const testRows = rows.filter((r) => test.has(r.session));
  const checked = trainRows.length && testRows.length ? accuracy(trainTree(trainRows), testRows) : null;
  const tree = trainTree(rows);
  return {
    reps: rows.length,
    sessions: ids.length,
    baselines: baselines(rows),
    holdoutAccuracy: checked === null ? null : round(checked, 3),
    labels: tally(rows),
    tree,
    rules: rulesOf(tree),
  };
}

// Share of reps that are mock. Rows from the mock CSV have no `source`; they are mock by definition.
export const mockShare = (rows) => (rows.length ? rows.filter((r) => (r.source ?? 'mock') === 'mock').length / rows.length : 0);

// Is there enough history to train on? Mirrors the guidance in ALGORITHM.md: a tree needs a few hundred labeled
// reps and enough bad reps to learn from, spread over several sessions so one day's form does not dominate.
export const READY = { minReps: 300, minSessions: 5, minBad: 50 };

export function readiness(rows, need = READY) {
  const reps = rows.length;
  const sessions = new Set(rows.map((r) => r.session)).size;
  const bad = rows.filter((r) => r.label && r.label !== 'good').length;
  const missing = [];
  if (reps < need.minReps) missing.push(`${need.minReps - reps} more reps`);
  if (sessions < need.minSessions) missing.push(`${need.minSessions - sessions} more sessions`);
  if (bad < need.minBad) missing.push(`${need.minBad - bad} more bad-form reps`);
  return { ready: !missing.length, reps, sessions, bad, need, missing };
}

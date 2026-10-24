// Personal profile from past reps: baselines (what a good rep looks like for this user) plus a small
// decision tree that reads as if/then rules. Pure functions, no DOM or file access, so it runs in node tests.

export const FEATURES = ['elbow', 'body_line', 'seconds', 'rep'];

const LABELS = ['good', 'shallow', 'sagging', 'fatigued', 'piking', 'other'];
const REQUIRED = ['session', 'rep', 'elbow', 'body_line', 'seconds', 'counted', 'label'];
const COLUMNS = [...REQUIRED, 'date', 'source', 'measured_at', 'workout_id'];
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function validateRows(rows) {
  if (!Array.isArray(rows)) throw new Error('Invalid profile rows');
  return rows.map((row, index) => {
    const invalid = () => { throw new Error(`Invalid profile row ${index + 1}`); };
    if (!row || typeof row !== 'object' || Array.isArray(row)) invalid();
    if (REQUIRED.some((key) => !Object.hasOwn(row, key)) || Object.keys(row).some((key) => !COLUMNS.includes(key))) invalid();
    if (![row.session, row.rep].every((n) => Number.isSafeInteger(n) && n > 0)) invalid();
    if (![row.elbow, row.body_line].every((n) => Number.isFinite(n) && n >= 0 && n <= 180)) invalid();
    if (row.seconds !== null && (!Number.isFinite(row.seconds) || row.seconds < 0 || row.seconds > 86400)) invalid();
    if (![true, false, 0, 1].includes(row.counted) || !LABELS.includes(row.label) || (row.label === 'good' && !row.counted)) invalid();
    if (row.source !== undefined && !['mock', 'real'].includes(row.source)) invalid();
    if (row.date !== undefined && (typeof row.date !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(row.date) || !Number.isFinite(Date.parse(row.date)) || new Date(row.date).toISOString().slice(0, 10) !== row.date)) invalid();
    if (row.measured_at !== undefined && !Number.isFinite(Date.parse(row.measured_at))) invalid();
    if (row.workout_id != null && (typeof row.workout_id !== 'string' || !UUID.test(row.workout_id))) invalid();
    return row.workout_id ? { ...row, workout_id: row.workout_id.toLowerCase() } : { ...row };
  });
}

export function parseCsv(text) {
  if (typeof text !== 'string') throw new Error('Invalid profile CSV');
  if (!text.trim()) return [];
  const [head, ...lines] = text.trim().split(/\r?\n/);
  const cols = head.split(',');
  if (new Set(cols).size !== cols.length || REQUIRED.some((key) => !cols.includes(key)) || cols.some((key) => !COLUMNS.includes(key))) throw new Error('Invalid profile CSV columns');
  return validateRows(lines.filter((line) => line.trim()).map((line) => {
    const cells = line.split(',');
    if (cells.length !== cols.length || cells.some((cell) => !cell.trim())) throw new Error('Invalid profile CSV cells');
    const row = Object.fromEntries(cols.map((c, i) => [c, cells[i]]));
    for (const key of ['session', 'rep', 'elbow', 'body_line', 'seconds', 'counted']) row[key] = Number(row[key]);
    return row;
  }));
}

const usableRows = (rows) => validateRows(rows).filter((row) => row.seconds !== null);
const sessionKey = (row) => row.workout_id ?? `legacy:${row.source ?? 'mock'}:${row.session}`;

const mean = (xs) => xs.reduce((a, b) => a + b, 0) / xs.length;
const sd = (xs) => { const m = mean(xs); return Math.sqrt(mean(xs.map((x) => (x - m) ** 2))); };
const median = (xs) => { const a = [...xs].sort((x, y) => x - y); const h = a.length >> 1; return a.length % 2 ? a[h] : (a[h - 1] + a[h]) / 2; };
const round = (x, d = 1) => Math.round(x * 10 ** d) / 10 ** d;

// Baselines from the user's good reps only. Median is used for time because rep time has long slow outliers.
export function baselines(rows) {
  const good = usableRows(rows).filter((r) => r.label === 'good');
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
  if (depth === 0) rows = usableRows(rows);
  if (!rows.length) throw new Error('Not enough usable rows to fit a tree');
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
  rows = usableRows(rows);
  if (!readiness(rows).ready) throw new Error('Not enough usable profile history');
  const groups = [...new Map(rows.map((row) => [sessionKey(row), { key: sessionKey(row), session: row.session }])).values()]
    .sort((a, b) => a.session - b.session || a.key.localeCompare(b.key));
  const ids = groups.map((group) => group.key);
  const test = new Set(ids.slice(-holdoutSessions));
  const trainRows = rows.filter((r) => !test.has(sessionKey(r)));
  const testRows = rows.filter((r) => test.has(sessionKey(r)));
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
export const READY = { minReps: 300, minSessions: 5, minBad: 50, minGood: 30 };

export function readiness(rows, need = READY) {
  const totalReps = rows.length;
  rows = usableRows(rows);
  const missingDuration = totalReps - rows.length;
  const reps = rows.length;
  const sessions = new Set(rows.map(sessionKey)).size;
  const bad = rows.filter((r) => r.label && r.label !== 'good').length;
  const good = rows.filter((r) => r.label === 'good').length;
  const missing = [];
  if (reps < need.minReps) missing.push(`${need.minReps - reps} more reps`);
  if (sessions < need.minSessions) missing.push(`${need.minSessions - sessions} more sessions`);
  if (bad < need.minBad) missing.push(`${need.minBad - bad} more bad-form reps`);
  if (good < need.minGood) missing.push(`${need.minGood - good} more good-form reps`);
  return { ready: !missing.length, reps, totalReps, missingDuration, sessions, bad, good, need, missing };
}

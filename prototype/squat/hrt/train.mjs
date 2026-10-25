// Offline experiment for the tempo forecast: builds prediction origins from hrt/data/reps.csv with the same code the
// page runs (../hrt.mjs), fits the baselines and the L2 logistic model under grouped cross-validation, selects the
// cue threshold under a false-alert budget, and writes the artifacts the page and the paper read:
//   hrt/model.json          the deployable model (features, scaling, coefficients, threshold)
//   hrt/results.json        every table and curve shown in the evidence dialog
//   hrt/data/split-manifest.json
// Usage: node hrt/train.mjs [--target controlled] [--budget 1.0] [--seed 7] [--boot 1000]
import { readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { execSync } from 'node:child_process';
import { TARGETS, DEFAULT_TARGET, FEATURES, FEATURE_SETS, HORIZON, MIN_REPS, LABEL_VERSION, FEATURE_VERSION, POLICY_VERSION, violates, featuresAt, ineligible, labelAt, heuristicAlert, sigmoid } from '../hrt.mjs';

const args = process.argv.slice(2);
const opt = (k, d) => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : d; };
const TARGET = TARGETS[opt('--target', DEFAULT_TARGET)];
const BUDGET = Number(opt('--budget', 0.5));   // false alerts per monitored set: a product choice (one unnecessary interruption per two sets), not a medical constant
const SEED = Number(opt('--seed', 7)), BOOT = Number(opt('--boot', 1000));
const LAMBDAS = [0.01, 0.1, 1, 10];
const TAUS = Array.from({ length: 19 }, (_, i) => Math.round((i + 1) * 0.05 * 100) / 100);
const DATA = new URL('./data/reps.csv', import.meta.url);

// ---------- data ----------
const csvText = readFileSync(DATA, 'utf8');
const datasetSha = createHash('sha256').update(csvText).digest('hex');
const [head, ...lines] = csvText.trim().split('\n');
const cols = head.split(',');
const rows = lines.map((l) => Object.fromEntries(l.split(',').map((v, i) => [cols[i], v])));
const groups = {};
for (const r of rows) {
  const g = (groups[r.recording] ??= { recording: r.recording, split: r.split, person: r.person, provenance: r.provenance, variation: r.variation, reps: [] });
  g.reps.push({ n: r.rep_n === '' ? null : Number(r.rep_n), counted: r.counted === 'true', tDown: r.down === '' ? null : Number(r.down), tUp: r.up === '' ? null : Number(r.up),
    secs: Number(r.secs || 0), depth: r.depth === '' ? null : Number(r.depth), tEnd: Number(r.t_end) });
}

// Every counted rep of every recording is a prediction origin; most are ineligible or unobserved. Keep the counts.
const audit = { origins: 0, ineligible: {}, excluded: {}, observed: 0, positives: 0 };
const examples = [];
for (const g of Object.values(groups)) {
  if (g.split === 'unassigned') continue;
  const counted = g.reps.filter((r) => r.counted);
  for (let t = 1; t <= counted.length; t++) {
    audit.origins++;
    const why = ineligible(g.reps, t, TARGET);
    if (why) { audit.ineligible[why] = (audit.ineligible[why] ?? 0) + 1; continue; }
    const lab = labelAt(g.reps, t, TARGET, { setEnded: true });
    if (lab.state !== 'observed') { audit.excluded[lab.reason] = (audit.excluded[lab.reason] ?? 0) + 1; continue; }
    audit.observed++; audit.positives += lab.y;
    const origin = counted[t - 1];
    examples.push({ group: g.recording, person: g.person, split: g.split, t, x: featuresAt(g.reps, t, TARGET), y: lab.y, onset: lab.onsetOffset,
      leadSecs: lab.onsetOffset ? lab.futureReps[lab.onsetOffset - 1].tEnd - origin.tEnd : null, heuristic: heuristicAlert(g.reps, t), tEnd: origin.tEnd,
      nextDown: lab.futureReps[0].tDown });
  }
}
const dev = examples.filter((e) => e.split === 'dev'), testSet = examples.filter((e) => e.split === 'test');
const groupsOf = (ex) => [...new Set(ex.map((e) => e.group))];

// ---------- model ----------
const mean = (a) => a.reduce((s, v) => s + v, 0) / (a.length || 1);
const sd = (a) => { const m = mean(a); return Math.sqrt(mean(a.map((v) => (v - m) ** 2))) || 1; };
function solve(A, b) { // Gaussian elimination with partial pivoting; tiny systems only
  const n = b.length, M = A.map((r, i) => [...r, b[i]]);
  for (let c = 0; c < n; c++) {
    let p = c; for (let r = c + 1; r < n; r++) if (Math.abs(M[r][c]) > Math.abs(M[p][c])) p = r;
    [M[c], M[p]] = [M[p], M[c]];
    for (let r = 0; r < n; r++) if (r !== c && M[c][c] !== 0) { const f = M[r][c] / M[c][c]; for (let k = c; k <= n; k++) M[r][k] -= f * M[c][k]; }
  }
  return M.map((r, i) => (r[i] === 0 ? 0 : r[n] / r[i]));
}
// L2-regularised logistic regression by Newton's method: minimise mean NLL + lambda * ||beta||^2, intercept unpenalised.
function fitLogistic(ex, feats, lambda) {
  const X = ex.map((e) => feats.map((f) => (Number.isFinite(e.x[f]) ? e.x[f] : 0)));
  const mu = feats.map((_, j) => mean(X.map((r) => r[j]))), sg = feats.map((_, j) => sd(X.map((r) => r[j])));
  const Z = X.map((r) => [1, ...r.map((v, j) => (v - mu[j]) / sg[j])]);
  const y = ex.map((e) => e.y), n = ex.length, d = feats.length + 1;
  let beta = new Array(d).fill(0);
  for (let it = 0; it < 25; it++) {
    const p = Z.map((z) => sigmoid(z.reduce((s, v, j) => s + v * beta[j], 0)));
    const g = new Array(d).fill(0), H = Array.from({ length: d }, () => new Array(d).fill(0));
    for (let i = 0; i < n; i++) { const w = p[i] * (1 - p[i]); for (let j = 0; j < d; j++) { g[j] += (Z[i][j] * (p[i] - y[i])) / n; for (let k = 0; k < d; k++) H[j][k] += (w * Z[i][j] * Z[i][k]) / n; } }
    for (let j = 1; j < d; j++) { g[j] += 2 * lambda * beta[j]; H[j][j] += 2 * lambda; }
    H[0][0] += 1e-9;
    const step = solve(H, g);
    beta = beta.map((b, j) => b - step[j]);
    if (Math.max(...step.map(Math.abs)) < 1e-8) break;
  }
  const art = { features: feats, mean: mu, sd: sg, coef: beta.slice(1), intercept: beta[0], lambda };
  art.predict = (x) => { let z = beta[0]; feats.forEach((f, j) => { const v = Number.isFinite(x[f]) ? x[f] : 0; z += beta[j + 1] * ((v - mu[j]) / sg[j]); }); return sigmoid(z); };
  return art;
}
function fitRidge(ex, feats, lambda, target = (e) => e.nextDown) { // the regression fallback: next lowering duration
  const X = ex.map((e) => feats.map((f) => (Number.isFinite(e.x[f]) ? e.x[f] : 0)));
  const mu = feats.map((_, j) => mean(X.map((r) => r[j]))), sg = feats.map((_, j) => sd(X.map((r) => r[j])));
  const Z = X.map((r) => [1, ...r.map((v, j) => (v - mu[j]) / sg[j])]), y = ex.map(target), d = feats.length + 1, n = ex.length;
  const A = Array.from({ length: d }, () => new Array(d).fill(0)), b = new Array(d).fill(0);
  for (let i = 0; i < n; i++) for (let j = 0; j < d; j++) { b[j] += (Z[i][j] * y[i]) / n; for (let k = 0; k < d; k++) A[j][k] += (Z[i][j] * Z[i][k]) / n; }
  for (let j = 1; j < d; j++) A[j][j] += lambda;
  const beta = solve(A, b);
  return { predict: (x) => { let z = beta[0]; feats.forEach((f, j) => { const v = Number.isFinite(x[f]) ? x[f] : 0; z += beta[j + 1] * ((v - mu[j]) / sg[j]); }); return z; } };
}
const constant = (ex) => { const k = ex.filter((e) => e.y).length, n = ex.length; const p = (k + 1) / (n + 2); return { predict: () => p, p }; }; // Laplace-smoothed prevalence

// ---------- metrics ----------
const brier = (ps, ys) => mean(ps.map((p, i) => (p - ys[i]) ** 2));
const logloss = (ps, ys) => mean(ps.map((p, i) => { const q = Math.min(1 - 1e-12, Math.max(1e-12, p)); return -(ys[i] * Math.log(q) + (1 - ys[i]) * Math.log(1 - q)); }));
function averagePrecision(ps, ys) {
  const order = ps.map((p, i) => i).sort((a, b) => ps[b] - ps[a]);
  let tp = 0, sum = 0; const pos = ys.filter((y) => y).length;
  order.forEach((i, rank) => { if (ys[i]) { tp++; sum += tp / (rank + 1); } });
  return pos ? sum / pos : null;
}
// Alerting policy on a set of examples (all from one model's predictions): alert when p >= tau, at most one alert per
// HORIZON reps within a group. Events are onsets of a violation in the horizon; one onset matches at most one alert.
function policy(ex, alertAt, tau) {
  const byGroup = {};
  for (const e of ex) (byGroup[e.group] ??= []).push(e);
  let alerts = 0, falseAlerts = 0, matched = 0, events = 0, leads = [], leadReps = [], monitored = 0;
  for (const list of Object.values(byGroup)) {
    list.sort((a, b) => a.t - b.t); monitored++;
    let lastAlert = -Infinity; const onsetsWarned = new Set();
    const onsets = new Set(list.filter((e) => e.y).map((e) => e.t + e.onset));
    events += onsets.size;
    for (const e of list) {
      if (!alertAt(e, tau) || e.t - lastAlert < HORIZON) continue;
      alerts++; lastAlert = e.t;
      if (e.y) { const k = e.t + e.onset; if (!onsetsWarned.has(k)) { onsetsWarned.add(k); matched++; leads.push(e.leadSecs); leadReps.push(e.onset); } }
      else falseAlerts++;
    }
  }
  const med = (a) => (a.length ? [...a].sort((x, y) => x - y)[a.length >> 1] : null);
  return { tau, alerts, falseAlerts, events, matched, recall: events ? matched / events : null, precision: alerts ? matched / alerts : null,
    falseAlertsPerSet: monitored ? falseAlerts / monitored : null, monitoredSets: monitored, medianLeadSecs: med(leads), medianLeadReps: med(leadReps) };
}
function reliability(ps, ys, edges = [0, 0.2, 0.4, 0.6, 0.8, 1.0001]) {
  return edges.slice(0, -1).map((lo, i) => { const idx = ps.map((p, k) => k).filter((k) => ps[k] >= lo && ps[k] < edges[i + 1]);
    return { lo, hi: Math.min(1, edges[i + 1]), n: idx.length, meanP: idx.length ? mean(idx.map((k) => ps[k])) : null, observed: idx.length ? mean(idx.map((k) => ys[k])) : null }; });
}
function rng(seed) { let a = seed >>> 0; return () => { a = (a + 0x6d2b79f5) >>> 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; }

// ---------- grouped cross-validation on dev ----------
// Outer: leave one recording out. Inner (for lambda): leave one recording out again inside the training recordings.
function crossValidate(ex, feats, lambdas) {
  const gs = groupsOf(ex), oof = new Map(), chosen = [];
  for (const g of gs) {
    const train = ex.filter((e) => e.group !== g), held = ex.filter((e) => e.group === g);
    let best = lambdas[0];
    if (lambdas.length > 1 && groupsOf(train).length > 2) {
      let bestLoss = Infinity;
      for (const lam of lambdas) {
        const inner = [];
        for (const h of groupsOf(train)) { const tr = train.filter((e) => e.group !== h), te = train.filter((e) => e.group === h); if (!tr.some((e) => e.y) || tr.every((e) => e.y)) continue; const m = fitLogistic(tr, feats, lam); for (const e of te) inner.push([m.predict(e.x), e.y]); }
        const loss = inner.length ? logloss(inner.map((v) => v[0]), inner.map((v) => v[1])) : Infinity;
        if (loss < bestLoss) { bestLoss = loss; best = lam; }
      }
    }
    chosen.push(best);
    const m = train.some((e) => e.y) && !train.every((e) => e.y) ? fitLogistic(train, feats, best) : constant(train);
    for (const e of held) oof.set(e, m.predict(e.x));
  }
  const lam = chosen.sort((a, b) => a - b)[chosen.length >> 1];
  return { oof, lambda: lam, lambdasChosen: chosen };
}
function constantCV(ex) { const oof = new Map(); for (const g of groupsOf(ex)) { const m = constant(ex.filter((e) => e.group !== g)); for (const e of ex.filter((e) => e.group === g)) oof.set(e, m.predict()); } return { oof }; }
const summarise = (ex, oof) => { const ps = ex.map((e) => oof.get(e)), ys = ex.map((e) => e.y); return { n: ex.length, positives: ys.filter(Boolean).length, brier: brier(ps, ys), logLoss: logloss(ps, ys), averagePrecision: averagePrecision(ps, ys) }; };

const enough = dev.length >= 10 && dev.some((e) => e.y) && dev.some((e) => !e.y) && groupsOf(dev).length >= 3;
const results = {
  generatedAt: new Date().toISOString(), gitCommit: (() => { try { return execSync('git rev-parse HEAD', { encoding: 'utf8' }).trim(); } catch { return null; } })(),
  datasetSha256: datasetSha, target: TARGET, horizon: HORIZON, minReps: MIN_REPS, labelVersion: LABEL_VERSION, featureVersion: FEATURE_VERSION, policyVersion: POLICY_VERSION, budget: BUDGET, seed: SEED,
  datasetCard: {
    recordings: Object.values(groups).filter((g) => g.split !== 'unassigned').length, people: new Set(Object.values(groups).map((g) => g.person)).size,
    attempts: rows.length, countedReps: rows.filter((r) => r.counted === 'true').length,
    bySplit: Object.fromEntries(['dev', 'test'].map((s) => [s, { recordings: Object.values(groups).filter((g) => g.split === s).length, eligibleOrigins: examples.filter((e) => e.split === s).length, positives: examples.filter((e) => e.split === s && e.y).length }])),
    provenance: Object.fromEntries(Object.values(groups).map((g) => [g.recording, { split: g.split, person: g.person, provenance: g.provenance, reps: g.reps.filter((r) => r.counted).length }])),
    audit, labelDefinition: `v_t = 1 when the lowering duration of counted rep t is outside [${TARGET.L}, ${TARGET.U}] s; Y_t = 1 when v = 1 for rep t+1 or t+2; origins need ${MIN_REPS} counted reps and v_t = 0; horizons with an uncounted attempt or fewer than 2 further reps are excluded.`,
    limitations: ['Labels are produced by the rep counter, not by independent annotation.', 'Development clips were used to tune the counter.', 'Most recordings are single short sets of different people under different loads and camera angles.', 'Test split is empty until the team\'s held-out recordings are added.'],
  },
  status: enough ? 'dev-cv' : 'insufficient-data',
  dev: null, test: null, regression: null,
};

if (enough) {
  const cvFull = crossValidate(dev, FEATURE_SETS.full, LAMBDAS), cvTempo = crossValidate(dev, FEATURE_SETS.tempo, LAMBDAS), cvPos = crossValidate(dev, FEATURE_SETS.position, LAMBDAS), cvConst = constantCV(dev);
  const models = { constant: cvConst.oof, position: cvPos.oof, tempo: cvTempo.oof, full: cvFull.oof };
  const probMetrics = Object.fromEntries(Object.entries(models).map(([k, oof]) => [k, summarise(dev, oof)]));
  // Policies: frontier over tau for each probability model, the heuristic, and silence.
  const frontier = Object.fromEntries(Object.entries(models).map(([k, oof]) => [k, TAUS.map((tau) => policy(dev, (e, t) => oof.get(e) >= t, tau))]));
  const heuristic = policy(dev, (e) => e.heuristic, null);
  const silent = policy(dev, () => false, null);
  const pick = (fr) => { const ok = fr.filter((p) => p.falseAlertsPerSet <= BUDGET); if (!ok.length) return null; const best = Math.max(...ok.map((p) => p.recall ?? 0)); return ok.filter((p) => (p.recall ?? 0) === best).sort((a, b) => b.tau - a.tau)[0]; };
  const operating = Object.fromEntries(Object.entries(frontier).map(([k, fr]) => [k, pick(fr)]));
  // Paired cluster bootstrap over recordings of the out-of-fold predictions (fixed models; see docs for the caveat).
  for (const e of dev) e.pred = { full: cvFull.oof.get(e), constant: cvConst.oof.get(e), position: cvPos.oof.get(e) }; // travels with resampled copies
  const r = rng(SEED), gs = groupsOf(dev), byG = Object.fromEntries(gs.map((g) => [g, dev.filter((e) => e.group === g)]));
  const diffs = { brierFullMinusConstant: [], recallFullMinusHeuristic: [], falseAlertsFullMinusHeuristic: [], brierFullMinusPosition: [] };
  const tauStar = operating.full?.tau ?? 0.5;
  for (let b = 0; b < BOOT; b++) {
    const sample = Array.from({ length: gs.length }, () => byG[gs[Math.floor(r() * gs.length)]]).flatMap((list, i) => list.map((e) => ({ ...e, group: `${e.group}#${i}` })));
    const ys = sample.map((e) => e.y);
    diffs.brierFullMinusConstant.push(brier(sample.map((e) => e.pred.full), ys) - brier(sample.map((e) => e.pred.constant), ys));
    diffs.brierFullMinusPosition.push(brier(sample.map((e) => e.pred.full), ys) - brier(sample.map((e) => e.pred.position), ys));
    const pf = policy(sample, (e) => e.pred.full >= tauStar, tauStar), ph = policy(sample, (e) => e.heuristic, null);
    diffs.recallFullMinusHeuristic.push((pf.recall ?? 0) - (ph.recall ?? 0));
    diffs.falseAlertsFullMinusHeuristic.push((pf.falseAlertsPerSet ?? 0) - (ph.falseAlertsPerSet ?? 0));
  }
  const ci = (a) => { const s = [...a].sort((x, y) => x - y); return { low: s[Math.floor(0.025 * s.length)], high: s[Math.floor(0.975 * s.length)], mean: mean(s) }; };
  const ps = dev.map((e) => cvFull.oof.get(e)), ys = dev.map((e) => e.y);
  const calibratable = ys.filter(Boolean).length >= 10 && ys.filter((y) => !y).length >= 10;
  results.dev = {
    protocol: 'leave-one-recording-out; lambda by nested leave-one-recording-out log loss', groups: gs.length, lambdas: { full: cvFull.lambda, tempo: cvTempo.lambda, position: cvPos.lambda },
    probability: probMetrics, prevalence: ys.filter(Boolean).length / ys.length,
    policies: { ...Object.fromEntries(Object.entries(operating).map(([k, v]) => [k, v])), heuristic, silent }, frontier, budget: BUDGET,
    reliability: { full: reliability(ps, ys), status: calibratable ? 'preliminary (out-of-fold, no recalibration applied)' : 'preliminary: too few events per class to assess or fit calibration' },
    bootstrap: { resamples: BOOT, unit: 'recording', seed: SEED, intervals: Object.fromEntries(Object.entries(diffs).map(([k, v]) => [k, ci(v)])), note: 'Fixed out-of-fold predictions resampled by recording; does not include model-selection uncertainty.' },
    ablations: Object.fromEntries(Object.entries(probMetrics).map(([k, m]) => [k, { ...m, recallAtBudget: operating[k]?.recall ?? null, falseAlertsPerSet: operating[k]?.falseAlertsPerSet ?? null, tau: operating[k]?.tau ?? null }])),
    perGroup: gs.map((g) => { const list = byG[g]; const p = list.map((e) => cvFull.oof.get(e)), y = list.map((e) => e.y); return { group: g, n: list.length, positives: y.filter(Boolean).length, brierFull: brier(p, y), brierConstant: brier(list.map((e) => cvConst.oof.get(e)), y) }; }),
    primaryComparison: 'Brier score of the full logistic model against the constant baseline (bootstrap interval of the difference); policy: event recall of the full model at the selected threshold against the existing slow-ascent rule, both under the false-alert budget.',
  };
  // Regression fallback: next lowering duration, out of fold.
  const oofR = new Map(), oofLast = new Map(), oofMed = new Map();
  for (const g of gs) { const tr = dev.filter((e) => e.group !== g), m = fitRidge(tr, FEATURE_SETS.tempo, 1); for (const e of dev.filter((e) => e.group === g)) { oofR.set(e, m.predict(e.x)); oofLast.set(e, e.x.down); oofMed.set(e, e.x.down_med); } }
  const mae = (oof) => mean(dev.map((e) => Math.abs(oof.get(e) - e.nextDown)));
  results.regression = { target: 'lowering duration of rep t+1 (s)', n: dev.length, mae: { ridgeTempo: mae(oofR), lastValue: mae(oofLast), rollingMedian: mae(oofMed) },
    oof: dev.map((e) => ({ group: e.group, t: e.t, actual: e.nextDown, ridge: Math.round(oofR.get(e) * 1000) / 1000, last: e.x.down, median: e.x.down_med })), note: 'Separate fallback experiment; not the primary question.' };
  // Deployable artifact: refit on all dev examples with the selected lambda; threshold from the dev frontier.
  const finalModel = fitLogistic(dev, FEATURE_SETS.full, cvFull.lambda);
  const modelRun = `hrt-${LABEL_VERSION}-${datasetSha.slice(0, 8)}-${createHash('sha256').update(JSON.stringify({ l: cvFull.lambda, tau: tauStar, f: FEATURES })).digest('hex').slice(0, 6)}`;
  results.modelRun = modelRun;
  const artifact = { modelRun, status: results.status, target: TARGET.id, labelVersion: LABEL_VERSION, featureVersion: FEATURE_VERSION, policyVersion: POLICY_VERSION, horizon: HORIZON, minReps: MIN_REPS,
    features: finalModel.features, mean: finalModel.mean, sd: finalModel.sd, coef: finalModel.coef, intercept: finalModel.intercept, lambda: finalModel.lambda, threshold: tauStar, calibration: null,
    trainedOn: { split: 'dev', examples: dev.length, recordings: gs.length, datasetSha256: datasetSha }, generatedAt: results.generatedAt, note: 'Probabilities are out-of-fold preliminary; see results.json before quoting them.' };
  writeFileSync(new URL('./model.json', import.meta.url), JSON.stringify(artifact, null, 2) + '\n');
  // Locked test evaluation, only if held-out recordings exist. Run once; changing anything above invalidates it.
  if (testSet.length) {
    const ysT = testSet.map((e) => e.y);
    const evalModel = (m) => { const p = testSet.map((e) => m.predict(e.x)); return { n: testSet.length, positives: ysT.filter(Boolean).length, brier: brier(p, ysT), logLoss: logloss(p, ysT), averagePrecision: averagePrecision(p, ysT) }; };
    const mFull = finalModel, mPos = fitLogistic(dev, FEATURE_SETS.position, cvPos.lambda), mTempo = fitLogistic(dev, FEATURE_SETS.tempo, cvTempo.lambda), mConst = constant(dev);
    const pFull = new Map(testSet.map((e) => [e, mFull.predict(e.x)]));
    results.test = { protocol: 'held-out recordings, evaluated once with the frozen dev configuration', groups: groupsOf(testSet).length, prevalence: ysT.filter(Boolean).length / ysT.length,
      probability: { constant: evalModel(mConst), position: evalModel(mPos), tempo: evalModel(mTempo), full: evalModel(mFull) },
      policies: { full: policy(testSet, (e) => pFull.get(e) >= tauStar, tauStar), heuristic: policy(testSet, (e) => e.heuristic, null), silent: policy(testSet, () => false, null) },
      reliability: reliability(testSet.map((e) => pFull.get(e)), ysT), perGroup: groupsOf(testSet).map((g) => { const l = testSet.filter((e) => e.group === g); return { group: g, n: l.length, positives: l.filter((e) => e.y).length, brierFull: brier(l.map((e) => pFull.get(e)), l.map((e) => e.y)) }; }) };
  }
}

writeFileSync(new URL('./results.json', import.meta.url), JSON.stringify(results, null, 2) + '\n');
writeFileSync(new URL('./data/split-manifest.json', import.meta.url), JSON.stringify({ datasetSha256: datasetSha, groups: Object.fromEntries(Object.values(groups).map((g) => [g.recording, g.split])) }, null, 2) + '\n');

// ---------- console summary ----------
const f3 = (v) => (v == null ? '  n/a' : v.toFixed(3));
console.log(`target ${TARGET.id}  origins ${audit.origins}  eligible+observed ${audit.observed} (positives ${audit.positives})  ineligible ${JSON.stringify(audit.ineligible)}  excluded ${JSON.stringify(audit.excluded)}`);
console.log(`dev examples ${dev.length} in ${groupsOf(dev).length} recordings; test examples ${testSet.length} in ${groupsOf(testSet).length} recordings; status ${results.status}`);
if (results.dev) {
  console.log('model      n   pos  brier  logloss  AP     recall@budget  FA/set  tau');
  for (const [k, m] of Object.entries(results.dev.ablations)) console.log(k.padEnd(9), String(m.n).padStart(3), String(m.positives).padStart(4), f3(m.brier), f3(m.logLoss), f3(m.averagePrecision), '   ', f3(m.recallAtBudget), '   ', f3(m.falseAlertsPerSet), ' ', m.tau ?? '');
  const h = results.dev.policies.heuristic; console.log('heuristic (slow ascent rule): recall', f3(h.recall), 'FA/set', f3(h.falseAlertsPerSet), 'alerts', h.alerts, 'events', h.events, 'median lead', h.medianLeadSecs, 's');
  console.log('bootstrap:', JSON.stringify(results.dev.bootstrap.intervals));
  console.log('regression MAE:', JSON.stringify(results.regression.mae));
  console.log('lambda', results.dev.lambdas.full, 'threshold', results.modelRun && JSON.parse(readFileSync(new URL('./model.json', import.meta.url), 'utf8')).threshold);
}
if (results.test) console.log('TEST (locked):', JSON.stringify(results.test.probability.full), 'policy', JSON.stringify(results.test.policies.full));
console.log('wrote hrt/results.json, hrt/model.json, hrt/data/split-manifest.json');

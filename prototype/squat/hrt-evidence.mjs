// Renders the "How the predictions perform" dialog from the saved evaluation artifact (hrt/results.json) and the stored
// forecasts of one workout (GET /hrt/review). Nothing is computed here beyond formatting; unsupported numbers read
// "not evaluated" rather than being invented.
const esc = (s) => String(s).replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]));
const f = (v, d = 3) => (v == null || Number.isNaN(v) ? 'not evaluated' : typeof v === 'number' ? v.toFixed(d) : esc(v));
const pct = (v) => (v == null ? 'not evaluated' : `${(v * 100).toFixed(0)}%`);
const table = (cols, rows) => `<table><tr>${cols.map((c) => `<th>${esc(c)}</th>`).join('')}</tr>${rows.map((r) => `<tr>${r.map((c) => `<td>${c}</td>`).join('')}</tr>`).join('')}</table>`;
const ci = (c) => (c && c.low != null ? `${f(c.mean)} [${f(c.low)}, ${f(c.high)}]` : 'not evaluated');

// Small SVG helpers: a 300x120 plot area with linear axes.
const W = 300, H = 120, PAD = { l: 34, r: 8, t: 8, b: 22 };
const sx = (x, x0, x1) => PAD.l + ((x - x0) / (x1 - x0 || 1)) * (W - PAD.l - PAD.r);
const sy = (y, y0, y1) => H - PAD.b - ((y - y0) / (y1 - y0 || 1)) * (H - PAD.t - PAD.b);
const axes = (xl, yl, x0, x1, y0, y1) => `<line x1="${PAD.l}" y1="${sy(y0, y0, y1)}" x2="${W - PAD.r}" y2="${sy(y0, y0, y1)}" stroke="currentColor" opacity=".4"/><line x1="${PAD.l}" y1="${sy(y1, y0, y1)}" x2="${PAD.l}" y2="${sy(y0, y0, y1)}" stroke="currentColor" opacity=".4"/>
  <text x="${W / 2}" y="${H - 4}" font-size="9" text-anchor="middle" fill="currentColor">${esc(xl)}</text><text x="9" y="${H / 2}" font-size="9" text-anchor="middle" fill="currentColor" transform="rotate(-90 9 ${H / 2})">${esc(yl)}</text>
  <text x="${PAD.l}" y="${H - PAD.b + 10}" font-size="8" fill="currentColor">${x0}</text><text x="${W - PAD.r}" y="${H - PAD.b + 10}" font-size="8" text-anchor="end" fill="currentColor">${x1}</text>
  <text x="${PAD.l - 3}" y="${sy(y1, y0, y1) + 3}" font-size="8" text-anchor="end" fill="currentColor">${y1}</text>`;
const svg = (inner, label) => `<svg viewBox="0 0 ${W} ${H}" role="img" aria-label="${esc(label)}">${inner}</svg>`;

function reliabilityPlot(bins) {
  if (!bins?.length) return '<p class="sub">not evaluated</p>';
  const pts = bins.filter((b) => b.n).map((b) => `<circle cx="${sx(b.meanP, 0, 1)}" cy="${sy(b.observed, 0, 1)}" r="${3 + Math.min(6, b.n)}" fill="#0a84ff" opacity=".7"/><text x="${sx(b.meanP, 0, 1)}" y="${sy(b.observed, 0, 1) - 9}" font-size="8" text-anchor="middle" fill="currentColor">n=${b.n}</text>`).join('');
  return svg(`${axes('predicted probability', 'observed rate', 0, 1, 0, 1)}<line x1="${sx(0, 0, 1)}" y1="${sy(0, 0, 1)}" x2="${sx(1, 0, 1)}" y2="${sy(1, 0, 1)}" stroke="currentColor" stroke-dasharray="3 3" opacity=".5"/>${pts}`, 'Reliability diagram with bin counts');
}
function frontierPlot(frontier, heuristic, selected, silent, budget) {
  if (!frontier?.length) return '<p class="sub">not evaluated</p>';
  const xmax = Math.max(1, ...frontier.map((p) => p.falseAlertsPerSet ?? 0), heuristic?.falseAlertsPerSet ?? 0);
  const line = frontier.filter((p) => p.recall != null).map((p) => `${sx(p.falseAlertsPerSet, 0, xmax)},${sy(p.recall, 0, 1)}`).join(' ');
  const mark = (p, color, label) => (p && p.recall != null ? `<circle cx="${sx(p.falseAlertsPerSet, 0, xmax)}" cy="${sy(p.recall, 0, 1)}" r="4" fill="${color}"/><text x="${sx(p.falseAlertsPerSet, 0, xmax) + 6}" y="${sy(p.recall, 0, 1) + 3}" font-size="8" fill="currentColor">${esc(label)}</text>` : '');
  return svg(`${axes('false alerts per monitored set', 'event recall', 0, xmax.toFixed(1), 0, 1)}<line x1="${sx(budget, 0, xmax)}" y1="${sy(0, 0, 1)}" x2="${sx(budget, 0, xmax)}" y2="${sy(1, 0, 1)}" stroke="#ff9f0a" stroke-dasharray="3 3"/><polyline points="${line}" fill="none" stroke="#0a84ff" stroke-width="1.5"/>${mark(selected, '#0a84ff', `selected τ=${selected?.tau}`)}${mark(heuristic, '#30d158', 'slow-ascent rule')}${mark(silent, '#8e8e93', 'silent')}`, 'Recall against false alerts per set, with the budget line');
}
function timelinePlot(rows) {
  const fc = rows.filter((r) => r.probability != null);
  if (!fc.length) return '<p class="sub">No forecasts stored for this workout.</p>';
  const xmax = Math.max(...fc.map((r) => r.rep_n + (r.onset_offset ?? 0))) + 1;
  const pts = fc.map((r) => `<circle cx="${sx(r.rep_n, 0, xmax)}" cy="${sy(r.probability, 0, 1)}" r="3" fill="${r.action === 'cue' ? '#ff9f0a' : '#0a84ff'}"><title>after rep ${r.rep_n}: p=${f(r.probability, 2)} ${r.action}</title></circle>`).join('');
  const onsets = fc.filter((r) => r.outcome === 1).map((r) => `<line x1="${sx(r.rep_n + r.onset_offset, 0, xmax)}" y1="${sy(0, 0, 1)}" x2="${sx(r.rep_n + r.onset_offset, 0, xmax)}" y2="${sy(1, 0, 1)}" stroke="#ff453a" opacity=".6"><title>tempo outside range at rep ${r.rep_n + r.onset_offset}</title></line>`).join('');
  const gaps = fc.filter((r) => r.state === 'excluded').map((r) => `<rect x="${sx(r.rep_n, 0, xmax) - 2}" y="${PAD.t}" width="4" height="${H - PAD.t - PAD.b}" fill="currentColor" opacity=".12"><title>horizon excluded: ${esc(r.exclusion_reason)}</title></rect>`).join('');
  const thr = fc[0].threshold != null ? `<line x1="${PAD.l}" y1="${sy(fc[0].threshold, 0, 1)}" x2="${W - PAD.r}" y2="${sy(fc[0].threshold, 0, 1)}" stroke="#ff9f0a" stroke-dasharray="3 3"/>` : '';
  return svg(`${axes('rep', 'forecast probability', 0, xmax, 0, 1)}${gaps}${onsets}${thr}${pts}`, 'Forecast timeline: probability at each origin, onsets in red, cues in orange');
}

export function renderEvidence(results, review) {
  if (!results) return '<p class="sub">No evaluation artifact for this target yet. Run <code>node hrt/train.mjs --target &lt;key&gt;</code> in prototype/squat.</p>';
  const d = results.dev, t = results.test, card = results.datasetCard;
  const rows = review?.rows ?? [];
  const mode = rows[0]?.mode, prov = rows[0]?.provenance;
  const polRow = (name, p) => [name, f(p?.recall, 2), f(p?.falseAlertsPerSet, 2), p?.medianLeadSecs != null ? `${f(p.medianLeadSecs, 1)} s / ${p.medianLeadReps} rep` : 'not evaluated', `${p?.alerts ?? 0} alerts, ${p?.events ?? 0} events`];
  const probRow = (name, m, pol) => [name, m ? m.n : '', f(m?.brier), f(m?.logLoss), f(m?.averagePrecision), pct(pol?.recall), f(pol?.falseAlertsPerSet, 2)];
  const section = (title, body) => `<h3>${esc(title)}</h3>${body}`;
  const status = results.status === 'insufficient-data' ? '<p><b>Status: insufficient data.</b> The infrastructure runs; no model was fitted.</p>' : t ? '<p><b>Status: locked held-out evaluation available.</b></p>' : '<p><b>Status: development results only</b> (grouped cross-validation on the development recordings). The held-out test has not been run: no test recordings in the dataset yet.</p>';
  const testBlock = t ? section('Locked held-out test', table(['model', 'n', 'Brier', 'log loss', 'AP', 'recall@budget', 'false alerts/set'], [
    probRow('constant', t.probability.constant, null), probRow('set position', t.probability.position, null), probRow('tempo', t.probability.tempo, null), probRow('full', t.probability.full, t.policies.full), polRow('slow-ascent rule', t.policies.heuristic), polRow('silent', t.policies.silent)]) +
    `<p class="sub">${t.groups} held-out recordings, prevalence ${pct(t.prevalence)}. ${esc(t.protocol)}.</p>${reliabilityPlot(t.reliability)}`) : '';
  return `
  <p class="sub">Target: ${esc(results.target.label)} · horizon ${results.horizon} reps · label ${esc(results.labelVersion)} · features ${esc(results.featureVersion)} · policy ${esc(results.policyVersion)} · budget ${results.budget} false alerts per set.</p>
  ${status}
  ${section('A. Forecast timeline, this workout', `${timelinePlot(rows)}<p class="sub">${rows.length ? `${rows.length} stored forecasts · ${esc(mode)} mode · ${esc(prov)} provenance · ${review.persisted ? 'read back from Tiger Data' : 'not persisted'}` : 'Run a set with the forecaster on to see its stored forecasts here.'}</p>`)}
  ${testBlock}
  ${d ? section('B. Baselines, development (out of fold)', table(['model', 'n', 'Brier', 'log loss', 'AP', 'recall@budget', 'false alerts/set'], [
    probRow('A constant (train prevalence)', d.probability.constant, d.policies.constant), probRow('B set position', d.probability.position, d.policies.position), probRow('tempo features', d.probability.tempo, d.policies.tempo),
    probRow('D tempo + pose (deployed)', d.probability.full, d.policies.full), polRow('C existing slow-ascent rule', d.policies.heuristic), polRow('always silent', d.policies.silent)]) +
    `<p class="sub">${d.groups} development recordings, ${d.probability.full.n} eligible origins, prevalence ${pct(d.prevalence)}. λ=${d.lambdas.full}. Lower Brier and log loss are better; "recall@budget" is event recall at the highest threshold whose false alerts per set stay within ${d.budget}.</p>
     <p class="sub">Paired bootstrap over recordings (${d.bootstrap.resamples} resamples, seed ${d.bootstrap.seed}), mean [2.5%, 97.5%]: Brier full − constant ${ci(d.bootstrap.intervals.brierFullMinusConstant)}; Brier full − position ${ci(d.bootstrap.intervals.brierFullMinusPosition)}; recall full − rule ${ci(d.bootstrap.intervals.recallFullMinusHeuristic)}; false alerts/set full − rule ${ci(d.bootstrap.intervals.falseAlertsFullMinusHeuristic)}. ${esc(d.bootstrap.note)}</p>`) : ''}
  ${d ? section('C. Calibration', `${reliabilityPlot(d.reliability.full)}<p class="sub">${esc(d.reliability.status)}. Circles scale with bin count.</p>`) : ''}
  ${d ? section('D. Decision frontier', `${frontierPlot(d.frontier.full, d.policies.heuristic, d.policies.full, d.policies.silent, d.budget)}<p class="sub">Each point is a threshold; the orange line is the false-alert budget. ${d.policies.full ? `Selected τ=${d.policies.full.tau}.` : 'No threshold met the budget, so the deployed policy stays silent.'}</p>`) : ''}
  ${d ? section('E. Ablations', table(['features', 'Brier', 'log loss', 'AP', 'recall@budget'], [
    ['set position only', f(d.ablations.position.brier), f(d.ablations.position.logLoss), f(d.ablations.position.averagePrecision), pct(d.ablations.position.recallAtBudget)],
    ['tempo', f(d.ablations.tempo.brier), f(d.ablations.tempo.logLoss), f(d.ablations.tempo.averagePrecision), pct(d.ablations.tempo.recallAtBudget)],
    ['tempo + pose', f(d.ablations.full.brier), f(d.ablations.full.logLoss), f(d.ablations.full.averagePrecision), pct(d.ablations.full.recallAtBudget)],
    d.ablations.history ? ['+ prior personal history (earlier sets)', f(d.ablations.history.brier), f(d.ablations.history.logLoss), f(d.ablations.history.averagePrecision), pct(d.ablations.history.recallAtBudget)] : ['+ prior personal history', 'not evaluated', 'not evaluated', 'not evaluated', 'not evaluated'],
    ['+ biometrics (Watch)', 'not evaluated', 'not evaluated', 'not evaluated', 'not evaluated']]) +
    (results.personal ? `<p class="sub"><b>Personalisation, chronological</b> (${esc(results.personal.person)}, ${results.personal.sets} sets; each set predicted by models trained on the clips plus that person's earlier sets only; separate from unseen-person generalisation): pooled ${results.personal.pooled.n} origins, ${results.personal.pooled.positives} positive; Brier history ${f(results.personal.pooled.brierHistory)}, tempo+pose ${f(results.personal.pooled.brierFull)}, constant ${f(results.personal.pooled.brierConstant)}; recall at the frozen threshold history ${pct(results.personal.policy.history.recall)} (${f(results.personal.policy.history.falseAlertsPerSet, 2)} false alerts/set), rule ${pct(results.personal.policy.heuristic.recall)} (${f(results.personal.policy.heuristic.falseAlertsPerSet, 2)}).</p>` : '') +
    `<p class="sub">All on the same ${d.probability.full.n} origins. History and biometrics: no such data recorded yet.</p>` +
    (results.regression ? `<p class="sub">Separate regression fallback (next lowering duration, MAE): ridge ${f(results.regression.mae.ridgeTempo, 2)} s · last value ${f(results.regression.mae.lastValue, 2)} s · rolling median ${f(results.regression.mae.rollingMedian, 2)} s.</p>` : '')) : ''}
  ${section('F. Dataset card', `<p class="sub">${card.people} people · ${card.recordings} recordings · ${card.attempts} attempts · ${card.countedReps} counted reps · dev: ${card.bySplit.dev.eligibleOrigins} eligible origins (${card.bySplit.dev.positives} positive) in ${card.bySplit.dev.recordings} recordings · test: ${card.bySplit.test.eligibleOrigins} origins in ${card.bySplit.test.recordings} recordings.</p>
    <p class="sub">Origins ${card.audit.origins}: ineligible ${esc(JSON.stringify(card.audit.ineligible))}, excluded ${esc(JSON.stringify(card.audit.excluded))}.</p>
    <p class="sub"><b>Label.</b> ${esc(card.labelDefinition)}</p><ul>${card.limitations.map((l) => `<li>${esc(l)}</li>`).join('')}</ul>
    ${table(['recording', 'split', 'person', 'provenance', 'counted reps'], Object.entries(card.provenance).map(([k, v]) => [esc(k), v.split, esc(v.person), esc(v.provenance), v.reps]))}`)}
  ${section('G. Reproducibility', `<p class="sub">Model ${esc(results.modelRun ?? 'none')} · dataset sha256 ${esc((results.datasetSha256 ?? '').slice(0, 16))}… · commit ${esc((results.gitCommit ?? '').slice(0, 10))} · evaluated ${esc(results.generatedAt)} · seed ${results.seed}.<br>
    <code>node hrt/build_dataset.mjs &lt;landmark-dir&gt;</code> then <code>node hrt/train.mjs</code>. Paper: <a href="/docs/hrt-paper/main.pdf" target="_blank">docs/hrt-paper/main.pdf</a> (opens if built).</p>`)}`;
}

// "What we anticipated" for the set summary, from stored rows. Returns HTML.
export function renderReview(review, target, localReps = []) { // target: the set's bounds { L, U }
  const rows = review?.rows ?? [];
  if (!rows.length) return `<b>What we anticipated.</b> ${review?.persisted ? 'No forecast was eligible in this set (forecasts need three counted reps in range and two more reps to resolve).' : 'Forecasts were not persisted (Tiger Data off).'}`;
  if (!target) target = { L: -Infinity, U: Infinity };
  const items = rows.map((r) => {
    const head = `After rep ${r.rep_n}: ${r.action === 'cue' ? 'cued' : r.action === 'suppressed' && r.suppressed_reason === 'shadow_mode' ? 'would have cued (shadow)' : r.action === 'suppressed' ? 'cue held (cooldown)' : 'no cue'} · p=${f(r.probability, 2)} (preliminary).`;
    let body;
    if (!r.state) body = 'Horizon still open.';
    else if (r.state === 'excluded') body = r.exclusion_reason === 'after_departure' ? 'Made after the tempo had already shifted; not scored.' : `Horizon incomplete: ${r.exclusion_reason === 'set_ended' ? 'the set ended' : 'an attempt in the horizon did not count'}.`;
    else if (r.outcome === 1) body = `${r.coached ? 'Observed after coaching' : 'Observed'}: the tempo left ${target.L} to ${target.U} s from rep ${r.rep_n + r.onset_offset} and stayed out. Warning lead time ${f(r.lead_secs, 1)} s (${r.onset_offset} rep${r.onset_offset > 1 ? 's' : ''}).`;
    else body = `${r.coached ? 'Observed after coaching' : 'Observed'}: no sustained departure began in the next two reps.`;
    return `<li><b>${esc(head)}</b><br>${esc(body)}</li>`;
  });
  // Onsets that no eligible forecast preceded (from the page's own rep list, labelled as such).
  const counted = localReps.filter((r) => r.counted);
  const v = counted.map((r) => !(r.tDown >= target.L && r.tDown <= target.U));
  let k = null; for (let i = 0; i < v.length; i++) if (v[i] && i + 2 < v.length && v[i] + v[i + 1] + v[i + 2] >= 2) { k = i + 1; break; }
  const warned = new Set(rows.filter((r) => r.probability >= (r.threshold ?? 1)).flatMap((r) => [r.rep_n + 1, r.rep_n + 2]));
  const missed = k != null && !warned.has(k) ? `<li>The tempo shifted from rep ${k} without an eligible warning.</li>` : '';
  return `<b>What we anticipated</b> <span class="sub">(${review.persisted ? 'from stored records' : 'not persisted'})</span><ul>${items.join('')}${missed}</ul>`;
}

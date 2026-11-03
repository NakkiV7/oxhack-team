// Session reports and weekly reviews, rendered as readable stories from the stored facts. Every number shown comes from the
// saved report; Gemini's narrative is shown as a labelled summary that cites the facts it rests on.
import { icon } from './emblems.mjs';

const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const when = (iso) => new Date(iso).toLocaleString(undefined, { weekday: 'short', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' });
const dayRange = (a, b) => { const s = new Date(a + 'T12:00:00Z'), e = new Date(b + 'T12:00:00Z'); e.setUTCDate(e.getUTCDate() - 1); const f = (d) => d.toLocaleDateString(undefined, { day: 'numeric', month: 'short', timeZone: 'UTC' }); return `${f(s)} – ${f(e)}`; };
const chips = (ids = []) => (ids.length ? `<span class="cites">${ids.map((i) => `<span class="cite" title="Calculated fact">${esc(i.replace(/^attempt:/, 'attempt '))}</span>`).join('')}</span>` : '');
const SRC = { camera: { t: 'Camera set', i: 'camera' }, video: { t: 'Replayed video', i: 'repeat' } };
const RESULT = { closer: { t: 'Closer to the target', c: 'good' }, similar: { t: 'About the same', c: 'neutral' }, further: { t: 'Further from the target', c: 'warn' }, unable: { t: 'Unable to assess', c: 'neutral' } };

function tile(label, value, sub = '', cls = '') { return `<div class="stat ${cls}"><div class="sl">${esc(label)}</div><div class="sv2">${value}</div>${sub ? `<div class="ss">${sub}</div>` : ''}</div>`; }

// Lowering time per counted rep, with the target band when an assessment set one.
function tempoChart(reps, band) {
  const rs = reps.filter((r) => r.counted && Number.isFinite(r.down));
  if (rs.length < 2) return '';
  const W = 640, H = 150, P = { l: 34, r: 10, t: 12, b: 24 }, max = Math.max(2, ...rs.map((r) => r.down), band ? band.hi : 0) * 1.08;
  const x = (i) => P.l + (i + 0.5) * ((W - P.l - P.r) / rs.length), y = (v) => H - P.b - (v / max) * (H - P.t - P.b), bw = Math.max(3, Math.min(22, ((W - P.l - P.r) / rs.length) * 0.62));
  const ticks = [0, 0.5, 1, 1.5, 2, 2.5, 3, 4, 5].filter((t) => t <= max);
  return `<figure class="chart"><figcaption>${icon('clock', 15)} Lowering time per rep</figcaption><svg viewBox="0 0 ${W} ${H}" role="img" aria-label="Lowering time per counted rep">
    ${ticks.map((t) => `<line x1="${P.l}" x2="${W - P.r}" y1="${y(t)}" y2="${y(t)}" class="grid"/><text x="${P.l - 6}" y="${y(t) + 4}" class="ax" text-anchor="end">${t}s</text>`).join('')}
    ${band ? `<rect x="${P.l}" width="${W - P.l - P.r}" y="${y(band.hi)}" height="${y(band.lo) - y(band.hi)}" class="band"/><text x="${W - P.r - 4}" y="${y(band.hi) - 4}" class="ax" text-anchor="end">target ${band.lo}–${band.hi} s</text>` : ''}
    ${rs.map((r, i) => `<rect x="${x(i) - bw / 2}" width="${bw}" y="${y(r.down)}" height="${H - P.b - y(r.down)}" rx="2" class="bar ${r.good ? '' : 'fault'}"><title>Rep ${r.n}: ${r.down} s${r.good ? '' : ' · ' + (r.faults ?? []).join(', ')}</title></rect>`).join('')}
    ${rs.length <= 30 ? rs.map((r, i) => `<text x="${x(i)}" y="${H - 8}" class="ax" text-anchor="middle">${r.n}</text>`).join('') : ''}
  </svg><div class="legend"><span><i class="k bar"></i>clean rep</span><span><i class="k fault"></i>rep with a form note</span>${band ? '<span><i class="k band"></i>target band</span>' : ''}</div></figure>`;
}

// Baseline vs retry on one number line with the target band.
function attemptCard(a) {
  const o = a.outcome, r = RESULT[o?.classification] ?? { t: a.status, c: 'neutral' };
  if (!o || o.baselineMedian == null) return `<div class="attempt"><div class="ah"><span class="pill ${r.c}">${esc(r.t)}</span></div><p class="muted">${esc(o?.reason ?? 'This attempt did not finish.')}</p></div>`;
  const lo = Math.min(o.baselineMedian, o.retryMedian, o.target - o.tolerance) - 0.3, hi = Math.max(o.baselineMedian, o.retryMedian, o.target + o.tolerance) + 0.3, pc = (v) => (100 * (v - lo)) / (hi - lo);
  return `<div class="attempt"><div class="ah"><span class="pill ${r.c}">${esc(r.t)}</span><span class="muted">${o.baselineN} baseline and ${o.retryN} retry reps · ${esc(o.contractVersion)}</span></div>
    ${a.cue?.text ? `<blockquote>${icon('chat', 16)} “${esc(a.cue.text)}”<span class="muted"> · ${a.cue.provenance === 'gemini' ? 'Gemini cue' : 'deterministic cue'}</span></blockquote>` : ''}
    <div class="line" aria-label="Baseline median ${o.baselineMedian} s, retry median ${o.retryMedian} s, target ${o.target} s">
      <div class="track"><span class="tband" style="left:${pc(o.target - o.tolerance)}%;width:${pc(o.target + o.tolerance) - pc(o.target - o.tolerance)}%"></span>
        <span class="dot before" style="left:${pc(o.baselineMedian)}%"><b>${o.baselineMedian}s</b><i>before</i></span><span class="dot after" style="left:${pc(o.retryMedian)}%"><b>${o.retryMedian}s</b><i>after</i></span></div>
      <div class="muted small">Target ${o.target} s ± ${o.tolerance} s (median lowering time)</div></div>
    ${a.explanation?.text ? `<p class="expl">${esc(a.explanation.text)}${a.explanation.provenance === 'gemini' ? ' <span class="muted">· Gemini, from the computed result</span>' : ''}</p>` : ''}
    ${o.classification === 'unable' && o.reason ? `<p class="muted">${esc(o.reason)}</p>` : ''}</div>`;
}

export function renderSession(r, { onNarrate } = {}) {
  const fact = (id) => r.facts.find((f) => f.id === id);
  const src = (r.workout.note ?? '').startsWith('synthetic') ? { t: 'Synthetic sample', i: 'info' } : SRC[r.workout.source] ?? { t: r.workout.source, i: 'info' };
  const counted = r.reps.filter((x) => x.counted), clean = counted.filter((x) => x.good).length;
  const band = r.attempts.find((a) => a.target)?.target ? { lo: +(r.attempts.find((a) => a.target).target.value - r.attempts.find((a) => a.target).target.tolerance).toFixed(2), hi: +(r.attempts.find((a) => a.target).target.value + r.attempts.find((a) => a.target).target.tolerance).toFixed(2) } : null;
  const moments = r.timeline.filter((t) => t.kind !== 'rep');
  const first = counted[0], last = counted[counted.length - 1];
  return `<article class="report">
    <header class="hero"><div class="kicker">${icon(src.i, 16)} ${esc(src.t)}${r.workout.note && !r.workout.note.startsWith('synthetic') ? ` · ${esc(r.workout.note)}` : ''}</div><h2>${esc(r.workout.exercise === 'squat' ? 'Squat session' : r.workout.exercise)}</h2><div class="sub">${esc(when(r.workout.started_at))}</div></header>
    ${r.narrative?.headline ? `<section class="callout"><div class="ck">${icon('spark', 16)} Coach's summary</div><p class="big">${esc(r.narrative.headline.text)}</p>${(r.narrative.insights ?? []).map((i) => `<p>${esc(i.text)} ${chips(i.factIDs)}</p>`).join('')}<div class="muted small">Written by Gemini from the calculated facts below; tags show the facts each line rests on.</div></section>` : `<section class="callout quiet"><div class="ck">${icon('spark', 16)} Coach's summary</div><p class="muted">Not written yet. One Gemini call turns the facts below into a short summary, then it is saved.</p><button class="ghost" data-narrate>Write the summary</button></section>`}
    <div class="stats">${tile('Duration', esc((fact('duration')?.text ?? '').replace('Recorded workout duration ', '') || '–'))}${tile('Counted reps', counted.length, r.reps.length > counted.length ? `${r.reps.length - counted.length} not counted` : '')}${tile('Median lowering', fact('lowering') ? `${fact('lowering').value}<small>s</small>` : '–')}${tile('Clean form', counted.length ? `${Math.round((100 * clean) / counted.length)}<small>%</small>` : '–', `${clean} of ${counted.length} reps`)}</div>
    ${tempoChart(r.reps, band)}
    ${r.attempts.length ? `<section><h3>${icon('target', 18)} Coach, retry, verify</h3>${r.attempts.map(attemptCard).join('')}</section>` : ''}
    <section class="two"><div class="box"><h3>${icon('route', 18)} Tempo forecasts</h3><p>${r.predictions.length ? `<b>${r.predictions.length}</b> forecasts recorded in shadow mode, <b>${r.predictions.filter((p) => p.state === 'observed').length}</b> resolved, <b>${r.predictions.filter((p) => p.outcome === 1).length}</b> with a tempo departure.` : 'None recorded in this set.'}</p></div>
      <div class="box"><h3>${icon('bolt', 18)} Biometrics</h3><p class="muted">${esc((fact('biometrics')?.text ?? 'No readings recorded').replace(/\.?\s*$/, '.'))} Missing readings are shown as missing, never as zero.</p></div></section>
    <section><h3>${icon('clock', 18)} Moments</h3><ol class="moments">
      ${[...(first ? [{ at: first.at, kind: '', text: 'First counted rep' }] : []), ...moments, ...(last && last !== first ? [{ at: last.at, kind: '', text: `Last counted rep (${counted.length} in total)` }] : [])]
        .sort((a, b) => Date.parse(a.at) - Date.parse(b.at))
        .map((m) => `<li class="${m.kind}"><span class="t">${esc(new Date(m.at).toLocaleTimeString())}</span><span class="d">${esc(m.text)}</span></li>`).join('')}</ol></section>
    <details class="facts"><summary>All calculated facts (${r.facts.length})</summary><ul>${r.facts.map((f) => `<li>${esc(f.text)} <span class="cite">${esc(f.id.replace(/^attempt:/, 'attempt '))}</span></li>`).join('')}</ul></details>
  </article>`;
}

function delta(cur, prev, { unit = '', better = 'up' } = {}) {
  if (prev == null) return '<span class="delta none">no earlier week</span>';
  if (prev === 0 && cur === 0) return '<span class="delta none">same as last week</span>';
  if (prev === 0) return '<span class="delta new">new this week</span>';
  const d = Math.round((cur - prev) * 100) / 100; if (!d) return '<span class="delta none">same as last week</span>';
  const good = better === 'none' ? 'neutral' : (d > 0) === (better === 'up') ? 'up' : 'down';
  return `<span class="delta ${good}">${icon(d > 0 ? 'up' : 'down', 13)} ${d > 0 ? '+' : '−'}${Math.abs(d)}${unit} vs last week</span>`;
}
const GOAL_ICON = { practice_node: 'repeat', repeat_assessment: 'camera', metric_target: 'target', practice_preparation: 'book' };

export function renderWeekly(r) {
  const items = r.facts?.items ?? [], s = r.facts?.summary ?? {}, cur = s.current ?? {}, prev = s.previous;
  const f = (id) => items.find((x) => x.id === id);
  const headline = r.narrative?.headline?.text ?? `${cur.sessions ?? 0} recorded workout${cur.sessions === 1 ? '' : 's'}, ${cur.reps ?? 0} counted reps`;
  const goals = r.proposed_goals ?? [];
  return `<article class="report weekly">
    <header class="hero"><div class="kicker">${icon('calendar', 16)} Week of ${esc(dayRange(r.period_start, r.period_end))} · <span class="pill ${r.status === 'ready' ? 'good' : r.status === 'stale' ? 'warn' : 'neutral'}">${esc(r.status)}</span> · version ${r.version}</div>
      <h2 class="headline">${esc(headline)}</h2>${r.narrative?.headline ? `<div class="muted small">${icon('spark', 14)} Gemini, from the facts ${chips(r.narrative.headline.factIDs)}</div>` : ''}</header>
    ${f('synthetic') ? `<div class="banner warn">${icon('info', 16)} ${esc(f('synthetic').text)}</div>` : ''}${f('in_progress') ? `<div class="banner">${icon('clock', 16)} ${esc(f('in_progress').text)}</div>` : ''}
    <div class="stats">${tile('Workouts', cur.sessions ?? 0, delta(cur.sessions ?? 0, prev?.sessions))}${tile('Counted reps', cur.reps ?? 0, delta(cur.reps ?? 0, prev?.reps))}${tile('Training days', cur.days ?? 0, delta(cur.days ?? 0, prev?.days))}${tile('Median lowering', cur.medianLowering != null ? `${cur.medianLowering}<small>s</small>` : '–', cur.medianLowering != null && prev?.medianLowering != null ? delta(cur.medianLowering, prev.medianLowering, { unit: ' s', better: 'none' }) : `<span class="delta none">${cur.loweringN ?? 0} timed reps</span>`)}</div>
    <p class="coverage">${icon('info', 15)} ${esc(f('coverage')?.text ?? '')}</p>
    ${(r.narrative?.insights ?? []).length ? `<section><h3>${icon('spark', 18)} What stood out</h3><div class="insights">${r.narrative.insights.map((i, k) => `<div class="insight"><span class="n">${k + 1}</span><p>${esc(i.text)}</p>${chips(i.factIDs)}</div>`).join('')}</div></section>` : ''}
    <section class="two"><div class="box"><h3>${icon('target', 18)} Coaching</h3><p>${esc(f('coaching')?.text ?? '')}</p></div><div class="box"><h3>${icon('star', 18)} Milestones</h3><p>${esc(f('milestones')?.text ?? '')}</p></div></section>
    <section><h3>${icon('flag', 18)} Next week's quests</h3><p class="muted">Proposed from this week's facts. Edit the wording or targets, then accept. Nothing changes until you do.</p>
      <div class="quests" id="goalForm">${goals.map((g, i) => `<div class="quest" data-i="${i}"><div class="qh"><span class="qi">${icon(GOAL_ICON[g.kind] ?? 'flag', 20)}</span><input value="${esc(g.text)}" data-k="text" aria-label="Goal wording"></div>
        <div class="qf"><label>Target <input type="number" min="1" max="14" value="${g.target}" data-k="target"></label><label class="acc"><input type="checkbox" data-k="accept" checked> Accept</label><button class="ghost small" data-why="${esc(g.id)}">${icon('chat', 14)} Why this?</button></div>
        <div class="why" data-answer></div>${chips(g.factIDs)}</div>`).join('') || '<p class="muted">No goals proposed.</p>'}</div>
      ${goals.length ? '<div class="row"><button class="cta" id="acceptGoals">Accept selected quests</button><span class="muted" id="goalNote"></span></div>' : ''}</section>
    ${(r.research_refs ?? []).length ? `<section><h3>${icon('book', 18)} Research referenced</h3><div class="cards">${r.research_refs.map((x) => `<a href="#" class="ref" data-src="${esc(x.sourceId)}">${icon('doc', 18)} <span>${esc(x.title)}</span><span class="pill neutral">${esc(x.access === 'full_text' ? 'full text' : x.access)}</span></a>`).join('')}</div></section>` : ''}
    <section class="box quiet"><h3>${icon('bolt', 18)} Biometrics</h3><p class="muted">${esc((f('biometrics')?.text ?? 'No readings recorded').replace(/\.?\s*$/, '.'))}</p></section>
    <details class="facts"><summary>All calculated facts (${items.length})</summary><ul>${items.map((x) => `<li>${esc(x.text)} <span class="cite">${esc(x.id)}</span></li>`).join('')}</ul></details>
  </article>`;
}

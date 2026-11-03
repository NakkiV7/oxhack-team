// "Build my training path": a six-step guided survey, an editable review, Gemini generation with an honest loading state,
// and a preview of the generated path (with what changes and what carries over) before anything is saved.
import { emblemInline, icon } from './emblems.mjs';
import { renderMap } from './map.mjs';

const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const STEPS = ['goal', 'ability', 'check', 'equipment', 'routine', 'preferences', 'review'];
const LABELS = { goal: 'Goal', ability: 'Starting point', check: 'Camera check', equipment: 'Space', routine: 'Routine', preferences: 'Preferences', review: 'Review' };
const MINUTES = [{ v: 10, t: '10 min', s: 'A quick block' }, { v: 20, t: '20 min', s: 'A focused session' }, { v: 30, t: '30 min', s: 'Room for all sets' }, { v: 45, t: '45 min', s: 'Unhurried' }];
const PER_WEEK = [2, 3, 4, 5];
const FOCUS = [{ v: 'learn', t: 'Learn the movement', s: 'Get the pattern right first', i: 'book' }, { v: 'consistency', t: 'Build consistency', s: 'Turn up on planned days', i: 'calendar' }, { v: 'improve', t: 'Improve a skill I have', s: 'Refine control and tempo', i: 'target' }, { v: 'unsure', t: "I'm not sure", s: 'Balance all three', i: 'info' }];
const STYLE = [{ v: 'concise', t: 'Concise', s: 'Short and direct' }, { v: 'encouraging', t: 'Encouraging', s: 'Warm and upbeat' }, { v: 'explanatory', t: 'Explanatory', s: 'Tell me why' }];
const EQUIP_ICON = { wall: 'wall', 'raised surface': 'table', 'stable support': 'chair' };

export function openSurvey({ root, me, api, user, onFinished, onClose, startAt = null }) {
  const cat = Object.fromEntries(me.catalogue.map((e) => [e.id, e]));
  const ans = { ...(me.profile?.survey ?? {}) };
  const refining = !!me.programme;
  let step = startAt ?? (ans.completed ? 'review' : STEPS[Math.min(STEPS.length - 1, Math.max(0, STEPS.indexOf(ans.step ?? 'goal')))]);
  let saving = Promise.resolve(), fromReview = false; // fromReview: an Edit from the review returns there on Continue
  const save = (patch) => { Object.assign(ans, patch); saving = saving.then(() => api('/coach/survey', { timezone: Intl.DateTimeFormat().resolvedOptions().timeZone, survey: { ...patch, step } }).catch(() => {})); };
  root.hidden = false; document.body.classList.add('survey-open');

  const goal = () => (ans.goal === 'pushup' ? 'pushup' : 'squat');
  // Answers saved by the earlier survey used a band ("intermediate") and other style names. Map them onto today's options
  // so a refine starts from what the person already told us instead of showing "Not answered".
  if (!ans.abilityKey && ans.ability) ans.abilityKey = me.options.ability[goal()].find((o) => o.band === ans.ability)?.key ?? null;
  if (ans.coaching && !STYLE.some((x) => x.v === ans.coaching)) ans.coaching = { direct: 'concise', supportive: 'encouraging', gentle: 'encouraging', detailed: 'explanatory' }[ans.coaching] ?? null;
  const tile = (v, title, sub, { sel = false, art = '', multi = false } = {}) => `<button class="tile${sel ? ' sel' : ''}" data-v="${esc(v)}" aria-pressed="${sel}" ${multi ? 'data-multi="1"' : ''}>${art ? `<span class="art">${art}</span>` : ''}<span class="tt">${esc(title)}</span>${sub ? `<span class="ts">${esc(sub)}</span>` : ''}</button>`;
  const shell = (body, { title, lede, next = 'Continue', canNext = true, back = true } = {}) => {
    const i = STEPS.indexOf(step);
    root.innerHTML = `<div class="sv" role="dialog" aria-modal="true" aria-labelledby="svTitle">
      <div class="sv-top"><div class="sv-brand">${icon('route')} Build my training path</div><button class="ghost" id="svClose">${icon('close')} <span>Close</span></button></div>
      <ol class="sv-steps" aria-label="Progress">${STEPS.map((s, k) => `<li class="${k < i ? 'done' : k === i ? 'now' : ''}" ${k === i ? 'aria-current="step"' : ''}><span>${LABELS[s]}</span></li>`).join('')}</ol>
      <div class="sv-card"><h2 id="svTitle">${title}</h2>${lede ? `<p class="lede">${lede}</p>` : ''}${body}</div>
      <div class="sv-nav">${back && i > 0 ? `<button class="ghost" id="svBack">Back</button>` : '<span></span>'}<button class="cta" id="svNext" ${canNext ? '' : 'disabled'}>${fromReview && step !== 'review' ? 'Back to review' : next}</button></div></div>`;
    root.querySelector('#svClose').onclick = close;
    root.querySelector('#svBack')?.addEventListener('click', () => go(STEPS[i - 1]));
    root.querySelector('.sv-card h2').focus?.();
  };
  const go = (s) => { step = s; save({}); render(); };
  const close = () => { root.hidden = true; root.innerHTML = ''; document.body.classList.remove('survey-open'); onClose?.(); };
  const bindTiles = (key, { multi = false, after } = {}) => {
    for (const b of root.querySelectorAll('.tile[data-v]')) b.onclick = () => {
      if (multi) { const set = new Set(ans[key] ?? []); set.has(b.dataset.v) ? set.delete(b.dataset.v) : set.add(b.dataset.v); save({ [key]: [...set] }); }
      else save({ [key]: isNaN(+b.dataset.v) ? b.dataset.v : +b.dataset.v });
      after?.(); render();
    };
  };

  function render() {
    const g = goal();
    if (step === 'goal') {
      shell(`<div class="tiles two">${tile('squat', 'Squat path', 'Camera-assessed lowering tempo on the squat page', { sel: ans.goal === 'squat', art: emblemInline('squat', 64) })}${tile('pushup', 'Push-up path', 'Camera counts push-ups; path steps are logged', { sel: ans.goal === 'pushup', art: emblemInline('pushup', 64) })}</div>
        <p class="note">${icon('info', 16)} Further steps in each path are training content. Only squats are assessed by the camera inside this path today.</p>`,
        { title: 'What do you want to work towards?', lede: 'Pick one path. You can change it later.', canNext: !!ans.goal });
      bindTiles('goal', { after: () => { if (ans.abilityKey && !me.options.ability[goal()].some((a) => a.key === ans.abilityKey)) save({ abilityKey: null }); } });
    } else if (step === 'ability') {
      const opts = me.options.ability[g];
      shell(`<div class="tiles list">${opts.map((o) => tile(o.key, o.label, { new: 'We start at the foundation', control: 'We focus on control and tempo', comfortable: 'We start at the full movement', unsure: "That's fine: we start safe and a camera check can move you on", notTried: 'We start with supported variations', first: 'We build towards it step by step', few: 'We start at the full movement' }[o.key] ?? '', { sel: ans.abilityKey === o.key })).join('')}</div>
        <p class="note">${icon('info', 16)} This places your starting step. It is not a strength score.</p>`,
        { title: g === 'pushup' ? 'Where are you with push-ups?' : 'Where are you with squats?', lede: 'Choose the closest. "Not sure" is a good answer.', canNext: !!ans.abilityKey });
      bindTiles('abilityKey', { after: () => save({ ability: opts.find((o) => o.key === ans.abilityKey)?.band }) });
    } else if (step === 'check') {
      const c = me.check && me.check.exercise === g ? me.check : null;
      const supported = g === 'squat';
      shell(`${supported ? `<div class="tiles two">${tile('camera', 'Try a quick camera check', 'Three squats at your own pace, about a minute', { sel: ans.check === 'camera', art: icon('camera', 40) })}${tile('answers', 'Continue with my answers', 'Your path starts from what you told us', { sel: ans.check === 'answers', art: icon('chat', 40) })}</div>` :
        `<div class="tiles one">${tile('answers', 'Continue with my answers', 'Your path starts from what you told us', { sel: true, art: icon('chat', 40) })}</div><p class="note">${icon('info', 16)} The push-up camera counts reps on its own page but is not linked to path placement yet, so placement uses your answers.</p>`}
        ${supported && ans.check === 'camera' ? `<div class="setup"><h3>Before you start</h3><ul><li>${icon('camera', 16)} Laptop at hip height, side-on to you, 2 to 3 metres away.</li><li>${icon('target', 16)} Hips, knees and feet in frame.</li><li>${icon('repeat', 16)} Three squats at your normal pace. Stop any time.</li></ul>
          ${c ? `<div class="checked">${icon('check', 18)} Camera check recorded: <b>${c.validReps}</b> valid squats${c.medianLowering ? `, median lowering ${c.medianLowering.toFixed(2)} s` : ''}. ${c.validReps >= 3 ? 'Your path can start at squats if you choose.' : 'Fewer than three valid squats, so placement uses your answers.'}</div>` : ''}
          <a class="cta alt" id="svCam" href="/?check=squat&user=${encodeURIComponent(user)}">${icon('camera', 18)} ${c ? 'Run the check again' : 'Open camera check'}</a></div>` : ''}`,
        { title: 'Want a quick camera check?', lede: 'A short supported check can personalise where you start. It is optional; nobody is asked to attempt a harder movement than they chose.', canNext: !supported || !!ans.check });
      if (!supported) save({ check: 'answers' });
      bindTiles('check');
      root.querySelector('#svCam')?.addEventListener('click', () => save({ step: 'check' }));
    } else if (step === 'equipment') {
      const has = new Set(ans.equipment ?? []), none = ans.equipmentAnswered && !has.size;
      shell(`<div class="tiles grid3">${me.options.equipment.map((o) => tile(o.key, o.label, o.hint, { sel: has.has(o.key), art: icon(EQUIP_ICON[o.key] ?? 'info', 36), multi: true })).join('')}${tile('__none', 'None of these', 'Floor space only', { sel: none, art: icon('none', 36) })}</div>`,
        { title: 'What do you have nearby?', lede: 'Select all that apply. Steps that need something you don\'t have are left out.', canNext: !!ans.equipmentAnswered });
      for (const b of root.querySelectorAll('.tile[data-v]')) b.onclick = () => { if (b.dataset.v === '__none') save({ equipment: [], equipmentAnswered: true }); else { has.has(b.dataset.v) ? has.delete(b.dataset.v) : has.add(b.dataset.v); save({ equipment: [...has], equipmentAnswered: true }); } render(); };
    } else if (step === 'routine') {
      shell(`<h3 class="q">Time per session</h3><div class="tiles grid4">${MINUTES.map((m) => tile(m.v, m.t, m.s, { sel: ans.minutes === m.v, art: icon('clock', 30) })).join('')}</div>
        <h3 class="q">Sessions per week</h3><div class="tiles grid4 wk">${PER_WEEK.map((d) => `<button class="tile${ans.daysPerWeek === d ? ' sel' : ''}" data-k="daysPerWeek" data-v="${d}" aria-pressed="${ans.daysPerWeek === d}"><span class="big">${d}</span><span class="ts">per week</span></button>`).join('')}</div>`,
        { title: 'How does training fit your week?', lede: 'This sets how much each step asks of you.', canNext: !!ans.minutes && !!ans.daysPerWeek });
      for (const b of root.querySelectorAll('.tile[data-v]')) b.onclick = () => { save({ [b.dataset.k ?? 'minutes']: +b.dataset.v }); render(); };
    } else if (step === 'preferences') {
      const avoid = new Set(ans.avoid ?? []);
      shell(`<h3 class="q">Main focus</h3><div class="tiles grid4">${FOCUS.map((f) => `<button class="tile${ans.focus === f.v ? ' sel' : ''}" data-k="focus" data-v="${f.v}" aria-pressed="${ans.focus === f.v}"><span class="art">${icon(f.i, 30)}</span><span class="tt">${f.t}</span><span class="ts">${f.s}</span></button>`).join('')}</div>
        <h3 class="q">Coaching style</h3><div class="tiles grid3">${STYLE.map((s) => `<button class="tile${ans.coaching === s.v ? ' sel' : ''}" data-k="coaching" data-v="${s.v}" aria-pressed="${ans.coaching === s.v}"><span class="tt">${s.t}</span><span class="ts">${s.s}</span></button>`).join('')}</div>
        <h3 class="q">Any movements to leave out? <span class="muted">Optional</span></h3><div class="chips">${me.options.avoidable[g].map((id) => `<button class="chip${avoid.has(id) ? ' sel' : ''}" data-avoid="${id}" aria-pressed="${avoid.has(id)}">${emblemInline(id, 22)} ${esc(cat[id].name)}</button>`).join('')}</div>
        <p class="note">${icon('info', 16)} Leaving a movement out simply removes it from your path. We don't ask why, and we don't make any medical judgement.</p>`,
        { title: 'How would you like to train?', lede: 'Two quick choices, and anything you\'d rather skip.', canNext: !!ans.focus && !!ans.coaching });
      for (const b of root.querySelectorAll('.tile[data-k]')) b.onclick = () => { save({ [b.dataset.k]: b.dataset.v }); render(); };
      for (const b of root.querySelectorAll('[data-avoid]')) b.onclick = () => { avoid.has(b.dataset.avoid) ? avoid.delete(b.dataset.avoid) : avoid.add(b.dataset.avoid); save({ avoid: [...avoid] }); render(); };
    } else if (step === 'review') {
      const ab = me.options.ability[g].find((a) => a.key === ans.abilityKey);
      const rows = [
        ['goal', 'Goal', g === 'pushup' ? 'Push-up path' : 'Squat path'],
        ['ability', 'Starting point', ab?.label ?? 'Not answered'],
        ['check', 'Placement', ans.check === 'camera' && me.check?.exercise === g && me.check.validReps >= 3 ? `Camera check: ${me.check.validReps} valid squats` : 'From my answers'],
        ['equipment', 'Nearby', (ans.equipment ?? []).length ? ans.equipment.join(', ') : 'Floor space only'],
        ['routine', 'Routine', `${ans.minutes ?? 20} min, ${ans.daysPerWeek ?? 3} sessions per week`],
        ['preferences', 'Focus and style', `${FOCUS.find((f) => f.v === ans.focus)?.t ?? 'Focus not answered'}, ${STYLE.find((s) => s.v === ans.coaching)?.t.toLowerCase() ?? 'style not answered'}${(ans.avoid ?? []).length ? `; leave out ${ans.avoid.map((id) => cat[id]?.name.toLowerCase()).join(', ')}` : ''}`],
      ];
      shell(`<dl class="review">${rows.map(([s, k, v]) => `<div><dt>${k}</dt><dd>${esc(v)}</dd><button class="link" data-edit="${s}">Edit</button></div>`).join('')}</dl>
        <p class="note">${icon('spark', 16)} Gemini picks your steps, start, practice targets and optional branch from the Spottr exercise catalogue. The app checks every link, target and capability before you see it.</p>`,
        { title: "Here's what we'll use to build your path", lede: refining ? 'Your earned progress carries over to the new version.' : '', next: refining ? 'Build a new version' : 'Build my path' });
      fromReview = false;
      for (const b of root.querySelectorAll('[data-edit]')) b.onclick = () => { fromReview = true; go(b.dataset.edit); };
    }
    const next = root.querySelector('#svNext');
    if (next && step !== 'review') next.onclick = () => go(fromReview && (step !== 'goal' || ans.abilityKey) ? 'review' : STEPS[STEPS.indexOf(step) + 1]);
    if (next && step === 'review') next.onclick = () => { save({ completed: true }); generate(); };
  }

  async function generate() {
    root.innerHTML = `<div class="sv"><div class="sv-gen" role="status" aria-live="polite"><div class="orbit" aria-hidden="true"><span></span><span></span><span></span></div><h2>Building your path…</h2><p class="lede">Gemini is choosing your steps from the catalogue. Every link, target and capability is then checked by the app.</p></div></div>`;
    await saving;
    let res;
    try { res = await api('/coach/programme/preview', {}); }
    catch (e) { root.innerHTML = `<div class="sv"><div class="sv-gen"><h2>That didn't work</h2><p class="lede">${esc(e.message)}</p><div class="sv-nav"><button class="ghost" id="svBack">Back to answers</button><button class="cta" id="svRetry">Try again</button></div></div></div>`; root.querySelector('#svRetry').onclick = generate; root.querySelector('#svBack').onclick = () => go('review'); return; }
    preview(res);
  }

  function preview(res) {
    const { graph, rationale, provenance, diff } = res, nameOf = (id) => cat[graph.nodes.find((n) => n.id === id)?.exerciseId ?? id]?.name ?? id;
    const rows = Object.fromEntries(graph.nodes.map((n) => [n.id, { availability: n.notRequired ? 'not_required' : n.id === graph.start ? 'current' : (n.prerequisites ?? []).length ? 'locked' : 'available', verification: diff.carried.find((c) => c.nodeId === n.id)?.verification ?? 'none', practice_count: diff.carried.find((c) => c.nodeId === n.id)?.practice ?? 0 }]));
    const changes = refining ? `<div class="diff"><h3>${icon('route', 18)} What changes</h3><ul>
        ${diff.start.from !== diff.start.to ? `<li>Start moves from <b>${esc(nameOf(diff.start.from))}</b> to <b>${esc(nameOf(diff.start.to))}</b></li>` : `<li>Start stays at <b>${esc(nameOf(diff.start.to))}</b></li>`}
        ${diff.added.length ? `<li>New steps: ${diff.added.map((id) => `<b>${esc(nameOf(id))}</b>`).join(', ')}</li>` : ''}
        ${diff.removed.length ? `<li>Leaving this version: ${diff.removed.map((id) => `<b>${esc(cat[id]?.name ?? id)}</b>`).join(', ')}</li>` : ''}
        ${!diff.added.length && !diff.removed.length ? '<li>Same steps; wording, targets or route may differ</li>' : ''}</ul>
        ${diff.carried.length ? `<h3>${icon('check', 18)} Progress carried over</h3><ul>${diff.carried.map((c) => `<li><b>${esc(nameOf(c.nodeId))}</b>: ${c.verification !== 'none' ? c.verification.replace('_', ' ') : `${c.practice} practice day${c.practice === 1 ? '' : 's'}`}, ${c.xp} XP</li>`).join('')}</ul>` : ''}
        ${diff.archived.length ? `<h3>${icon('book', 18)} Kept in your history</h3><ul>${diff.archived.map((c) => `<li><b>${esc(cat[c.nodeId]?.name ?? c.nodeId)}</b> stays in your record and level; it is not part of the new path</li>`).join('')}</ul>` : ''}</div>` : '';
    root.innerHTML = `<div class="sv"><div class="sv-top"><div class="sv-brand">${icon('route')} ${refining ? 'Your new path, before saving' : 'Your path'}</div><button class="ghost" id="svClose">${icon('close')} <span>Close</span></button></div>
      <div class="pv">
        <div class="pv-map" id="pvMap"></div>
        <div class="pv-side">
          <div class="prov ${provenance === 'gemini' ? 'gem' : 'fb'}">${provenance === 'gemini' ? `${icon('spark', 16)} Personalised by Gemini, validated by the app` : `${icon('info', 16)} Built from the catalogue: Gemini's plan didn't pass validation or wasn't available`}</div>
          <h2>${esc(rationale.startReason ?? '')}</h2>
          <p>${esc(rationale.text ?? '')}</p>
          ${rationale.emphasis ? `<p class="emph">${icon('target', 16)} ${esc(rationale.emphasis)}</p>` : ''}
          <p class="muted">${rationale.placementSource === 'camera-supported' ? 'Placement: camera-supported.' : 'Placement: from your answers.'}</p>
          ${changes}
          <div class="sv-nav"><button class="ghost" id="svAdjust">Adjust answers</button><button class="cta" id="svAccept">${refining ? `Save as version ${(res.currentVersion ?? 0) + 1}` : 'Start my path'}</button></div>
        </div></div></div>`;
    root.querySelector('#svClose').onclick = close;
    root.querySelector('#svAdjust').onclick = () => go('review');
    const m = root.querySelector('#pvMap');
    renderMap(m, { graph, rows, catalogue: cat, capabilityOf: (id) => cat[id]?.capability, practiceComplete: me.practiceComplete, selected: graph.start, orientation: m.clientWidth < 560 ? 'v' : 'h', reveal: true, onSelect: () => {} });
    root.querySelector('#svAccept').onclick = async (ev) => {
      ev.target.disabled = true; ev.target.textContent = 'Saving…';
      try { const r = await api('/coach/programme/accept', { graph, rationale, provenance }); close(); onFinished?.(r.programme, { reveal: true }); }
      catch (e) { ev.target.disabled = false; ev.target.textContent = 'Try saving again'; alert(e.message); }
    };
  }

  render();
}

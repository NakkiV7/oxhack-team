// The skill map: a deterministic layout of the programme graph and its SVG rendering. Positions come only from the graph
// (main chain in level order, supporting steps beside the step they feed), so progress updates never move a node.
// Edges are exactly the programme's prerequisite links plus the catalogue support link of the optional branch.
import { emblem, icon } from './emblems.mjs';

export const SHAPE_R = { goal: 40, milestone: 36, standard: 30, optional: 24 };

// Display status from a progress row. Capability is reported separately and never mixed into status.
export function nodeStatus(node, row, { capability, practiceComplete = 3 } = {}) {
  const verified = row && row.verification && row.verification !== 'none';
  const practised = !verified && capability !== 'assessable' && (row?.practice_count ?? 0) >= practiceComplete;
  if (verified) return { key: 'verified', label: row.verification === 'consistent' ? 'Verified on two days' : 'AI-verified', done: true };
  if (practised) return { key: 'practised', label: 'Practice complete', done: true };
  if (row?.availability === 'not_required') return { key: 'skipped', label: 'Not required for your start', done: true };
  if (row?.availability === 'current') return { key: 'current', label: 'Current step', done: false };
  if (row?.availability === 'locked') return { key: 'locked', label: 'Locked', done: false };
  return { key: 'available', label: 'Available', done: false };
}
export const roleOf = (node, graph, capability) => (node.id === graph.goalNode ? 'goal' : node.optional ? 'optional' : capability !== 'practice-only' ? 'milestone' : 'standard');

// Layout. orientation 'h': start on the left, goal on the right; 'v': start at the top, goal at the bottom.
export function layout(graph, catalogue, orientation = 'h') {
  const fam = catalogue[graph.goal]?.family ?? catalogue[graph.nodes[0]?.exerciseId]?.family;
  const chain = graph.nodes.filter((n) => !n.optional && catalogue[n.exerciseId]?.family === fam).sort((a, b) => catalogue[a.exerciseId].level - catalogue[b.exerciseId].level).map((n) => n.id);
  const pos = {}; chain.forEach((id, i) => { pos[id] = { axis: i, lane: 0 }; });
  const others = graph.nodes.filter((n) => !(n.id in pos));
  const used = new Set(chain.map((id) => `${pos[id].axis}:0`));
  for (const n of others) {
    const anchor = n.supports ?? graph.nodes.find((x) => (x.prerequisites ?? []).includes(n.id))?.id;
    const a = pos[anchor]?.axis ?? 0, axis = n.optional ? a : Math.max(0, a - 0.5);
    let lane = n.optional ? 1 : -1;
    while (used.has(`${axis}:${lane}`)) lane += Math.sign(lane);
    used.add(`${axis}:${lane}`); pos[n.id] = { axis, lane };
  }
  const STEP = orientation === 'h' ? 168 : 156, LANE = orientation === 'h' ? 162 : 128, PAD = orientation === 'h' ? 96 : 84;
  const lanes = Object.values(pos).map((p) => p.lane), minLane = Math.min(0, ...lanes), maxLane = Math.max(0, ...lanes);
  const maxAxis = Math.max(0, ...Object.values(pos).map((p) => p.axis));
  const out = {};
  for (const [id, p] of Object.entries(pos)) {
    const wave = p.lane === 0 ? (Math.round(p.axis) % 2 ? 16 : -16) : 0; // a gentle constellation curve on the main chain
    if (orientation === 'h') out[id] = { ...p, x: PAD + p.axis * STEP, y: PAD + 10 + (maxLane - p.lane) * LANE + wave };
    else out[id] = { ...p, x: PAD + 20 + (p.lane - minLane) * LANE + wave, y: PAD + p.axis * STEP };
  }
  const width = orientation === 'h' ? PAD * 2 + maxAxis * STEP : PAD * 2 + 40 + (maxLane - minLane) * LANE;
  const height = orientation === 'h' ? PAD * 2 + 50 + (maxLane - minLane) * LANE : PAD * 2 + 40 + maxAxis * STEP;
  const order = Object.keys(out).sort((a, b) => out[a].axis - out[b].axis || out[a].lane - out[b].lane);
  return { pos: out, width, height, order, chain, orientation };
}

export function edgesOf(graph) {
  const e = [];
  for (const n of graph.nodes) {
    for (const p of n.prerequisites ?? []) e.push({ from: p, to: n.id, kind: 'prereq' });
    if (n.optional && n.supports) e.push({ from: n.id, to: n.supports, kind: 'support' });
  }
  return e;
}

const shapePath = (role, R) => {
  if (role === 'goal') return `<path class="shape" d="M0 ${-R} L${0.9 * R} ${-0.55 * R} L${0.84 * R} ${0.32 * R} Q${0.56 * R} ${0.86 * R} 0 ${1.06 * R} Q${-0.56 * R} ${0.86 * R} ${-0.84 * R} ${0.32 * R} L${-0.9 * R} ${-0.55 * R} Z"/>`;
  if (role === 'milestone') { const p = [0, 1, 2, 3, 4, 5].map((i) => { const a = (Math.PI / 3) * i - Math.PI / 2; return `${(R * Math.cos(a)).toFixed(1)},${(R * Math.sin(a)).toFixed(1)}`; }).join(' '); return `<polygon class="shape" points="${p}"/>`; }
  return `<circle class="shape" r="${R}"/>`;
};
const wrap = (s, max = 15) => { if (s.length <= max) return [s]; const mid = s.length / 2; let best = -1; for (let i = 0; i < s.length; i++) if (s[i] === ' ' && (best < 0 || Math.abs(i - mid) < Math.abs(best - mid))) best = i; return best < 0 ? [s] : [s.slice(0, best), s.slice(best + 1)]; };
const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

// Deterministic background stars (same sky every time).
function stars(w, h) { let s = 7, out = ''; const r = () => { s = (s * 16807) % 2147483647; return s / 2147483647; }; for (let i = 0; i < 46; i++) out += `<circle cx="${(r() * w).toFixed(0)}" cy="${(r() * h).toFixed(0)}" r="${(0.5 + r() * 1.1).toFixed(1)}" opacity="${(0.15 + r() * 0.35).toFixed(2)}"/>`; return out; }

// Render into `el`. opts: { graph, rows (by node id), catalogue (by id), capabilityOf, practiceComplete, selected, orientation,
// reveal (animate in), unlocked (Set of node ids that just became available or done), onSelect(id) }.
export function renderMap(el, opts) {
  const { graph, rows, catalogue, capabilityOf, practiceComplete, selected, orientation, reveal, unlocked = new Set(), onSelect } = opts;
  const L = layout(graph, catalogue, orientation), byId = Object.fromEntries(graph.nodes.map((n) => [n.id, n]));
  const status = Object.fromEntries(graph.nodes.map((n) => [n.id, nodeStatus(n, rows[n.id], { capability: capabilityOf(n.exerciseId), practiceComplete })]));
  const route = new Set((graph.route ?? []).flatMap((id, i, r) => (i ? [`${r[i - 1]}>${id}`] : [])));
  const current = graph.nodes.find((n) => status[n.id].key === 'current')?.id ?? graph.start;
  const edges = edgesOf(graph).map((e) => {
    const a = L.pos[e.from], b = L.pos[e.to]; if (!a || !b) return '';
    const fromDone = status[e.from].done, toDone = status[e.to].done, toOpen = ['current', 'available'].includes(status[e.to].key);
    const kind = e.kind === 'support' ? 'optional' : fromDone && toDone ? 'achieved' : fromDone && toOpen ? 'open' : route.has(`${e.from}>${e.to}`) ? 'route' : 'future';
    const d = orientation === 'h' ? `M${a.x} ${a.y} C${(a.x + b.x) / 2} ${a.y} ${(a.x + b.x) / 2} ${b.y} ${b.x} ${b.y}` : `M${a.x} ${a.y} C${a.x} ${(a.y + b.y) / 2} ${b.x} ${(a.y + b.y) / 2} ${b.x} ${b.y}`;
    const lit = unlocked.has(e.to) ? ' lit' : '';
    return `<path class="edge ${kind}${lit}" d="${d}" pathLength="1" style="--i:${a.axis}"/>`;
  }).join('');
  const nodes = L.order.map((id) => {
    const n = byId[id], p = L.pos[id], cap = capabilityOf(n.exerciseId), role = roleOf(n, graph, cap), R = SHAPE_R[role], st = status[id], row = rows[id];
    const name = catalogue[n.exerciseId]?.name ?? id, lines = wrap(name);
    // Labels sit below a node, except for side branches above a horizontal main line: there the link leaves downwards, so the
    // label goes on top where no edge crosses it.
    const above = L.orientation === 'h' && p.lane > 0, subY = above ? -R - 14 : R + (role === 'goal' ? 26 : 22) + lines.length * 15 + 2;
    const labelY = above ? subY - 17 - (lines.length - 1) * 15 : R + (role === 'goal' ? 26 : 22);
    const practiceRing = cap !== 'assessable' && !st.done && (row?.practice_count ?? 0) > 0 ? `<circle class="ring" r="${R + 7}" pathLength="1" stroke-dasharray="${Math.min(1, row.practice_count / practiceComplete)} 1" transform="rotate(-90)"/>` : '';
    const badge = { verified: 'star', practised: 'check', locked: 'lock', skipped: 'skip' }[st.key];
    const capIcon = cap === 'assessable' ? 'camera' : cap === 'counting' ? 'count' : null;
    const aria = `${name}. ${st.label}. ${cap === 'assessable' ? 'Camera assessment' : cap === 'counting' ? 'Camera rep counting on the push-up page' : 'Practice log'}.${role === 'goal' ? ' Path goal.' : ''}${role === 'optional' ? ' Optional branch.' : ''}${id === graph.start ? ' Starting point.' : ''}`;
    return `<g class="node st-${st.key} role-${role}${id === selected ? ' selected' : ''}${unlocked.has(id) ? ' unlock' : ''}" data-id="${esc(id)}" transform="translate(${p.x} ${p.y})" style="--i:${p.axis}" role="button" tabindex="${id === (selected ?? current) ? 0 : -1}" aria-label="${esc(aria)}" aria-pressed="${id === selected}">
      ${id === current ? `<circle class="aura" r="${R * 2.4}"/>` : ''}
      <circle class="hit" r="${R + 14}"/>
      ${practiceRing}
      <g class="body">${shapePath(role, R)}${shapePath(role, R - 5).replace('class="shape"', 'class="inner"')}<g class="fig">${emblem(n.exerciseId, { size: R * 1.25 })}</g></g>
      ${badge ? `<g class="badge b-${badge}" transform="translate(${(R * 0.74).toFixed(1)} ${(-R * 0.74).toFixed(1)})"><circle r="10"/><g transform="translate(-7 -7) scale(.58)">${icon(badge, 24).replace(/^<svg[^>]*>|<\/svg>$/g, '')}</g></g>` : ''}
      ${capIcon ? `<g class="cap" transform="translate(${(-R * 0.76).toFixed(1)} ${(R * 0.7).toFixed(1)})"><circle r="9.5"/><g transform="translate(-6.5 -6.5) scale(.54)">${icon(capIcon, 24).replace(/^<svg[^>]*>|<\/svg>$/g, '')}</g></g>` : ''}
      <text class="label" y="${labelY}">${lines.map((t, i) => `<tspan x="0" dy="${i ? 15 : 0}">${esc(t)}</tspan>`).join('')}</text>
      <text class="sub" y="${subY}">${esc(role === 'goal' ? 'Goal · ' + st.label : role === 'optional' ? 'Optional · ' + st.label : st.label)}</text>
    </g>`;
  }).join('');
  el.innerHTML = `<svg class="map ${reveal ? 'reveal' : ''}" style="--w:${L.width}px;--h:${L.height}px" viewBox="0 0 ${L.width} ${L.height}" preserveAspectRatio="xMidYMid meet" role="group" aria-label="Training path map. Arrow keys move between steps, Home jumps to your current step, End to the goal, Enter opens a step.">
    <defs>
      <pattern id="grid" width="32" height="32" patternUnits="userSpaceOnUse"><path d="M32 0H0V32" fill="none" stroke="currentColor" stroke-width=".6" opacity=".09"/></pattern>
      <radialGradient id="auraG"><stop offset="0" stop-color="var(--cyan)" stop-opacity=".34"/><stop offset=".55" stop-color="var(--cyan)" stop-opacity=".08"/><stop offset="1" stop-color="var(--cyan)" stop-opacity="0"/></radialGradient>
    </defs>
    <rect class="bg" width="${L.width}" height="${L.height}" fill="url(#grid)"/><g class="sky">${stars(L.width, L.height)}</g>
    <g class="edges">${edges}</g><g class="nodes">${nodes}</g></svg>`;
  const svg = el.querySelector('svg');
  const nodesEls = [...svg.querySelectorAll('.node')];
  for (const g of nodesEls) {
    g.addEventListener('click', () => onSelect(g.dataset.id));
    g.addEventListener('keydown', (ev) => {
      if (ev.key === 'Enter' || ev.key === ' ') { ev.preventDefault(); onSelect(g.dataset.id); return; }
      const dir = { ArrowRight: [1, 0], ArrowLeft: [-1, 0], ArrowDown: [0, 1], ArrowUp: [0, -1] }[ev.key];
      if (ev.key === 'Home') { ev.preventDefault(); focusNode(current); return; }
      if (ev.key === 'End') { ev.preventDefault(); focusNode(graph.goalNode); return; }
      if (!dir) return;
      ev.preventDefault();
      const me = L.pos[g.dataset.id];
      const cands = L.order.filter((id) => id !== g.dataset.id).map((id) => { const p = L.pos[id], dx = p.x - me.x, dy = p.y - me.y, along = dx * dir[0] + dy * dir[1]; return { id, along, score: along > 0 ? along + 2 * Math.abs(dx * dir[1] + dy * dir[0]) : Infinity }; }).filter((c) => c.along > 0).sort((a, b) => a.score - b.score);
      if (cands[0]) focusNode(cands[0].id);
    });
  }
  function focusNode(id) { for (const g of nodesEls) g.tabIndex = g.dataset.id === id ? 0 : -1; const t = nodesEls.find((g) => g.dataset.id === id); t?.focus(); return t; }
  return { layout: L, status, current, focusNode, nodeEl: (id) => nodesEls.find((g) => g.dataset.id === id) };
}

// The same graph as an ordered list, for screen readers and anyone who prefers text.
export function renderOutline(el, { graph, rows, catalogue, capabilityOf, practiceComplete, onSelect, orientation = 'h' }) {
  const L = layout(graph, catalogue, orientation);
  el.innerHTML = `<ol class="outline">${L.order.map((id) => {
    const n = graph.nodes.find((x) => x.id === id), cap = capabilityOf(n.exerciseId), st = nodeStatus(n, rows[id], { capability: cap, practiceComplete });
    const pre = (n.prerequisites ?? []).map((p) => catalogue[graph.nodes.find((x) => x.id === p)?.exerciseId]?.name ?? p);
    return `<li><button data-id="${esc(id)}"><b>${esc(catalogue[n.exerciseId]?.name ?? id)}</b> <span>${esc(st.label)}${n.optional ? ' · optional' : ''}${id === graph.goalNode ? ' · goal' : ''} · ${cap === 'assessable' ? 'camera assessment' : cap === 'counting' ? 'camera rep counting' : 'practice log'}${pre.length ? ` · after ${esc(pre.join(', '))}` : ''}</span></button></li>`;
  }).join('')}</ol>`;
  for (const b of el.querySelectorAll('button')) b.onclick = () => onSelect(b.dataset.id);
}

// Seeds the demo account with clearly labelled synthetic history so the weekly review has two weeks to compare.
// Synthetic sets carry client 'demo-seed' and a note; reports flag them and they never enter the HRT evaluation.
//   node coach-demo-seed.mjs [--server http://localhost:3002] [--user demo]
const args = process.argv.slice(2), opt = (k, d) => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : d; };
const server = opt('--server', 'http://localhost:3002'), user = opt('--user', 'demo');
const api = async (path, body) => { const r = await fetch(`${server}${path}${path.includes('?') ? '&' : '?'}user=${encodeURIComponent(user)}`, body ? { method: 'POST', body: JSON.stringify(body) } : {}); const j = await r.json(); if (!r.ok) throw new Error(j.error ?? r.statusText); return j; };
const me = await api('/coach/me');
if ((await (await fetch(`${server}/coach/workouts?user=${user}`)).json()).some((w) => (w.note ?? '').startsWith('synthetic sample history'))) { console.log('demo history already seeded'); process.exit(0); }
await api('/coach/profile', { timezone: 'Europe/London', survey: { goal: 'squat', ability: 'intermediate', equipment: ['wall', 'raised surface'], minutes: 20, daysPerWeek: 3, coaching: 'encouraging', limitations: [] } });
if (!me.programme) await api('/coach/programme', {});
// Six synthetic sets over the last twelve days: lowering drifts from quick to controlled, with one short set.
let seed = 7; const rnd = () => { seed = (seed * 16807) % 2147483647; return seed / 2147483647; };
const days = [-12, -10, -8, -5, -3, -1], lengths = [12, 14, 10, 16, 15, 18];
for (const [i, d] of days.entries()) {
  const workoutId = crypto.randomUUID(), start = new Date(Date.now() + d * 86400e3); start.setHours(18, 0, 0, 0);
  const t0 = start.getTime(), reps = [];
  for (let n = 1; n <= lengths[i]; n++) { const down = Math.round((0.9 + 0.08 * i + 0.1 * (rnd() - 0.5)) * 100) / 100, up = Math.round((0.8 + 0.1 * (rnd() - 0.5)) * 100) / 100; reps.push({ at: t0 + n * 4000, n, counted: true, good: n % 5 !== 0, secs: Math.round((down + up) * 10) / 10, downSecs: down, upSecs: up, travel: 0.5, depth: 0.05, lean: 30, issue: null, faults: n % 5 ? [] : ['Deeper: hips to knee height'] }); }
  const post = (body) => fetch(`${server}/telemetry`, { method: 'POST', body: JSON.stringify({ workoutId, exercise: 'squat', ...body }) });
  await post({ start: { variation: 'standard', source: 'camera', client: 'demo-seed', startedAt: start.toISOString(), note: `synthetic sample history (demo account), day ${d}` }, reps });
  await post({ end: { endedAt: new Date(t0 + (lengths[i] + 1) * 4000).toISOString() } });
  console.log(`seeded synthetic set ${i + 1}: ${lengths[i]} reps on day ${d}`);
}
console.log('demo account ready; synthetic history is labelled in every report');

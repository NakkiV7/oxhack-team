import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import { RepCounter } from '../pushup.mjs';
import { parseSync } from '../sync.mjs';

const page = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
const section = (from, to) => page.slice(page.indexOf(from), page.indexOf(to, page.indexOf(from)));

test('changing an unfinished replay into camera input starts with no earlier reps or time', () => {
  const counter = new RepCounter('standard');
  counter.reps.push({ counted: true, good: true, minElbow: 85, minLine: 175, secs: 2 });
  const state = vm.createContext({ counter, ruleFor: () => null, updateRuleUI() {}, savedProfile: null, hidePanel() {}, clockReset() { state.resetTime = true; }, $: () => ({ innerHTML: '' }), client: { start: () => 'new-camera' } });
  vm.runInContext("let workoutEnded=false,syncInfo=null,finishedUpload=null;" + section('function newWorkout(', 'function askEnd()'), state);
  vm.runInContext("newWorkout('camera', 'owner-a')", state);
  assert.equal(counter.reps.length, 0);
  assert.equal(state.resetTime, true);
});

test('personal thresholds require an explicit saved choice', () => {
  const state = vm.createContext({ localStorage: { getItem: () => null } });
  vm.runInContext(section('const RULE_KEY =', 'function updateRuleUI()'), state);
  assert.equal(vm.runInContext('getMode()', state), 'default');
});

test('saved mock profile keeps its demo label when current history is real', () => {
  const state = vm.createContext({ counter: { reps: [], personal: null }, $: () => ({ disabled: false }), ruleFor: () => ({ warnElbow: 74, minLine: 169 }) });
  vm.runInContext("let running=false,paused=false,workoutEnded=false; const savedProfile={mockShare:0,profile:{mockShare:1}};" + section('function ruleInfo()', '// "My profile":'), state);
  assert.match(vm.runInContext('ruleInfo().text', state), /demo data/);
});

test('ending a camera workout offers an upload action without sending it', () => {
  let uploads = 0;
  const nodes = new Map();
  const $ = id => { if (!nodes.has(id)) nodes.set(id, { innerHTML: '', hidden: false, textContent: '' }); return nodes.get(id); };
  const state = vm.createContext({ $, panel: $('panel'), counter: { variation: 'standard', reps: [{ counted: true, good: true, minElbow: 85, minLine: 175, secs: 2 }] },
    clockPause() {}, stopAll() {}, showClock() {}, summaryStats: () => ({ timeMs: 2000, reps: 1, good: 1 }), fmtTime: String, hidePanel() {},
    pendingList: () => [], VARIATIONS: { standard: { label: 'Standard push-up' } }, runSync: () => { uploads++; }, setSync() {},
    client: { finish: () => ({ workoutId: 'one' }), upload: () => { uploads++; } } });
  vm.runInContext("let cameraWorkout=true,workoutEnded=false,finishedUpload=null,ruleUsed='default';" + section('function saveWorkout(st)', 'function endWorkout()') + section('function endWorkout()', "document.addEventListener('keydown'"), state);
  vm.runInContext('endWorkout()', state);
  assert.equal(uploads, 0);
});

const T0 = Date.UTC(2026, 9, 24, 12);
const ids = ['00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000002'];
const rep = { counted: true, good: true, minElbow: 85, minLine: 175, secs: 2, issue: null };
const context = (userId = 'owner-a') => ({ userId, token: 'ephemeral-test-token', cloudAvailable: true });
const storage = () => {
  const values = new Map();
  return { values, getItem: key => values.get(key) ?? null, setItem: (key, value) => values.set(key, value) };
};
async function fixture(options = {}) {
  const { createWorkoutClient } = await import('../client-workout.mjs');
  const store = options.storage ?? storage();
  let time = T0, id = 0;
  const posts = [], statuses = [];
  const client = createWorkoutClient({ storage: store, context: async () => context(), send: async body => { posts.push(body); return { saved: body.reps.length }; }, status: info => statuses.push(info), now: () => time, uuid: () => ids[id++], ...options });
  return { client, store, posts, statuses, at: value => { time = value; } };
}
function ended(f, source = 'camera', userId = 'owner-a') {
  f.client.start({ source, variation: 'standard', userId });
  f.at(T0 + 2000); f.client.observe(rep);
  f.at(T0 + 10000);
  return f.client.finish(2000);
}

test('workout source is frozen, observation dates are real completions and finishing never uploads', async () => {
  const f = await fixture();
  assert.equal(ended(f, 'video'), null);
  f.at(T0 + 11000);
  f.client.start({ source: 'camera', variation: 'standard', userId: 'owner-a' });
  f.at(T0 + 15000); f.client.observe(rep);
  f.at(T0 + 30000);
  const body = f.client.finish(4000);
  assert.equal(body.reps.length, 1);
  assert.equal(body.reps[0].observedAt, T0 + 15000);
  assert.equal(body.startedAt, T0 + 11000);
  assert.equal(body.endedAt, T0 + 30000);
  assert.equal(body.timeMs, 4000);
  assert.equal(body.userId, 'owner-a');
  assert.equal(body.source, 'real');
  assert.equal(body.workoutId, ids[1]);
  assert.equal(f.posts.length, 0);
  assert.equal(f.client.pending().length, 0);
});

test('explicit upload durably queues before transport and preserves the same body for explicit retry', async () => {
  let f, attempts = 0;
  f = await fixture({ send: async (body, token) => {
    assert.deepEqual(f.client.pending(), [body]);
    assert.equal(token, 'ephemeral-test-token');
    assert.ok([...f.store.values.values()].every(value => !value.includes(token)));
    if (++attempts === 1) throw new Error('offline');
    return { saved: 1 };
  } });
  const body = ended(f);
  await assert.rejects(f.client.upload(body), /offline/);
  assert.deepEqual(f.client.pending(), [body]);
  assert.equal(attempts, 1);
  await f.client.retry();
  assert.equal(attempts, 2);
  assert.deepEqual(f.client.pending(), []);
});

test('reload does not retry and a different user cannot receive or drain the pending workout', async () => {
  const first = await fixture({ send: async () => { throw new Error('offline'); } });
  const body = ended(first);
  await assert.rejects(first.client.upload(body), /offline/);
  const second = await fixture({ storage: first.store, context: async () => context('owner-b') });
  assert.equal(second.posts.length, 0);
  await assert.rejects(second.client.upload(body), /owner|user/i);
  await second.client.retry();
  assert.equal(second.posts.length, 0);
  assert.deepEqual(second.client.pending(), [body]);
});

test('storage failure prevents transport and does not claim an upload was kept', async () => {
  const f = await fixture({ storage: { getItem: () => null, setItem() { throw new Error('storage full'); } } });
  await assert.rejects(f.client.upload(ended(f)), /storage full/);
  assert.equal(f.posts.length, 0);
  assert.ok(f.statuses.every(info => info?.status !== 'saved'));
});

test('an older upload may finish durably but cannot replace the new workout status', async () => {
  let finish;
  const f = await fixture({ send: () => new Promise(resolve => { finish = resolve; }) });
  const body = ended(f);
  const pending = f.client.upload(body);
  await new Promise(resolve => setImmediate(resolve));
  f.at(T0 + 11000); f.client.start({ source: 'camera', variation: 'standard', userId: 'owner-a' });
  const statusCount = f.statuses.length;
  finish({ saved: 1 }); await pending;
  assert.equal(f.statuses.length, statusCount);
  assert.deepEqual(f.client.pending(), []);
});

test('a server conflict stays terminal until the user explicitly discards that pending copy', async () => {
  let attempts = 0;
  const f = await fixture({ send: async () => { attempts++; throw Object.assign(new Error('workout_conflict'), { status: 409 }); } });
  const body = ended(f);
  await assert.rejects(f.client.upload(body), /workout_conflict/);
  await f.client.retry();
  assert.equal(attempts, 1);
  assert.deepEqual(f.client.conflicts('owner-a'), [body]);
  assert.deepEqual(f.client.conflicts('owner-b'), []);
  f.client.discard(body.workoutId, 'owner-b');
  assert.deepEqual(f.client.pending(), [body]);
  f.client.discard(body.workoutId, 'owner-a');
  assert.deepEqual(f.client.pending(), []);
});

test('an unreadable pending index is preserved instead of overwritten by a new upload', async () => {
  const store = { getItem: () => '{broken', setItem() { throw new Error('must not overwrite'); } };
  const f = await fixture({ storage: store });
  await assert.rejects(f.client.upload(ended(f)), /JSON|Unexpected|property/i);
  assert.equal(f.posts.length, 0);
});

test('finishing twice preserves the exact first snapshot for its immutable UUID', async () => {
  const f = await fixture(), first = ended(f);
  f.at(T0 + 30000); f.client.observe(rep);
  assert.deepEqual(f.client.finish(9000), first);
});

test('training upload preserves a null default issue independently of stricter personal feedback', async () => {
  const f = await fixture();
  f.client.start({ source: 'camera', variation: 'standard', userId: 'owner-a' });
  f.at(T0 + 2000); f.client.observe({ ...rep, baseGood: true, baseIssue: null, good: false, issue: 'go deeper (your rule)' });
  f.at(T0 + 3000);
  const body = f.client.finish(2000);
  assert.equal(body.reps[0].issue, null);
  assert.equal(body.reps[0].good, true);
  assert.equal(parseSync(body, { userId: 'owner-a', now: T0 + 3000 }).rows[0].label, 'good');
});

test('an idempotent server receipt says already saved rather than claiming zero reps', async () => {
  const f = await fixture({ send: async () => ({ saved: 0 }) });
  await f.client.upload(ended(f));
  assert.match(f.statuses.at(-1).text, /already saved/i);
});

test('server success with failed browser cleanup remains truthful and safely retryable', async () => {
  const store = storage(), original = store.setItem;
  let writes = 0;
  store.setItem = (key, value) => { if (++writes === 2) throw new Error('storage blocked'); original(key, value); };
  const f = await fixture({ storage: store });
  const body = ended(f);
  await f.client.upload(body);
  assert.match(f.statuses.at(-1).text, /saved.*cleanup/i);
  assert.equal(f.statuses.at(-1).status, 'saved');
  assert.deepEqual(f.client.pending(), [body]);
});

function beginFixture() {
  let resolvePlay;
  const firstRule = { warnElbow: 74, minLine: 169 }, nextRule = { warnElbow: 70, minLine: 172 };
  const state = vm.createContext({ video: { src: 'blob:replay', play: () => new Promise(resolve => { resolvePlay = resolve; }) },
    counter: { personal: firstRule, setPersonal(rule) { this.personal = rule; } }, ruleFor: () => nextRule,
    savedProfile: { profile: { mockShare: 0 } }, $: () => ({}), clockStart() { state.clockStarted = true; }, setPause() {},
    requestAnimationFrame() { state.frames = (state.frames ?? 0) + 1; }, loop() {} });
  vm.runInContext('let inputGeneration=1,running=false,lastTs=0,lm0Logged=true,ruleUsed="personal",ruleMockShare=0,syncInfo=null;' + section('async function begin(', "$('startCam').onclick"), state);
  return { state, firstRule, resolve: () => resolvePlay() };
}

test('resuming a replay keeps the workout rule even if a new profile was trained while paused', async () => {
  const f = beginFixture(), pending = vm.runInContext('begin()', f.state);
  f.resolve(); await pending;
  assert.deepEqual(f.state.counter.personal, f.firstRule);
});

test('late video playback completion cannot restart a cancelled or replaced source', async () => {
  const f = beginFixture(), pending = vm.runInContext('begin()', f.state);
  vm.runInContext('inputGeneration++;running=false;', f.state);
  f.resolve(); await pending;
  assert.equal(f.state.clockStarted, undefined);
  assert.equal(f.state.frames, undefined);
  assert.equal(vm.runInContext('running', f.state), false);
});

test('explicit upload survives an offline identity endpoint before any transport', async () => {
  const f = await fixture({ context: async () => { throw new Error('offline context'); } });
  const body = ended(f);
  await assert.rejects(f.client.upload(body), /offline context/);
  assert.deepEqual(f.client.pending(), [body]);
  const reloaded = await fixture({ storage: f.store });
  assert.deepEqual(reloaded.client.pending(), [body]);
  assert.equal(reloaded.posts.length, 0);
});

test('a saved personal profile is never used for a different captured workout owner', () => {
  const state = vm.createContext({ localStorage: { getItem: () => 'personal' }, personalRule: () => ({ warnElbow: 74 }),
    savedProfile: { profile: { provenance: { userId: 'owner-a' } } }, counter: { variation: 'standard' } });
  vm.runInContext(section('const RULE_KEY =', 'function updateRuleUI()'), state);
  assert.equal(vm.runInContext("ruleFor('owner-b')", state), null);
});

for (const action of ['camera', 'file', 'resume']) test(`a stale ${action} start cannot update the replacement source after playback fails`, async () => {
  const nodes = new Map();
  const $ = id => { if (!nodes.has(id)) nodes.set(id, { textContent: '', value: '' }); return nodes.get(id); };
  let rejectPlay;
  const state = vm.createContext({ $, video: { src: 'blob:video', canPlayType: () => 'yes' }, landmarker: {}, console: { log() {}, error() {}, warn() {} },
    URL: { createObjectURL: () => 'blob:test' }, navigator: { mediaDevices: { getUserMedia: async () => ({ getTracks: () => [] }) } },
    readCloudContext: async () => context(), newWorkout() {}, begin: () => new Promise((_, reject) => { rejectPlay = reject; }),
    stopAll() { vm.runInContext('inputGeneration++;', state); }, clockPause() {}, setTimeout() {}, publish() {}, askEnd() {},
    canvas: { addEventListener() { state.installedFallback = true; } } });
  vm.runInContext('let inputGeneration=0,cameraStarting=false,stream=null,running=false;' + section("$('startCam').onclick", 'function stopAll()'), state);
  if (action === 'resume') vm.runInContext('paused=true;', state);
  const promise = action === 'camera' ? $('startCam').onclick() : action === 'file' ? $('file').onchange({ target: { files: [{ name: 'test.mp4', type: 'video/mp4' }], value: '' } }) : $('pause').onclick();
  await new Promise(resolve => setImmediate(resolve));
  vm.runInContext('inputGeneration++;', state); $('status').textContent = 'Replacement source';
  rejectPlay(Object.assign(new Error('old playback denied'), { name: 'NotAllowedError' })); await promise;
  assert.equal($('status').textContent, 'Replacement source');
  assert.equal(state.installedFallback, undefined);
});

test('profile refresh cannot relabel the locked default workout as a newly available personal rule', () => {
  const nodes = { ruleMode: { disabled: true, querySelector: () => ({}) }, ruleNote: {} };
  const state = vm.createContext({ $: id => nodes[id], personalRule: () => ({ warnElbow: 74, minLine: 169 }), getMode: () => 'personal',
    savedProfile: { profile: { reps: 300, sessions: 10, mockShare: 0 } }, counter: { variation: 'standard', personal: null },
    ruleInfo: () => ({ mode: 'default', text: 'Default rule' }), VARIATIONS: { standard: { down: 90, minLine: 165 } } });
  vm.runInContext(section('function updateRuleUI()', "$('ruleMode').onchange"), state);
  vm.runInContext('updateRuleUI()', state);
  assert.equal(nodes.ruleMode.value, 'default');
  assert.match(nodes.ruleNote.textContent, /Default rule/);
});

test('profile summary describes held-out label agreement without implying ground-truth form accuracy', () => {
  const state = vm.createContext({ esc: String });
  vm.runInContext(section('function profileSummary(', 'async function profileRefresh()'), state);
  const html = vm.runInContext('profileSummary({baselines:{elbow:{typical:80,spread:2},body_line:{typical:175,spread:2},seconds:{typical:2}},holdoutAccuracy:1,mockShare:1,rules:[]})', state);
  assert.match(html, /Held-out label agreement:.*100%/);
  assert.doesNotMatch(html, /100% right/);
});

test('an older discard review cannot replace the new workout status after identity lookup', async () => {
  const nodes = { discardConflicts: {}, status: { textContent: '' } };
  let resolveContext;
  const state = vm.createContext({ $: id => nodes[id], readCloudContext: () => new Promise(resolve => { resolveContext = resolve; }),
    client: { conflicts: () => [] } });
  vm.runInContext("let currentWorkoutId='old';" + section("$('discardConflicts').onclick", 'function saveWorkout(st)'), state);
  const pending = nodes.discardConflicts.onclick();
  vm.runInContext("currentWorkoutId='new';", state); nodes.status.textContent = 'Replacement source';
  resolveContext(context()); await pending;
  assert.equal(nodes.status.textContent, 'Replacement source');
});

test('Stop cancels an opened camera while its video playback is still pending', async () => {
  const nodes = new Map();
  const $ = id => { if (!nodes.has(id)) nodes.set(id, { textContent: '' }); return nodes.get(id); };
  let resolvePlay, stopped = 0;
  const state = vm.createContext({ $, video: { pause() {}, removeAttribute() {} }, console: { log() {} },
    navigator: { mediaDevices: { getUserMedia: async () => ({ getTracks: () => [{ stop() { stopped++; } }] }) } },
    readCloudContext: async () => context(), newWorkout() {}, begin: () => new Promise(resolve => { resolvePlay = resolve; }),
    clockPause() {}, setTimeout() {}, askEnd() {} });
  vm.runInContext('let inputGeneration=0,cameraStarting=false,stream=null,running=false;' + section("$('startCam').onclick", 'function loop()'), state);
  const pending = $('startCam').onclick();
  await new Promise(resolve => setImmediate(resolve));
  $('stop').onclick();
  assert.equal(stopped, 1);
  assert.equal(vm.runInContext('inputGeneration', state), 2);
  resolvePlay(false); await pending;
  assert.equal($('status').textContent, 'Camera start cancelled.');
});

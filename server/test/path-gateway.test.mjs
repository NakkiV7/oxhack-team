import assert from 'node:assert/strict';
import { once } from 'node:events';
import test from 'node:test';
import { createGateway } from '../src/gateway.mjs';
import { pathCatalog } from '../src/path-contracts.mjs';

const env = { SPOTTR_GATEWAY_TOKEN: 'test-token', GEMINI_API_KEY: 'test-key', GEMINI_MODEL: 'gemini-test' };
const post = data => ({ method: 'POST', headers: { authorization: 'Bearer test-token', 'content-type': 'application/json' }, body: JSON.stringify(data) });
const providerResponse = output => Response.json({ candidates: [{ finishReason: 'STOP', content: { parts: [{ text: typeof output === 'string' ? output : JSON.stringify(output) }] } }] });

async function serve(t, reply) {
  const calls = [];
  const server = createGateway({ env, fetchImpl: async (_url, options) => { calls.push(JSON.parse(options.body)); return providerResponse(reply()); } });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(() => new Promise(resolve => server.close(resolve)));
  const origin = `http://127.0.0.1:${server.address().port}`;
  return { calls, request: (path, data) => fetch(`${origin}${path}`, post(data)) };
}

// A beginner on the squat path who has a stable support and left nothing out (built by the app from its own rules).
const pathInput = {
  generationID: 'path-1', goal: 'squat',
  answers: { band: 'beginner', focus: 'learn', coachingStyle: 'encouraging', minutesPerSession: 20, sessionsPerWeek: 3 },
  exercises: [
    { id: 'gluteBridge', capability: 'practiceLog', allowedPrerequisites: [], maxTarget: 18 },
    { id: 'squat', capability: 'cameraAssessment', allowedPrerequisites: ['gluteBridge'], maxTarget: 18 },
    { id: 'reverseLunge', capability: 'practiceLog', allowedPrerequisites: ['squat', 'singleLegBalance'], maxTarget: 12 },
    { id: 'splitSquat', capability: 'practiceLog', allowedPrerequisites: ['reverseLunge'], maxTarget: 12 },
    { id: 'assistedSquat', capability: 'practiceLog', allowedPrerequisites: ['splitSquat', 'hipFlexorStretch'], maxTarget: 8 },
    { id: 'singleLegBalance', capability: 'practiceLog', allowedPrerequisites: [], maxTarget: 30 },
    { id: 'hipFlexorStretch', capability: 'practiceLog', allowedPrerequisites: [], maxTarget: 45 }
  ],
  allowedStarts: ['gluteBridge'], ruleStart: 'gluteBridge'
};
const target = { sets: 3, target: 8, perWeek: 3 };
const validPath = {
  generationID: 'path-1',
  nodes: [
    { id: 'gluteBridge', why: 'Builds hip control first. Camera tracking is not trained for it yet.', prerequisites: [], optional: false, supports: null, practiceTarget: target },
    { id: 'squat', why: 'The camera can time your lowering here.', prerequisites: ['gluteBridge'], optional: false, supports: null, practiceTarget: target },
    { id: 'reverseLunge', why: 'Adds single-leg balance.', prerequisites: ['squat'], optional: false, supports: null, practiceTarget: target },
    { id: 'splitSquat', why: 'Holds a split stance under control.', prerequisites: ['reverseLunge'], optional: false, supports: null, practiceTarget: target },
    { id: 'assistedSquat', why: 'The goal: a supported single-leg squat.', prerequisites: ['splitSquat'], optional: false, supports: null, practiceTarget: { sets: 3, target: 5, perWeek: 3 } },
    { id: 'singleLegBalance', why: 'Optional balance practice for lunges.', prerequisites: [], optional: true, supports: 'reverseLunge', practiceTarget: { sets: 2, target: 20, perWeek: 3 } }
  ],
  start: 'gluteBridge', goalNode: 'assistedSquat', route: ['gluteBridge', 'squat', 'reverseLunge', 'splitSquat', 'assistedSquat'],
  rationale: 'Starts with the pattern and builds towards single-leg control.', startReason: 'You chose to learn the movement first.', emphasis: 'Smooth, controlled reps.'
};

test('path proposals send the person\'s bounded options and return a validated path', async t => {
  const { calls, request } = await serve(t, () => validPath);
  const response = await request('/v1/path-proposal', pathInput);
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), validPath);
  const payload = calls[0];
  const current = JSON.parse(payload.contents[0].parts[0].text);
  assert.equal(current.task, '/v1/path-proposal');
  assert.deepEqual(current.exercises, pathInput.exercises);
  assert.match(payload.systemInstruction.parts.at(-1).text, /allowedPrerequisites/);
  assert.equal(payload.generationConfig.responseFormat.text.schema.properties.start.enum[0], 'gluteBridge');
  assert.equal(payload.generationConfig.maxOutputTokens, 4096);
});

test('path proposals reject requests the app could not have built, before any provider call', async t => {
  const { calls, request } = await serve(t, () => validPath);
  const bad = [
    { ...pathInput, goal: 'burpee' },
    { ...pathInput, ruleStart: 'squat' },
    { ...pathInput, exercises: pathInput.exercises.filter(item => item.id !== 'squat') },
    { ...pathInput, exercises: pathInput.exercises.map(item => item.id === 'squat' ? { ...item, maxTarget: 40 } : item) },
    { ...pathInput, exercises: pathInput.exercises.map(item => item.id === 'squat' ? { ...item, allowedPrerequisites: ['plank'] } : item) },
    { ...pathInput, extra: true }
  ];
  for (const input of bad) assert.equal((await request('/v1/path-proposal', input)).status, 422);
  assert.equal(calls.length, 0);
});

test('generated paths that break a rule fail validation', async t => {
  let output;
  const { request } = await serve(t, () => output);
  const edit = (id, change) => ({ ...validPath, nodes: validPath.nodes.map(node => node.id === id ? { ...node, ...change } : node) });
  const broken = {
    unknownExercise: edit('reverseLunge', { id: 'plank' }),
    inventedLink: edit('squat', { prerequisites: ['assistedSquat'] }),
    disallowedStart: { ...validPath, start: 'squat' },
    twoOptional: edit('assistedSquat', { optional: true }),
    supportsWithoutOptional: edit('squat', { supports: 'reverseLunge' }),
    targetTooHigh: edit('assistedSquat', { practiceTarget: { sets: 3, target: 12, perWeek: 3 } }),
    moreSessionsThanPlanned: edit('squat', { practiceTarget: { sets: 3, target: 8, perWeek: 5 } }),
    link: { ...validPath, rationale: 'See www.example.com for more.' },
    staleGeneration: { ...validPath, generationID: 'path-0' },
    duplicateNodes: { ...validPath, nodes: [...validPath.nodes.slice(0, 5), validPath.nodes[0]] },
    // A real Gemini plan ended at squats with lunges and split squats after it.
    goalBeforeTheEnd: { ...validPath, goalNode: 'squat', route: ['gluteBridge', 'squat'] }
  };
  for (const [name, value] of Object.entries(broken)) {
    output = value;
    assert.equal((await request('/v1/path-proposal', pathInput)).status, 502, name);
  }
});

const cueInput = (exerciseID = 'squat', median = 1.34) => ({
  generationID: 'cue-1',
  contract: exerciseID === 'squat'
    ? { exerciseID, version: 'squat-tempo-v1', metric: 'lowering', label: 'lowering time', target: 1.5, tolerance: 0.15 }
    : { exerciseID, version: 'pushup-cadence-v1', metric: 'repTime', label: 'rep time', target: 2, tolerance: 0.25 },
  baseline: { validReps: 3, median },
  coachingStyle: 'concise',
  facts: [{ id: 'baseline', text: `Baseline median ${median} s over 3 counted reps.` }, { id: 'target', text: exerciseID === 'squat' ? 'Target 1.5 s within 0.15 s.' : 'Target 2 s within 0.25 s.' }]
});

test('cues follow the frozen target and only state supplied numbers, for squats and push-ups', async t => {
  let output;
  const { calls, request } = await serve(t, () => output);
  output = { generationID: 'cue-1', action: 'cue_target', text: 'Count to 2 on the way down, aiming for 1.5 s.', factIDs: ['target'] };
  assert.equal((await request('/v1/attempt-cue', cueInput())).status, 200);
  output = { generationID: 'cue-1', action: 'maintain_target', text: 'Keep exactly that rhythm.', factIDs: ['baseline'] };
  assert.equal((await request('/v1/attempt-cue', cueInput('squat', 1.34))).status, 502);   // 1.34 s is outside 1.5 s ± 0.15 s
  assert.equal((await request('/v1/attempt-cue', cueInput('squat', 1.45))).status, 200);
  output = { generationID: 'cue-1', action: 'cue_target', text: 'Slow down to 1.7 s per rep.', factIDs: ['target'] };
  assert.equal((await request('/v1/attempt-cue', cueInput('squat', 1.1))).status, 502);   // 1.7 is not in the facts
  output = { generationID: 'cue-1', action: 'cue_target', text: 'Slow each push-up to about 2 s.', factIDs: ['target'] };
  assert.equal((await request('/v1/attempt-cue', cueInput('pushup', 1.4))).status, 200);
  const before = calls.length;
  assert.equal((await request('/v1/attempt-cue', { ...cueInput(), contract: { ...cueInput().contract, exerciseID: 'plank' } })).status, 422);
  assert.equal(calls.length, before);   // no camera tracker is trained for planks, so nothing is assessed
  assert.match(calls[0].systemInstruction.parts.at(-1).text, /cannot change/);
});

test('explanations cannot introduce numbers or links', async t => {
  let output;
  const { request } = await serve(t, () => output);
  const input = {
    generationID: 'why-1', contract: cueInput().contract, outcome: { classification: 'closer', retryMeets: true }, coachingStyle: null,
    facts: [{ id: 'baseline', text: 'Baseline median 0.9 s.' }, { id: 'retry', text: 'Retry median 1.5 s, within 0.15 s of the target.' }, { id: 'result', text: 'Classified as closer to the target.' }]
  };
  output = { generationID: 'why-1', text: 'Your retry median of 1.5 s was within 0.15 s of the target, closer than your 0.9 s baseline.', factIDs: ['baseline', 'retry', 'result'] };
  assert.equal((await request('/v1/attempt-explanation', input)).status, 200);
  output = { generationID: 'why-1', text: 'You improved by 67 percent.', factIDs: ['result'] };
  assert.equal((await request('/v1/attempt-explanation', input)).status, 502);
  output = { generationID: 'why-1', text: 'Closer to the target; read more at https://example.com.', factIDs: ['result'] };
  assert.equal((await request('/v1/attempt-explanation', input)).status, 502);
  output = { generationID: 'why-1', text: 'Closer to the target.', factIDs: ['invented'] };
  assert.equal((await request('/v1/attempt-explanation', input)).status, 502);
});

test('new routes keep bearer authentication and the catalogue stays in step with the app', async t => {
  const server = createGateway({ env, fetchImpl: () => { throw Error('provider must not be called'); } });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(() => new Promise(resolve => server.close(resolve)));
  const response = await fetch(`http://127.0.0.1:${server.address().port}/v1/path-proposal`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(pathInput) });
  assert.equal(response.status, 401);
  assert.equal(pathCatalog.length, 19);
  assert.deepEqual(pathCatalog.filter(item => item.tracked).map(item => item.id).sort(), ['pushup', 'squat']);
});

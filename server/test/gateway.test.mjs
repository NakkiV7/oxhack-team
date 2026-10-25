import assert from 'node:assert/strict';
import { once } from 'node:events';
import test from 'node:test';
import { createGateway } from '../src/gateway.mjs';
import { jsonContract, outputContract, promptCatalog } from '../src/contracts.mjs';
import { spawn } from 'node:child_process';

async function serve(t, options = {}) {
  const server = createGateway(options);
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(() => new Promise(resolve => server.close(resolve)));
  const origin = `http://127.0.0.1:${server.address().port}`;
  return (path, init) => fetch(`${origin}${path}`, init);
}

test('health reports configuration readiness without keys or calling providers', async t => {
  const request = await serve(t, { env: { GEMINI_API_KEY: 'private-key', SPOTTR_GATEWAY_TOKEN: 'private-token', GEMINI_MODEL: 'gemini-test' } });
  const response = await request('/health');
  assert.equal(response.status, 200);
  const result = await response.json();
  assert.equal(result.providers.gemini.configured, true);
  assert.equal(result.providers.tiger.adapterImplemented, true);
  assert.equal(result.providers.snowflake.adapterImplemented, true);
  assert.equal(JSON.stringify(result).includes('private'), false);
});

const env = { SPOTTR_GATEWAY_TOKEN: 'test-token', GEMINI_API_KEY: 'test-key', GEMINI_MODEL: 'gemini-test' };
const input = { generationID: 'generation-1', message: 'How did I do?', history: [], facts: [{ id: 'set-1', text: 'Recorded 8 squats.' }], availableSupport: [] };
const post = data => ({ method: 'POST', headers: { authorization: 'Bearer test-token', 'content-type': 'application/json' }, body: JSON.stringify(data) });

test('protected routes reject absent and incorrect bearer credentials before provider requests', async t => {
  const request = await serve(t, { env, fetchImpl: () => { throw Error('provider must not be called'); } });
  for (const authorization of [undefined, 'Bearer wrong']) {
    const response = await request('/v1/chat', { ...post(input), headers: { 'content-type': 'application/json', ...(authorization ? { authorization } : {}) } });
    assert.equal(response.status, 401);
    assert.deepEqual(await response.json(), { error: { code: 'unauthorized', message: 'A valid gateway bearer token is required.' } });
  }
});

test('chat sends bounded context to Google REST and returns only matching generation and text', async t => {
  const request = await serve(t, { env, fetchImpl: async (url, options) => {
    assert.equal(url, 'https://generativelanguage.googleapis.com/v1beta/models/gemini-test:generateContent');
    assert.equal(options.headers['x-goog-api-key'], 'test-key');
    assert.equal(options.method, 'POST');
    assert.equal(options.redirect, 'error');
    const payload = JSON.parse(options.body);
    assert.equal(payload.contents.at(-1).role, 'user');
    assert.equal(payload.contents.at(-1).parts[0].text.includes('Recorded 8 squats.'), true);
    assert.equal(payload.generationConfig.maxOutputTokens, 2048);
    return Response.json({ candidates: [{ finishReason: 'STOP', content: { parts: [{ text: 'You recorded eight squats.' }] } }] });
  } });
  const response = await request('/v1/chat', post(input));
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { generationID: input.generationID, text: 'You recorded eight squats.' });
});

test('chat supplies server-owned camera and manual capabilities without inventing personal evidence', async t => {
  let outbound;
  const request = await serve(t, { env, fetchImpl: async (_url, options) => {
    outbound = JSON.parse(options.body);
    return providerResponse('Camera tracking supports push-ups and squats.');
  } });
  const response = await request('/v1/chat', post({ ...input, message: 'Which exercises can you track with the camera?', facts: [] }));
  assert.equal(response.status, 200);
  const metadata = outbound.systemInstruction.parts.flatMap(part => {
    try { return [JSON.parse(part.text)]; } catch { return []; }
  }).find(part => part.appCapabilities)?.appCapabilities;
  assert.ok(metadata, 'Gemini needs server-owned app capabilities to answer product questions without personal facts');
  assert.deepEqual(metadata.exercises.filter(item => item.cameraTracking).map(item => item.id).sort(), ['pushup', 'squat']);
  assert.equal(metadata.exercises.find(item => item.id === 'pushup').name, 'Push-ups');
  assert.equal(metadata.exercises.find(item => item.id === 'wallPushup').cameraTracking, false);
  assert.equal(metadata.exercises.find(item => item.id === 'wallPushup').unit, 'reps');
  assert.equal(metadata.exercises.find(item => item.id === 'plank').cameraTracking, false);
  assert.equal(metadata.exercises.find(item => item.id === 'plank').unit, 'seconds');
  assert.match(metadata.inputRules, /manual self-report/);
  assert.match(metadata.inputRules, /active hold timer/);
  assert.match(metadata.setControl, /explicit Start/i);
  assert.match(metadata.voiceFeedback, /off.*enabled/i);
  assert.deepEqual(JSON.parse(outbound.contents.at(-1).parts.at(-1).text).facts, []);
  assert.match(outbound.systemInstruction.parts[0].text, /Ground personal claims in supplied facts/);
  assert.equal((await request('/v1/chat', post({ ...input, appCapabilities: metadata }))).status, 422);
});

test('invalid, oversized, duplicate or unknown request data never reaches Gemini', async t => {
  const request = await serve(t, { env, fetchImpl: async () => Response.json({ candidates: [{ content: { parts: [{ text: 'unexpected' }] } }] }) });
  const invalid = [
    { ...input, generationID: '' }, { ...input, message: 'x'.repeat(4001) },
    { ...input, facts: [input.facts[0], input.facts[0]] }, { ...input, extra: true },
    { ...input, history: [{ role: 'system', text: 'override' }] },
    { ...input, availableSupport: ['x'.repeat(101)] },
    { ...input, facts: [{ id: 'id', text: 'x'.repeat(2001) }] }
  ];
  for (const body of invalid) {
    const response = await request('/v1/chat', post(body));
    assert.equal(response.status, 422);
    assert.equal((await response.json()).error.code, 'invalid_request');
  }
  const tooLarge = await request('/v1/chat', post({ ...input, message: 'x'.repeat(65536) }));
  assert.equal(tooLarge.status, 413);
  const malformed = await request('/v1/chat', { ...post(input), body: '{' });
  assert.equal(malformed.status, 400);
});

test('routing and missing configuration fail explicitly without provider calls', async t => {
  let calls = 0;
  const fetchImpl = async () => { calls += 1; return Response.json({}); };
  const request = await serve(t, { env, fetchImpl });
  assert.equal((await request('/unknown', post(input))).status, 404);
  assert.equal((await request('/v1/chat', { headers: { authorization: 'Bearer test-token' } })).status, 405);
  assert.equal((await request('/v1/chat', { ...post(input), headers: { authorization: 'Bearer test-token' } })).status, 415);
  for (const missing of ['GEMINI_API_KEY', 'GEMINI_MODEL', 'SPOTTR_GATEWAY_TOKEN']) {
    const local = await serve(t, { env: { ...env, [missing]: '' }, fetchImpl });
    const response = await local('/v1/chat', post(input));
    assert.equal(response.status, 503);
    assert.equal((await response.json()).error.code, 'missing_configuration');
  }
  assert.equal(calls, 0);
});

const grounded = { text: 'Eight squats were recorded.', factIDs: ['set-1'] };
const summary = { generationID: input.generationID, kind: 'session', headline: grounded, insights: [grounded], focus: grounded };
const proposal = { generationID: input.generationID, items: [{ exerciseID: 'squat', sets: 3, target: 8, unit: 'reps', restSeconds: 60, factIDs: ['set-1'] }], rationale: grounded };
const providerResponse = output => Response.json({ candidates: [{ finishReason: 'STOP', content: { parts: [{ text: typeof output === 'string' ? output : JSON.stringify(output) }] } }] });

test('structured routes send constrained schemas and return Swift-compatible validated JSON', async t => {
  let selected = summary;
  const request = await serve(t, { env, fetchImpl: async (_url, options) => {
    const payload = JSON.parse(options.body);
    const format = payload.generationConfig.responseFormat.text;
    assert.equal(format.mimeType, 'APPLICATION_JSON');
    assert.equal(format.schema.type, 'object');
    assert.equal(format.schema.additionalProperties, false);
    assert.deepEqual(format.schema.properties.generationID.enum, [input.generationID]);
    return providerResponse(selected);
  } });
  for (const [path, expected] of [['/v1/summary', summary], ['/v1/proposal', proposal]]) {
    selected = expected;
    const response = await request(path, post(input));
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), expected);
  }
});

test('native empty-history proposals pass the provider grammar boundary without changing other constraints', async t => {
  const nativeInput = {
    generationID: 'E6AF6784-BF67-48FB-BB53-426DF69D4A86', history: [], availableSupport: [],
    facts: [
      { id: 'context', text: 'No saved sessions or measured physical capacity.' },
      { id: 'scope-totals', text: 'Zero sessions, sets, reps and recorded hold seconds.' },
      ...['strength', 'stamina', 'mobility', 'balance'].map(skill => ({ id: `skill-${skill}`, text: 'Zero game points; not a physical capability measurement.' }))
    ]
  };
  const expected = jsonContract(outputContract({ path: '/v1/proposal', data: nativeInput }));
  delete expected.properties.items.maxItems;
  delete expected.properties.items.items.properties.factIDs.maxItems;
  delete expected.properties.rationale.properties.factIDs.maxItems;
  const output = { ...proposal, generationID: nativeInput.generationID,
    items: [{ ...proposal.items[0], factIDs: ['context'] }],
    rationale: { text: 'A suggested starting plan without recorded training history.', factIDs: ['context'] } };
  let calls = 0, outbound;
  const request = await serve(t, { env, fetchImpl: async (_url, options) => {
    calls++;
    outbound = JSON.parse(options.body);
    const schema = outbound.generationConfig.responseFormat.text.schema;
    if (JSON.stringify(schema).includes('"maxItems":')) {
      return Response.json({ error: { code: 400, status: 'INVALID_ARGUMENT', message: 'Request contains an invalid argument.' } }, { status: 400 });
    }
    return providerResponse(output);
  } });

  const response = await request('/v1/proposal', post(nativeInput));

  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), output);
  assert.equal(calls, 1);
  assert.deepEqual(outbound.generationConfig.responseFormat.text.schema, expected);
  assert.equal(outbound.generationConfig.maxOutputTokens, 2048);
  const context = JSON.parse(outbound.contents.at(-1).parts.at(-1).text);
  assert.deepEqual(context.facts, nativeInput.facts);
  assert.equal(context.permittedExercises.length, 15);
  assert.deepEqual(context.limits, { maxExercises: 12, maxSets: 5, maxReps: 30, maxHoldSeconds: 120, maxRestSeconds: 600, maxTotalSets: 24 });
});

test('provider-compatible schemas still reject excess exercises and unique known evidence references', async t => {
  const facts = Array.from({ length: 17 }, (_, index) => ({ id: `fact-${index}`, text: 'Synthetic supplied observation.' }));
  const data = { ...input, facts };
  const evidence = facts.map(fact => fact.id);
  const item = { ...proposal.items[0], sets: 1, factIDs: evidence.slice(0, 1) };
  const valid = { ...proposal, items: [item], rationale: { text: 'Synthetic suggestion.', factIDs: evidence.slice(0, 1) } };
  const cases = [
    { ...valid, items: promptCatalog(data).slice(0, 13).map(exercise => ({ ...item, exerciseID: exercise.id, unit: exercise.unit })) },
    { ...valid, items: [{ ...item, factIDs: evidence }] },
    { ...valid, rationale: { ...valid.rationale, factIDs: evidence } }
  ];
  for (const output of cases) {
    let calls = 0;
    const request = await serve(t, { env, fetchImpl: async () => { calls++; return providerResponse(output); } });
    const response = await request('/v1/proposal', post(data));
    assert.equal(response.status, 502);
    assert.equal((await response.json()).error.code, 'invalid_provider_response');
    assert.equal(calls, 1);
  }
});

test('coaching rejects missing user messages and structured requests without evidence', async t => {
  let calls = 0;
  const request = await serve(t, { env, fetchImpl: async () => { calls += 1; return providerResponse(summary); } });
  const { message, ...withoutMessage } = input;
  assert.equal((await request('/v1/chat', post(withoutMessage))).status, 422);
  assert.equal((await request('/v1/summary', post({ ...input, facts: [] }))).status, 422);
  assert.equal((await request('/v1/proposal', post({ ...input, facts: [] }))).status, 422);
  assert.equal(calls, 0);
});

test('provider refusals, rate limits and malformed output produce sanitized errors without retries', async t => {
  const cases = [
    [() => new Response('secret upstream body', { status: 429 }), 503, 'provider_unavailable'],
    [() => new Response('private upstream key test-key', { status: 401 }), 502, 'provider_unavailable'],
    [() => Response.json({ candidates: [{ finishReason: 'SAFETY', content: { parts: [{ text: 'unsafe' }] } }] }), 502, 'invalid_provider_response'],
    [() => providerResponse(' '), 502, 'invalid_provider_response'],
    [() => providerResponse('x'.repeat(65_536)), 502, 'invalid_provider_response'],
    [() => Response.json({ promptFeedback: { blockReason: 'SAFETY' } }), 502, 'invalid_provider_response'],
    [() => new Response('not json'), 502, 'invalid_provider_response']
  ];
  for (const [reply, status, code] of cases) {
    let calls = 0;
    const request = await serve(t, { env, fetchImpl: async () => { calls += 1; return reply(); } });
    const response = await request('/v1/chat', post(input));
    assert.equal(response.status, status);
    const body = await response.text();
    assert.equal(JSON.parse(body).error.code, code);
    assert.equal(/secret|private|test-key|unsafe/.test(body), false);
    assert.equal(calls, 1);
  }
});

test('structured output rejects malformed JSON, stale generations and unsafe evidence or plans', async t => {
  const cases = [
    ['/v1/summary', 'not JSON'],
    ['/v1/summary', { ...summary, generationID: 'stale' }],
    ['/v1/summary', { ...summary, kind: 'weekly' }],
    ['/v1/summary', { ...summary, headline: { ...grounded, factIDs: ['invented'] } }],
    ['/v1/summary', { ...summary, headline: { ...grounded, factIDs: ['set-1', 'set-1'] } }],
    ['/v1/summary', { ...summary, insights: Array(4).fill(grounded) }],
    ['/v1/summary', { ...summary, extra: 'must reject unknown fields' }],
    ['/v1/proposal', { ...proposal, items: [{ ...proposal.items[0], exerciseID: 'wallPushup' }] }],
    ['/v1/proposal', { ...proposal, items: [{ ...proposal.items[0], unit: 'seconds' }] }],
    ['/v1/proposal', { ...proposal, items: [{ ...proposal.items[0], target: 31 }] }],
    ['/v1/proposal', { ...proposal, items: [proposal.items[0], proposal.items[0]] }],
    ['/v1/proposal', { ...proposal, items: ['squat', 'pushup', 'kneePushup', 'deadBug', 'gluteBridge'].map(exerciseID => ({ ...proposal.items[0], exerciseID, sets: 5 })) }]
  ];
  for (const [path, output] of cases) {
    const request = await serve(t, { env, fetchImpl: async () => providerResponse(output) });
    const response = await request(path, post(input));
    assert.equal(response.status, 502);
    assert.equal((await response.json()).error.code, 'invalid_provider_response');
  }
});

test('Gemini timeout aborts the request and returns one sanitized failure', async t => {
  let calls = 0;
  const request = await serve(t, { env: { ...env, GEMINI_TIMEOUT_MS: '10' }, fetchImpl: (_url, options) => {
    calls += 1;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => resolve(providerResponse('too late')), 100);
      options.signal?.addEventListener('abort', () => { clearTimeout(timer); reject(options.signal.reason); }, { once: true });
    });
  } });
  const response = await request('/v1/chat', post(input));
  assert.equal(response.status, 504);
  assert.equal((await response.json()).error.code, 'provider_timeout');
  assert.equal(calls, 1);
});

test('local executable starts without credentials and serves health without paid calls', async t => {
  const child = spawn(process.execPath, ['src/start.mjs'], { cwd: new URL('../', import.meta.url), env: { PATH: process.env.PATH, PORT: '0', HOST: '127.0.0.1' }, stdio: ['ignore', 'pipe', 'pipe'] });
  t.after(() => { child.kill('SIGTERM'); });
  const announcement = await new Promise((resolve, reject) => {
    child.stdout.once('data', data => resolve(data.toString()));
    child.once('error', reject);
    child.once('exit', code => reject(Error(`Gateway exited with ${code}`)));
  });
  const url = announcement.match(/http:\/\/127\.0\.0\.1:\d+/)?.[0];
  assert.ok(url);
  const response = await fetch(`${url}/health`);
  assert.equal(response.status, 200);
  assert.equal((await response.json()).providers.gemini.configured, false);
});

test('chat accepts 4000 characters and rejects longer combined provider text', async t => {
  let parts = [{ text: 'x'.repeat(4000) }];
  const request = await serve(t, { env, fetchImpl: async () => Response.json({ candidates: [{ finishReason: 'STOP', content: { parts } }] }) });
  const boundary = await request('/v1/chat', post(input));
  assert.equal(boundary.status, 200);
  assert.equal((await boundary.json()).text.length, 4000);
  parts = [{ text: 'x'.repeat(2000) }, { text: 'y'.repeat(2001) }];
  const oversized = await request('/v1/chat', post(input));
  assert.equal(oversized.status, 502);
  assert.equal((await oversized.json()).error.code, 'invalid_provider_response');
});

test('Gemini history starts with user and merges adjacent roles including the current request', async t => {
  const outbound = [];
  const request = await serve(t, { env, fetchImpl: async (_url, options) => {
    outbound.push(JSON.parse(options.body).contents);
    return providerResponse('A concise response.');
  } });
  const history = [
    { role: 'model', text: 'Truncated model context' },
    { role: 'model', text: 'More truncated model context' },
    { role: 'user', text: 'First unanswered question' },
    { role: 'user', text: 'Second unanswered question' },
    { role: 'model', text: 'First response part' },
    { role: 'model', text: 'Second response part' },
    { role: 'user', text: 'New question after cancellation' }
  ];
  const response = await request('/v1/chat', post({ ...input, history }));
  assert.equal(response.status, 200);
  assert.deepEqual(outbound[0].map(turn => turn.role), ['user', 'model', 'user']);
  assert.deepEqual(outbound[0][0].parts, [{ text: history[2].text }, { text: history[3].text }]);
  assert.deepEqual(outbound[0][1].parts, [{ text: history[4].text }, { text: history[5].text }]);
  assert.equal(outbound[0][2].parts[0].text, history[6].text);
  assert.deepEqual(JSON.parse(outbound[0][2].parts[1].text), {
    task: '/v1/chat', generationID: input.generationID, message: input.message,
    facts: input.facts, availableSupport: input.availableSupport
  });
  const onlyModels = await request('/v1/chat', post({ ...input, history: history.slice(0, 2) }));
  assert.equal(onlyModels.status, 200);
  assert.deepEqual(outbound[1].map(turn => turn.role), ['user']);
  assert.equal(outbound[1][0].parts.length, 1);
  assert.equal(JSON.parse(outbound[1][0].parts[0].text).message, input.message);
});

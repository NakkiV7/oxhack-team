import assert from 'node:assert/strict';
import test from 'node:test';
import { once } from 'node:events';
import { createGateway } from '../src/gateway.mjs';

const env = { SPOTTR_GATEWAY_TOKEN: 'test', GEMINI_API_KEY: 'fake', GEMINI_MODEL: 'fake' };
const week = { startDate: '2026-10-25', timeZone: 'Europe/London', availableDays: [0, 2, 4], targetDays: 3 };
const input = { generationID: 'week-1', message: 'A short week please', history: [], facts: [{ id: 'context', text: 'No recorded capacity.' }], availableSupport: [], week };
const grounded = { text: 'A suggestion based on your preferences, not measured readiness.', factIDs: ['context'] };
const workout = { generationID: input.generationID, items: [{ exerciseID: 'squat', sets: 2, target: 8, unit: 'reps', restSeconds: 60, factIDs: ['context'] }], rationale: grounded };
const proposal = () => ({ generationID: input.generationID, status: 'proposed', weekStart: week.startDate, timeZone: week.timeZone, days: Array.from({ length: 7 }, (_, i) => ({ date: `2026-10-${25 + i}`, kind: i === 0 ? 'workout' : 'rest', workout: i === 0 ? structuredClone(workout) : null })), rationale: grounded, guidanceIDs: ['nhs-strength'] });
const reply = output => Response.json({ candidates: [{ finishReason: 'STOP', content: { parts: [{ text: JSON.stringify(output) }] } }] });
async function serve(t, options = {}) {
  const server = createGateway({ env, now: () => Date.parse('2026-10-25T09:00:00Z'), ...options });
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  t.after(() => new Promise(resolve => server.close(resolve)));
  return async (data = input, path = '/v1/week-proposal') => fetch(`http://127.0.0.1:${server.address().port}${path}`, { method: 'POST', headers: { authorization: 'Bearer test', 'content-type': 'application/json' }, body: JSON.stringify(data) });
}

test('weekly planning returns seven local dates with existing grounded workout validation', async t => {
  let outbound;
  const request = await serve(t, { fetchImpl: async (_url, options) => { outbound = JSON.parse(options.body); return reply(proposal()); } });
  const response = await request();
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), proposal());
  const context = JSON.parse(outbound.contents.at(-1).parts.at(-1).text);
  assert.deepEqual(context.week, week);
  assert.equal(context.requestedAtUTC, '2026-10-25T09:00:00.000Z');
  assert.equal(outbound.generationConfig.maxOutputTokens, 4096);
  assert.match(JSON.stringify(outbound.systemInstruction), /nhs-strength/);
  assert.doesNotMatch(JSON.stringify(outbound.generationConfig.responseFormat), /"maxItems":/);
});

test('weekly output rejects impossible dates, extra sources, unsafe quantities and unsupported equipment', async t => {
  const corruptions = [
    p => { p.days[1].date = p.days[0].date; },
    p => { p.days.pop(); },
    p => { p.timeZone = 'UTC'; },
    p => { p.guidanceIDs = ['invented']; },
    p => { p.days[0].workout.items[0].target = 31; },
    p => { p.days[0].workout.items[0].unit = 'seconds'; },
    p => { p.days[0].workout.items[0].factIDs = ['invented']; },
    p => { p.days[0].workout.items[0].exerciseID = 'wallPushup'; },
    p => { p.days[1] = { ...p.days[1], kind: 'workout', workout }; },
    p => { p.days[0].workout.items = ['squat', 'pushup', 'kneePushup', 'gluteBridge'].map(exerciseID => ({ ...workout.items[0], exerciseID })); },
    p => { p.extra = true; }
  ];
  for (const corrupt of corruptions) {
    const output = proposal(); corrupt(output);
    const request = await serve(t, { fetchImpl: async () => reply(output) });
    const response = await request();
    assert.equal(response.status, 502);
    assert.equal((await response.json()).error.code, 'invalid_provider_response');
  }
});

test('invalid week requests never reach a provider and old routes reject the new context', async t => {
  let calls = 0;
  const request = await serve(t, { fetchImpl: async () => { calls++; return reply(proposal()); } });
  for (const invalid of [{ ...week, startDate: '2026-02-30' }, { ...week, timeZone: 'Made/Up' }, { ...week, availableDays: [0, 0] }, { ...week, availableDays: [] }, { ...week, targetDays: 4 }, { ...week, availableDays: [7] }]) {
    assert.equal((await request({ ...input, week: invalid })).status, 422);
  }
  assert.equal((await request(input, '/v1/proposal')).status, 422);
  assert.equal(calls, 0);
});

test('week provider attempts share the existing nonrefundable owner demo budget', async t => {
  let calls = 0;
  const request = await serve(t, { env: { ...env, SPOTTR_DEMO_MAX_ATTEMPTS: '1', SPOTTR_DEMO_EXPIRES_AT: '2026-10-25T10:00:00.000Z' }, fetchImpl: async () => { calls++; return reply(proposal()); } });
  assert.equal((await request()).status, 200);
  const response = await request({ generationID: 'chat', message: 'Hello' }, '/v1/chat');
  assert.equal(response.status, 429);
  assert.equal((await response.json()).error.code, 'demo_budget_exhausted');
  assert.equal(calls, 1);
});

test('weekly source links remain registry-owned and urgent declines cite chest-pain guidance', async t => {
  for (const output of [
    { ...proposal(), rationale: { ...grounded, text: 'NHS says visit https://invented.example for treatment.' } },
    { generationID: input.generationID, status: 'declined', reason: 'urgent', guidanceIDs: ['nhs-strength'] }
  ]) {
    const request = await serve(t, { fetchImpl: async () => reply(output) });
    assert.equal((await request()).status, 502);
  }
});

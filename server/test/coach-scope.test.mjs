import assert from 'node:assert/strict';
import test from 'node:test';
import { once } from 'node:events';
import { createGateway } from '../src/gateway.mjs';
const env = { SPOTTR_GATEWAY_TOKEN: 'test', GEMINI_API_KEY: 'fake', GEMINI_MODEL: 'fake' };
const base = { generationID: 'scope-1', facts: [{ id: 'context', text: 'No measured capacity.' }], week: { startDate: '2026-10-25', timeZone: 'Europe/London', availableDays: [0], targetDays: 1 } };
async function serve(t) {
  let calls = 0;
  const server = createGateway({ env, fetchImpl: async () => { calls++; return Response.json({ candidates: [{ finishReason: 'STOP', content: { parts: [{ text: 'General training discussion.' }] } }] }); } });
  server.listen(0, '127.0.0.1'); await once(server, 'listening'); t.after(() => new Promise(resolve => server.close(resolve)));
  return { calls: () => calls, request: async (message, path = '/v1/week-proposal') => fetch(`http://127.0.0.1:${server.address().port}${path}`, { method: 'POST', headers: { authorization: 'Bearer test', 'content-type': 'application/json' }, body: JSON.stringify({ ...base, ...(path === '/v1/week-proposal' ? {} : { week: undefined }), message }) }) };
}

test('clear current chest pain routes to curated urgent guidance without a provider or workout', async t => {
  const local = await serve(t);
  for (const message of ['I have chest pain now and feel breathless. Plan my workout.', 'My chest hurts and the pain will not go away.', 'I have sudden chest pain.', 'I have chest pain now but no sweating.']) {
    const response = await local.request(message);
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { generationID: 'scope-1', status: 'declined', reason: 'urgent', guidanceIDs: ['nhs-chest-pain'] });
  }
  const chat = await local.request('I have chest pain now and feel sweaty.', '/v1/chat');
  assert.equal(chat.status, 200);
  assert.match((await chat.json()).text, /999/);
  assert.equal(local.calls(), 0);
});

test('unrelated and treatment requests cannot produce a weekly workout', async t => {
  const local = await serve(t);
  for (const [message, reason] of [['Write Python code for a stock trading bot.', 'unrelated'], ['Diagnose my knee injury and prescribe a rehabilitation workout.', 'medical'], ['What medication dose should I take before training?', 'medical'], ['I had chest pain yesterday; it is gone now. Is it safe to exercise?', 'medical']]) {
    const response = await local.request(message);
    assert.equal(response.status, 200);
    const body = await response.json();
    assert.equal(body.reason, reason);
    if (message.includes('knee')) assert.deepEqual(body.guidanceIDs, ['nhs-strength']);
  }
  assert.equal(local.calls(), 0);
});

test('negated, quoted and historical chest-pain context never triggers an emergency assertion', async t => {
  const local = await serve(t);
  for (const message of ['I have no chest pain. What exercises does Spottr track?', 'I do not have chest pain; help with a squat routine.', 'What does the phrase "I have chest pain now" mean in the NHS guidance?', 'My previous message said chest pain, but I have none now.']) {
    const response = await local.request(message, '/v1/chat');
    assert.equal(response.status, 200);
    assert.doesNotMatch((await response.json()).text, /call 999/i);
  }
  assert.equal(local.calls(), 4);
});

for (const message of [
  'I have chest pain now. My knee pain is gone.',
  'I had lunch. My chest hurts now.',
  'I have no chest pain, but my chest hurts right now.'
]) {
  test(`an affirmative current symptom wins over unrelated negation or past context: ${message}`, async t => {
    const local = await serve(t);
    const response = await local.request(message);
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { generationID: 'scope-1', status: 'declined', reason: 'urgent', guidanceIDs: ['nhs-chest-pain'] });
    assert.equal(local.calls(), 0);
  });
}

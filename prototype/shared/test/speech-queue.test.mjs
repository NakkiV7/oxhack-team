import test from 'node:test';
import assert from 'node:assert/strict';

test('muting cancels playing and queued speech; an old completion cannot start another clip', async () => {
  const module = await import('../speech-queue.mjs').catch(() => ({}));
  assert.equal(typeof module.createSpeechQueue, 'function', 'A cancellable speech queue is required');
  const started = [];
  let stopped = 0;
  const queue = module.createSpeechQueue({ play: (text, done) => { started.push({ text, done }); return () => { stopped++; }; }, now: () => 0 });
  queue.say('1', 3); queue.say('2', 3);
  queue.cancel(); started[0].done();
  assert.equal(stopped, 1);
  assert.deepEqual(started.map((item) => item.text), ['1']);
  queue.say('3', 3);
  assert.deepEqual(started.map((item) => item.text), ['1', '3']);
});

test('counts expire while another clip is playing', async () => {
  const module = await import('../speech-queue.mjs').catch(() => ({}));
  assert.equal(typeof module.createSpeechQueue, 'function', 'A cancellable speech queue is required');
  let time = 0;
  const started = [];
  const queue = module.createSpeechQueue({ play: (text, done) => { started.push({ text, done }); return () => {}; }, now: () => time });
  queue.say('1', 3); queue.say('2', 3); time = 5000; started[0].done();
  assert.deepEqual(started.map((item) => item.text), ['1']);
});

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';

const directory = new URL('../../Native/Resources/DemoVoice/arnold/', import.meta.url);

test('authorized preview bank contains nine bounded clips matching actual decode receipts', async () => {
  const manifest = JSON.parse(await readFile(new URL('manifest.json', directory), 'utf8'));
  assert.equal(manifest.model, 'eleven_flash_v2_5');
  assert.equal(manifest.format, 'mp3_22050_32');
  assert.equal(manifest.purpose, 'TestFlight preview only');
  assert.equal(manifest.keyCapChanged, false);
  assert.equal(manifest.retries, 0);
  assert.equal(manifest.clips.length, 9);
  assert.equal(manifest.totalCharacters, manifest.clips.reduce((sum, clip) => sum + clip.text.length, 0));
  assert.ok(manifest.totalCharacters <= 191);
  assert.deepEqual(manifest.clips.map(clip => clip.name), ['positive-1', 'positive-2', 'slower-1', 'slower-2', 'recovery', 'positive-3', 'positive-4', 'slower-3', 'recovery-2']);
  for (const clip of manifest.clips) {
    assert.equal(clip.attempts, 1);
    assert.equal(clip.status, 200);
    assert.equal(clip.accepted, true);
    const bytes = await readFile(new URL(`${clip.name}.mp3`, directory));
    assert.equal(bytes.length, clip.bytes);
    assert.ok(bytes.length > 0 && bytes.length <= 262144);
    assert.equal(createHash('sha256').update(bytes).digest('hex'), clip.sha256);
    assert.equal(clip.decode.success, true);
    assert.equal(clip.decode.sampleRate, 22050);
    assert.ok(clip.decode.durationSeconds > 0 && clip.decode.durationSeconds <= 10);
    assert.equal(clip.decode.audiblePlayback, false);
  }
});

test('publishable provenance excludes account credentials and provider voice IDs', async () => {
  const text = await readFile(new URL('manifest.json', directory), 'utf8');
  assert.doesNotMatch(text, /xi-api-key|ELEVENLABS_API_KEY|ELEVENLABS_ARNOLD_VOICE_ID|voice_id|apiKey|sk_[A-Za-z0-9]/i);
  assert.equal(JSON.parse(text).identityClaim, false);
});

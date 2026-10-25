import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const directory = new URL('../../Native/Resources/DemoVoice/arnold/', import.meta.url);
const required = ['positive-1','positive-2','positive-3','positive-4','positive-5','slower-1','slower-2','slower-3','slower-4','recovery','recovery-2','completion','tracking','alignment','target','rest','stop'];

test('every Arnold cue decodes at audible normalized level without clipping', async () => {
  const bank = JSON.parse(await readFile(new URL('manifest.json', directory), 'utf8'));
  assert.deepEqual(bank.clips.map(c => c.name).sort(), required.sort());
  for (const clip of bank.clips) {
    const url = new URL(`${clip.name}.mp3`, directory);
    const bytes = await readFile(url);
    assert.equal(bytes.length, clip.bytes);
    assert.equal(createHash('sha256').update(bytes).digest('hex'), clip.sha256);
    const result = spawnSync('ffmpeg', ['-hide_banner','-i',fileURLToPath(url),'-af','volumedetect','-f','null','-'], {encoding:'utf8'});
    assert.equal(result.status, 0, clip.name);
    const mean = Number(/mean_volume: ([-\d.]+) dB/.exec(result.stderr)?.[1]);
    const peak = Number(/max_volume: ([-\d.]+) dB/.exec(result.stderr)?.[1]);
    assert.ok(mean >= -14, `${clip.name} too quiet: ${mean} dBFS`);
    assert.ok(peak <= -0.2, `${clip.name} clipped: ${peak} dBFS`);
    const truePeakResult = spawnSync('ffmpeg', ['-hide_banner','-i',fileURLToPath(url),'-af','ebur128=peak=true','-f','null','-'], {encoding:'utf8'});
    assert.equal(truePeakResult.status, 0);
    const truePeak = Number(/Peak:\s+([-\d.]+) dBFS/.exec(truePeakResult.stderr)?.[1]);
    assert.ok(truePeak <= -0.5, `${clip.name} lacks true peak headroom: ${truePeak} dBFS`);
    assert.equal(clip.decode.sampleRate, 22050);
    assert.ok(clip.decode.durationSeconds > 0 && clip.decode.durationSeconds <= 10);
  }
});

test('voice manifest contains no provider credentials or private voice identifiers', async () => {
  const manifest = await readFile(new URL('manifest.json', directory), 'utf8');
  assert.doesNotMatch(manifest, /xi-api-key|ELEVENLABS_API_KEY|ELEVENLABS_ARNOLD_VOICE_ID|voice_id|apiKey|sk_[A-Za-z0-9]/i);
});

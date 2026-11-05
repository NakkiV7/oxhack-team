import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

test('both original coaches have complete offline recordings for every coaching style', async () => {
  const counts = { discomfort: 1, tracking: 2, alignment: 2, targetReached: 2,
    restReminder: 3, workoutCompleted: 3, slowerRep: 3, steadyRhythm: 8 };
  for (const coach of ['maya', 'leo']) {
    const directory = new URL(`../../Native/Resources/DemoVoice/${coach}/`, import.meta.url);
    const raw = await readFile(new URL('manifest.json', directory), 'utf8');
    assert.doesNotMatch(raw, /xi-api-key|ELEVENLABS_API_KEY|voice_id|apiKey|sk_[A-Za-z0-9]/i);
    const manifest = JSON.parse(raw);
    const expected = ['gentle', 'encouraging', 'direct'].flatMap(tone =>
      Object.entries(counts).flatMap(([reason, count]) =>
        Array.from({ length: count }, (_, index) => `${tone}/${reason}-${index + 1}`)));
    assert.deepEqual(manifest.clips.map(clip => clip.name).sort(), expected.sort());
    for (const clip of manifest.clips) {
      const url = new URL(`${clip.name}.mp3`, directory);
      const bytes = await readFile(url);
      assert.equal(bytes.length, clip.bytes);
      assert.equal(createHash('sha256').update(bytes).digest('hex'), clip.sha256);
      const probe = spawnSync('ffprobe', ['-v', 'error', '-show_entries',
        'stream=sample_rate,channels:format=duration', '-of', 'json', fileURLToPath(url)], { encoding: 'utf8' });
      assert.equal(probe.status, 0, clip.name);
      const decoded = JSON.parse(probe.stdout);
      assert.equal(Number(decoded.streams[0].sample_rate), 22050);
      assert.equal(decoded.streams[0].channels, 1);
      assert.ok(Number(decoded.format.duration) > 0 && Number(decoded.format.duration) <= 12, clip.name);
      const volume = spawnSync('ffmpeg', ['-hide_banner', '-i', fileURLToPath(url),
        '-af', 'volumedetect', '-f', 'null', '-'], { encoding: 'utf8' });
      assert.equal(volume.status, 0, clip.name);
      const mean = Number(/mean_volume: ([-\d.]+) dB/.exec(volume.stderr)?.[1]);
      const peak = Number(/max_volume: ([-\d.]+) dB/.exec(volume.stderr)?.[1]);
      assert.ok(mean >= -19 && mean <= -10, `${clip.name} level ${mean}`);
      assert.ok(peak <= -0.5, `${clip.name} peak ${peak}`);
    }
  }
});

test('tracking and alignment recordings use view and quantity neutral transcripts', async () => {
  const expected = {
    'tracking-1': 'I lost sight of the movement. Your progress is saved. Move back into view when you are ready.',
    'tracking-2': 'Your progress is safe. Give the camera a clear view of the movement so we can continue.',
    'alignment-1': 'Check your starting position. Keep the movement comfortable and controlled.'
  };
  for (const coach of ['maya', 'leo']) {
    const manifest = JSON.parse(await readFile(new URL(`../../Native/Resources/DemoVoice/${coach}/manifest.json`, import.meta.url), 'utf8'));
    for (const clip of manifest.clips) {
      const text = expected[clip.name.split('/')[1]];
      if (text) assert.equal(clip.text, text);
    }
  }
});

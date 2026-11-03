import { readFile } from 'node:fs/promises';

const root = new URL('../../Native/Resources/DemoVoice/', import.meta.url);
const coaches = ['arnold', 'goggins'];

export async function bundledVoices() {
  return Promise.all(coaches.map(async (coach) => {
    const manifest = JSON.parse(await readFile(new URL(`${coach}-reps/manifest.json`, root), 'utf8'));
    return {
      id: `offline-${coach}`, name: `${coach === 'arnold' ? 'Arnold' : 'Goggins'} · offline`, offline: true,
      clips: manifest.clips.map(({ name, text }) => ({ name, text })),
    };
  }));
}

export async function bundledSpeech(voice, text) {
  const coach = coaches.find((name) => voice === `offline-${name}`);
  if (!coach) return null;
  const options = await bundledVoices();
  const clip = options.find((item) => item.id === voice)?.clips.find((item) => item.text === text);
  if (!clip || !/^(count-\d{2}|motivate-[1-7]|closing-[1-3]|start)$/.test(clip.name)) return null;
  return readFile(new URL(`${coach}-reps/${clip.name}.mp3`, root));
}

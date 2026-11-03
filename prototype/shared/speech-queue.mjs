export function createSpeechQueue({ play, now = () => performance.now() }) {
  let pending = [];
  let current = null;
  let generation = 0;
  let lastSaid = new Map();
  const pump = () => {
    if (current) return;
    pending = pending.filter((item) => now() - item.time < 4000);
    const next = [...pending].sort((a, b) => b.priority - a.priority || a.time - b.time)[0];
    if (!next) return;
    pending = pending.filter((item) => item !== next);
    const token = ++generation;
    current = { token, cancel: () => {} };
    const cancel = play(next.text, () => {
      if (current?.token !== token) return;
      current = null; pump();
    }, next.tone);
    if (current?.token === token) current.cancel = cancel;
  };
  return {
    say(text, priority = 2, tone = 'calm') {
      if (!text) return;
      const time = now();
      if (!/^\d+$/.test(text) && time - (lastSaid.get(text) ?? -Infinity) < 8000) return;
      if (pending.some((item) => item.text === text)) return;
      lastSaid.set(text, time);
      pending = [...pending, { text, priority, tone, time }].slice(-8);
      pump();
    },
    cancel() {
      const cancel = current?.cancel;
      generation++; current = null; pending = []; lastSaid = new Map();
      cancel?.();
    },
  };
}

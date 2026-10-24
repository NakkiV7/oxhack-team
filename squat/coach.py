"""Cue channel: one voice at a time, never cut off, queued cues wait, a more urgent fault can pre-empt."""
from typing import Callable


class Coach:
    def __init__(self, speak: Callable[[str], None] = print, cooldown: float = 5.0):
        self.speak = speak                 # swap for ElevenLabs TTS later; must be non-blocking
        self.cooldown = cooldown
        self.queue: list[tuple[int, float, str]] = []   # (priority, time queued, text)
        self.current, self.priority, self.busy_until = "", 0, 0.0
        self.last_said: dict[str, float] = {}

    def handle(self, events: list[tuple[int, str]], t: float) -> None:
        for prio, text in events:
            recent = t - self.last_said.get(text, -1e9) < self.cooldown and not text.isdigit()
            if recent or any(q[2] == text for q in self.queue):
                continue
            self.queue.append((prio, t, text))
            self.last_said[text] = t
        self.queue = [q for q in self.queue if q[0] >= 3 or t - q[1] < 3.0]   # stale low-priority cues expire
        if not self.queue:
            return
        nxt = max(self.queue, key=lambda q: (q[0], -q[1]))   # most urgent, then oldest
        if t >= self.busy_until or nxt[0] > self.priority:
            self.queue.remove(nxt)
            self.current, self.priority = nxt[2], nxt[0]
            self.busy_until = t + 0.35 * len(nxt[2].split()) + 0.6   # rough speech duration
            self.speak(nxt[2])

    def showing(self, t: float) -> str:
        return self.current if t < self.busy_until + 0.8 else ""

"""Cue channel: one voice, never interrupted, higher-priority faults can pre-empt, repeats are rate-limited."""
from typing import Callable


class Coach:
    def __init__(self, speak: Callable[[str], None] = print, cooldown: float = 5.0):
        self.speak = speak            # swap for ElevenLabs TTS later; must be non-blocking
        self.cooldown = cooldown
        self.current = ""             # text being "spoken" (shown on HUD)
        self.priority = 0
        self.busy_until = 0.0
        self.last_said: dict[str, float] = {}

    def handle(self, events: list[tuple[int, str]], t: float) -> None:
        for prio, text in sorted(events, reverse=True):
            if t - self.last_said.get(text, -1e9) < self.cooldown and not text.isdigit():
                continue                                     # same cue too recently
            if t < self.busy_until and prio <= self.priority:
                continue                                     # channel busy with something as important
            self.current, self.priority = text, prio
            self.busy_until = t + 0.35 * len(text.split()) + 0.6   # rough speech duration
            self.last_said[text] = t
            self.speak(text)
            return                                           # one cue per frame

    def showing(self, t: float) -> str:
        return self.current if t < self.busy_until + 0.8 else ""

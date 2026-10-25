"""On-demand macOS or ElevenLabs speech, cached by voice/model/text and played with afplay."""
import hashlib
import json
import os
import ssl
import subprocess
import urllib.request
from pathlib import Path

import certifi

CACHE = Path(__file__).with_name("voice_cache")
DEFAULT_VOICE = "21m00Tcm4TlvDq8ikWAM"      # ElevenLabs "Rachel", a standard voice
MODEL = "eleven_turbo_v2_5"
STANDARD_LINES = [str(n) for n in range(1, 31)] + ["Go", "Set complete. Nice work"]


def load_env():
    env = Path(__file__).with_name(".env")
    if env.exists():
        for line in env.read_text().splitlines():
            if "=" in line and not line.lstrip().startswith("#"):
                k, v = line.split("=", 1)
                os.environ.setdefault(k.strip(), v.strip())


def synth(text: str, backend: str, path: Path) -> None:
    if backend == "say":
        subprocess.run(["say", "-v", "Daniel", "-o", str(path), "--data-format=LEI16@24000", text], check=True)
        return
    req = urllib.request.Request(
        f"https://api.elevenlabs.io/v1/text-to-speech/{os.environ.get('ELEVENLABS_VOICE_ID', DEFAULT_VOICE)}",
        data=json.dumps({"text": text, "model_id": MODEL}).encode(),
        headers={"xi-api-key": os.environ["ELEVENLABS_API_KEY"], "Content-Type": "application/json"},
    )
    ctx = ssl.create_default_context(cafile=certifi.where())   # python.org builds ship without a CA bundle
    path.write_bytes(urllib.request.urlopen(req, timeout=30, context=ctx).read())


class Voice:
    """First uncached synthesis blocks; playback starts a separate audio process."""

    def __init__(self, backend: str = "say", lines=STANDARD_LINES):
        self.backend = backend
        load_env()
        CACHE.mkdir(exist_ok=True)

    def path(self, text: str) -> Path:
        identity = f"{os.environ.get('ELEVENLABS_VOICE_ID', DEFAULT_VOICE)}:{MODEL}" if self.backend == "elevenlabs" else "Daniel"
        digest = hashlib.sha256(f"{identity}:{text}".encode()).hexdigest()
        p = CACHE / f"{self.backend}_{digest}.{'wav' if self.backend == 'say' else 'mp3'}"
        if not p.exists():
            synth(text, self.backend, p)
        return p

    def __call__(self, text: str) -> None:
        print(text)
        subprocess.Popen(["afplay", str(self.path(text))], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

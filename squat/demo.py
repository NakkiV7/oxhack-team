"""Add a spoken cue track to an annotated tracker video and re-encode it as a shareable H.264 mp4.

Usage: python demo.py --video annotated.mp4 --log reps.json --out demo.mp4 [--voice say|elevenlabs]

`say` uses the free macOS voice (iterate with this). `elevenlabs` reads ELEVENLABS_API_KEY and optional
ELEVENLABS_VOICE_ID from the environment or squat/.env; each distinct cue is synthesised once.
"""
import argparse
import json
import subprocess
import tempfile
from pathlib import Path

import cv2
import imageio_ffmpeg
import numpy as np

from voice import load_env, synth

FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()
RATE = 24000


def pcm(path: str) -> np.ndarray:
    """Any audio file -> int16 mono at RATE."""
    cmd = [FFMPEG, "-v", "error", "-i", path, "-f", "s16le", "-ac", "1", "-ar", str(RATE), "-"]
    return np.frombuffer(subprocess.run(cmd, capture_output=True, check=True).stdout, np.int16)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--video", required=True)
    ap.add_argument("--log", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--voice", default="say", choices=["say", "elevenlabs"])
    args = ap.parse_args()
    load_env()

    cap = cv2.VideoCapture(args.video)
    duration = cap.get(cv2.CAP_PROP_FRAME_COUNT) / (cap.get(cv2.CAP_PROP_FPS) or 30)
    cues = json.load(open(args.log))["cues"]
    track = np.zeros(int((duration + 2) * RATE), np.int16)
    clips: dict[str, np.ndarray] = {}
    with tempfile.TemporaryDirectory() as tmp:
        for t, text in cues:
            if text not in clips:
                path = f"{tmp}/{len(clips)}.{'wav' if args.voice == 'say' else 'mp3'}"
                synth(text, args.voice, Path(path))
                clips[text] = pcm(path)
            a, i = clips[text], int(t * RATE)
            track[i:i + len(a)] = a[: len(track) - i]
        wav = f"{tmp}/track.wav"
        subprocess.run([FFMPEG, "-v", "error", "-y", "-f", "s16le", "-ar", str(RATE), "-ac", "1", "-i", "-", wav],
                       input=track.tobytes(), check=True)
        subprocess.run([FFMPEG, "-v", "error", "-y", "-i", args.video, "-i", wav, "-c:v", "libx264", "-pix_fmt", "yuv420p",
                        "-crf", "20", "-c:a", "aac", "-shortest", args.out], check=True)
    print(f"{args.out}: {len(cues)} cues, {len(clips)} distinct lines synthesised with {args.voice}")


if __name__ == "__main__":
    main()

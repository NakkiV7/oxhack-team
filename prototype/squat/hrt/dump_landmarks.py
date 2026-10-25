"""Dump MediaPipe pose landmarks of a clip to the JSON shape hrt/build_dataset.mjs reads.

    ../.venv/bin/python hrt/dump_landmarks.py <clip.mp4|.webm|.mov> [<more clips>] --out <dir>

One JSON per clip: { "fps", "width", "height", "frames": [[x, y, z, visibility] x 33 | null] }, normalized coordinates
exactly as the browser receives them, so the offline rep counter sees what the page would see. Uses the Python reference
wrapper (squat/pose.py at the repository root, pose_landmarker_full). Rotated phone clips are handled by OpenCV's
orientation flag. Run from prototype/squat.
"""
import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "squat"))
import cv2  # noqa: E402
from pose import Pose  # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument("clips", nargs="+")
ap.add_argument("--out", required=True)
args = ap.parse_args()
out = Path(args.out)
out.mkdir(parents=True, exist_ok=True)

for clip in args.clips:
    cap = cv2.VideoCapture(clip)
    if not cap.isOpened():
        print(f"skip {clip}: cannot open", file=sys.stderr)
        continue
    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    pose = Pose()
    frames, w, h, i = [], None, None, 0
    while True:
        ok, bgr = cap.read()
        if not ok:
            break
        h, w = bgr.shape[:2]
        lm = pose(bgr, int(round(i * 1000 / fps)))
        frames.append(None if lm is None else [[float(p[0] / w), float(p[1] / h), float(p[2] / w), float(p[3])] for p in lm])
        i += 1
    pose.close()
    cap.release()
    name = Path(clip).stem
    (out / f"{name}.json").write_text(json.dumps({"fps": fps, "width": w, "height": h, "frames": frames}))
    seen = sum(f is not None for f in frames)
    print(f"{name}: {i} frames at {fps:.2f} fps, pose in {seen} ({w}x{h}) -> {out / (name + '.json')}")

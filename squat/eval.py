"""Run the analyzer over every clip in a folder; print reps, dips and a hip-travel trace per clip.

Usage: python eval.py CLIP_DIR [--model full] [--plots OUT_DIR]
"""
import argparse
import sys
import time
from pathlib import Path

import cv2
import numpy as np

from analyzer import SquatAnalyzer
from pose import MODELS, Pose

BARS = " ▁▂▃▄▅▆▇█"


def run(path: Path, model: str):
    cap, pose, an = cv2.VideoCapture(str(path)), Pose(MODELS[model]), SquatAnalyzer()
    fps = cap.get(cv2.CAP_PROP_FPS) or 30
    trace, marks, n, t0 = [], [], 0, time.time()
    while True:
        ok, img = cap.read()
        if not ok:
            break
        lm = pose(img, int(n * 1000 / fps))
        if lm is not None:
            before = len(an.reps)
            f = an.update(lm, n / fps)
            trace.append(f.drop)
            if len(an.reps) > before:
                marks.append(n)
        else:
            trace.append(np.nan)
        n += 1
    pose.close()
    return an, np.array(trace), marks, n, n / (time.time() - t0)


def spark(trace, width=80):
    t = np.nan_to_num(trace, nan=0.0)
    bins = np.array_split(t, width)
    return "".join(BARS[int(np.clip(b.max() / 0.7, 0, 1) * (len(BARS) - 1))] if len(b) else " " for b in bins)


def plot(trace, marks, path: Path):
    h, w = 200, max(400, len(trace))
    img = np.full((h, w, 3), 255, np.uint8)
    for y in (0.08, 0.15, 0.22, 0.5):                       # END, START, MIN_DROP, ~parallel
        cv2.line(img, (0, int(h - y * h / 0.8)), (w, int(h - y * h / 0.8)), (200, 200, 200), 1)
    pts = [(i, int(h - np.clip(v, 0, 0.8) * h / 0.8)) for i, v in enumerate(trace) if not np.isnan(v)]
    cv2.polylines(img, [np.array(pts)], False, (180, 60, 0), 1)
    for m in marks:
        cv2.line(img, (m, 0), (m, h), (0, 160, 0), 1)
    cv2.imwrite(str(path), img)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dir")
    ap.add_argument("--model", default="full", choices=list(MODELS))
    ap.add_argument("--plots", help="write a hip-travel plot per clip here")
    args = ap.parse_args()
    clips = sorted(p for p in Path(args.dir).iterdir() if p.suffix.lower() in (".webm", ".mp4", ".mov", ".ogv", ".m4v"))
    for p in clips:
        an, trace, marks, n, fps = run(p, args.model)
        print(f"{p.name:34s} reps {len(an.reps):2d} dips {an.dips:2d}  {n:5d}f {fps:4.0f}fps  {spark(trace)}")
        for r in an.reps:
            print(f"    #{r.n:<2} drop {r.drop:.2f} depth {r.worst['depth']:+.2f} lean {r.worst['lean']:3.0f}"
                  f"  {r.t_down:.1f}/{r.t_up:.1f}s  {', '.join(r.faults) or 'clean'}")
        if args.plots:
            Path(args.plots).mkdir(exist_ok=True)
            plot(trace, marks, Path(args.plots) / f"{p.stem}.png")
        sys.stdout.flush()


if __name__ == "__main__":
    main()

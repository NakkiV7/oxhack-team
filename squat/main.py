"""Squat form tracker. Usage: python main.py [--source 0|video.mp4] [--out out.mp4] [--log reps.json] [--headless]"""
import argparse
import json
import time

import cv2
import numpy as np

from analyzer import SquatAnalyzer
from coach import Coach
from panel import COLOUR, panel, text
from pose import L_ANK, L_HIP, L_KNEE, L_SHO, Pose, R_ANK, R_HIP, R_KNEE, R_SHO

SEGMENTS = {  # skeleton segment -> landmark pairs, coloured by the analyzer's grade for that segment
    "torso": [(L_SHO, R_SHO), (L_SHO, L_HIP), (R_SHO, R_HIP), (L_HIP, R_HIP)],
    "thigh": [(L_HIP, L_KNEE), (R_HIP, R_KNEE)],
    "shin": [(L_KNEE, L_ANK), (R_KNEE, R_ANK)],
}


def draw(img, lm, f, cue):
    pt = lambda i: tuple(lm[i][:2].astype(int))
    for name, pairs in SEGMENTS.items():
        for a, b in pairs:
            cv2.line(img, pt(a), pt(b), COLOUR[f.segments[name]], 4)
    if f.view == "front":
        cv2.line(img, pt(L_KNEE), pt(R_KNEE), COLOUR[f.segments["knees"]], 2)
    for i in (L_SHO, R_SHO, L_HIP, R_HIP, L_KNEE, R_KNEE, L_ANK, R_ANK):
        cv2.circle(img, pt(i), 6, (255, 255, 255), -1)
    if cue:
        text(img, cue, (20, img.shape[0] - 30), 1.0, (255, 255, 255), 2, cv2.FONT_HERSHEY_DUPLEX)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", default="0", help="camera index or video path")
    ap.add_argument("--out", help="write annotated video here")
    ap.add_argument("--log", help="write per-rep JSON here")
    ap.add_argument("--headless", action="store_true", help="no window (CI / remote)")
    args = ap.parse_args()

    live = args.source.isdigit()
    cap = cv2.VideoCapture(int(args.source) if live else args.source)
    if not cap.isOpened():
        raise SystemExit(f"cannot open {args.source!r}" + (" (grant camera access to your terminal app)" if live else ""))
    fps = cap.get(cv2.CAP_PROP_FPS) or 30
    pose, analyzer, coach = Pose(), SquatAnalyzer(), Coach()
    writer, f, n, t0 = None, None, 0, time.time()

    while True:
        ok, img = cap.read()
        if not ok:
            break
        t = time.time() - t0 if live else n / fps
        lm = pose(img, int(t * 1000))
        if lm is not None:
            f = analyzer.update(lm, t)
            coach.handle(f.events, t)
            draw(img, lm, f, coach.showing(t))
        if f:
            img = np.hstack([img, panel(f, img.shape[0])])
        if args.out:
            writer = writer or cv2.VideoWriter(args.out, cv2.VideoWriter_fourcc(*"mp4v"), fps, img.shape[1::-1])
            writer.write(img)
        if not args.headless:
            cv2.imshow("squat tracker", img)
            if cv2.waitKey(1) & 0xFF in (27, ord("q")):
                break
        n += 1

    reps = analyzer.reps
    print(f"\n{n} frames, {len(reps)} reps")
    for r in reps:
        print(f"#{r.n:<3} depth {r.worst['depth']:3.0f}  down {r.t_down:.2f}s  up {r.t_up:.2f}s  {', '.join(r.faults) or 'clean'}")
    if args.log:
        json.dump([vars(r) for r in reps], open(args.log, "w"), indent=1, default=float)
    cap.release(), pose.close()
    if writer:
        writer.release()


if __name__ == "__main__":
    main()

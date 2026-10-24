"""Squat form demo. Usage: python main.py [--source 0|video.mp4] [--out out.mp4] [--headless]"""
import argparse
import time

import cv2

from analyzer import SquatAnalyzer
from coach import Coach
from pose import L_ANK, L_HIP, L_KNEE, L_SHO, Pose, R_ANK, R_HIP, R_KNEE, R_SHO

COLOUR = {0: (80, 200, 80), 1: (0, 170, 255), 2: (40, 40, 255)}  # BGR green / amber / red
SEGMENTS = {  # name -> landmark pairs
    "torso": [(L_SHO, R_SHO), (L_SHO, L_HIP), (R_SHO, R_HIP), (L_HIP, R_HIP)],
    "thigh": [(L_HIP, L_KNEE), (R_HIP, R_KNEE)],
    "shin": [(L_KNEE, L_ANK), (R_KNEE, R_ANK)],
}


def draw(img, lm, f, cue):
    for name, pairs in SEGMENTS.items():
        for a, b in pairs:
            cv2.line(img, tuple(lm[a][:2].astype(int)), tuple(lm[b][:2].astype(int)), COLOUR[f.segments[name]], 4)
    if f.view == "front":
        cv2.line(img, tuple(lm[L_KNEE][:2].astype(int)), tuple(lm[R_KNEE][:2].astype(int)), COLOUR[f.segments["knees"]], 2)
    for p in (L_SHO, R_SHO, L_HIP, R_HIP, L_KNEE, R_KNEE, L_ANK, R_ANK):
        cv2.circle(img, tuple(lm[p][:2].astype(int)), 6, (255, 255, 255), -1)
    cv2.putText(img, f"{f.reps}", (20, 70), cv2.FONT_HERSHEY_DUPLEX, 2.2, (255, 255, 255), 3)
    cv2.putText(img, f"knee {f.knee:3.0f}  lean {f.lean:2.0f}  {f.view} {f.state}", (20, 100),
                cv2.FONT_HERSHEY_SIMPLEX, 0.6, (220, 220, 220), 1)
    if cue:
        cv2.putText(img, cue, (20, img.shape[0] - 30), cv2.FONT_HERSHEY_DUPLEX, 1.0, (255, 255, 255), 2)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", default="0", help="camera index or video path")
    ap.add_argument("--out", help="write annotated video here")
    ap.add_argument("--headless", action="store_true", help="no window (CI / remote)")
    args = ap.parse_args()

    live = args.source.isdigit()
    cap = cv2.VideoCapture(int(args.source) if live else args.source)
    fps = cap.get(cv2.CAP_PROP_FPS) or 30
    pose, analyzer, coach = Pose(), SquatAnalyzer(), Coach()
    writer, n, t0 = None, 0, time.time()

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
        if args.out:
            writer = writer or cv2.VideoWriter(args.out, cv2.VideoWriter_fourcc(*"mp4v"), fps, img.shape[1::-1])
            writer.write(img)
        if not args.headless:
            cv2.imshow("squat", img)
            if cv2.waitKey(1) & 0xFF in (27, ord("q")):
                break
        n += 1

    print(f"frames {n}  reps {analyzer.reps}  ascent times {[round(a, 2) for a in analyzer.ascents]}")
    cap.release(), pose.close()
    if writer:
        writer.release()


if __name__ == "__main__":
    main()

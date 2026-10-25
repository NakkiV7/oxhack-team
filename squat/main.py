"""Form tracker for squats and push-ups.

Usage: python main.py [--exercise squat|pushup] [--source 0|video.mp4] [--model full] [--out annotated.mp4] [--record raw.mp4] [--log reps.json] [--headless]
"""
import argparse
import importlib
import json
import time

import cv2
import numpy as np

from coach import Coach
from voice import STANDARD_LINES, Voice
from panel import BG, COLOUR, W, panel, text
from pose import MODELS, Pose

def draw(img, lm, f, cue, ex):
    pt = lambda i: tuple(lm[i][:2].astype(int))
    for a, b, g, thick in ex.segments(f, lm):
        cv2.line(img, pt(a), pt(b), COLOUR[g], thick)
    for i in (ex.joints(f) if hasattr(ex, "joints") else ex.JOINTS):
        cv2.circle(img, pt(i), 6, (255, 255, 255) if lm[i][3] >= 0.5 else (0, 0, 255), -1)
    if cue:
        text(img, cue, (20, img.shape[0] - 30), 1.0, (255, 255, 255), 2, cv2.FONT_HERSHEY_DUPLEX)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--exercise", default="squat", choices=["squat", "pushup"])
    ap.add_argument("--source", default="0", help="camera index or video path")
    ap.add_argument("--model", default="full", choices=list(MODELS))
    ap.add_argument("--out", help="write annotated video here")
    ap.add_argument("--record", help="write the raw camera feed here (to share a failing session)")
    ap.add_argument("--log", help="write reps and timed cues as JSON here")
    ap.add_argument("--caption", help="small caption burnt into the video (e.g. footage credit)")
    ap.add_argument("--headless", action="store_true", help="no window (CI / remote)")
    ap.add_argument("--voice", default="off", choices=["off", "say", "elevenlabs"], help="speak cues aloud")
    args = ap.parse_args()
    ex = importlib.import_module(args.exercise)

    live = args.source.isdigit()
    cap = cv2.VideoCapture(int(args.source) if live else args.source)
    if not cap.isOpened():
        raise SystemExit(f"cannot open {args.source!r}" + (" (grant camera access to your terminal app)" if live else ""))
    fps = cap.get(cv2.CAP_PROP_FPS) or 30
    pose, analyzer = Pose(MODELS[args.model]), ex.Analyzer()
    coach = Coach(speak=Voice(args.voice, STANDARD_LINES + ex.LINES) if args.voice != "off" else print)
    writers, f, n, t0 = {}, None, 0, time.time()

    def write(key, path, img):
        if path:
            w = writers.get(key) or cv2.VideoWriter(path, cv2.VideoWriter_fourcc(*"mp4v"), fps, img.shape[1::-1])
            writers[key] = w
            w.write(img)

    try:
        while True:
            ok, img = cap.read()
            if not ok:
                break
            write("raw", args.record, img)
            t = time.time() - t0 if live else n / fps
            lm = pose(img, int(t * 1000))
            if lm is not None:
                f = analyzer.update(lm, t, img.shape[0])
                coach.handle(f.events, t)
                draw(img, lm, f, coach.showing(t), ex)
            if args.caption:
                text(img, args.caption, (10, 18), 0.45, (200, 200, 200))
            img = np.hstack([img, panel(f, img.shape[0], ex) if f else np.full((img.shape[0], W, 3), BG, np.uint8)])
            write("out", args.out, img)
            if not args.headless:
                cv2.imshow("squat tracker", img)
                if cv2.waitKey(1) & 0xFF in (27, ord("q")) or cv2.getWindowProperty("squat tracker", cv2.WND_PROP_VISIBLE) < 1:
                    break
            n += 1
    except KeyboardInterrupt:
        pass
    finally:
        for w in writers.values():          # unfinished mp4s are unreadable, so always finalise them
            w.release()

    reps = analyzer.reps
    print(f"\n{n} frames, {len(reps)} reps, {analyzer.dips} shallow dips not counted")
    for r in reps:
        print(f"#{r.n:<3} travel {r.drop:.2f}  down {r.t_down:.2f}s  up {r.t_up:.2f}s  {', '.join(r.faults) or 'clean'}")
    if args.log:
        json.dump({"reps": [vars(r) for r in reps], "cues": coach.history}, open(args.log, "w"), indent=1, default=float)
    cap.release(), pose.close()


if __name__ == "__main__":
    main()

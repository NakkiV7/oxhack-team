"""Side panel: reps, primary travel bar, live metric bars, tempo, fault tally and rep log. Pure OpenCV drawing."""
from collections import Counter

import cv2
import numpy as np

W = 360
COLOUR = {0: (80, 200, 80), 1: (0, 170, 255), 2: (40, 40, 255), None: (90, 90, 90)}   # BGR green/amber/red/off
BG, FG, DIM = (24, 24, 24), (235, 235, 235), (140, 140, 140)
FONT = cv2.FONT_HERSHEY_SIMPLEX


def text(img, s, xy, scale=0.5, colour=FG, thick=1, font=FONT):
    cv2.putText(img, s, xy, font, scale, colour, thick, cv2.LINE_AA)


def bar(p, y, frac, colour, ticks=()):
    cv2.rectangle(p, (105, y - 8), (305, y + 8), (50, 50, 50), -1)
    cv2.rectangle(p, (105, y - 8), (105 + int(200 * np.clip(frac, 0, 1)), y + 8), colour, -1)
    for f in ticks:
        x = 105 + int(200 * np.clip(f, 0, 1))
        cv2.line(p, (x, y - 10), (x, y + 10), FG, 1)


def fmt(k, v):
    return f"{v:+.2f}" if k in ("depth", "hip") else f"{v:.2f}" if k == "knees" else f"{v:.0f}"


def panel(f, h: int, ex) -> np.ndarray:
    """ex is the exercise module: METRICS, RANGE, PRIMARY."""
    p = np.full((h, W, 3), BG, np.uint8)
    text(p, str(len(f.reps)), (20, 64), 2.2, FG, 3, cv2.FONT_HERSHEY_DUPLEX)
    text(p, "REPS", (105, 64), 0.7, DIM)
    text(p, f"{f.view} view  |  {f.state}" + (f"  |  {f.dips} not counted" if f.dips else ""), (20, 92), 0.5, DIM)
    if f.warn:
        text(p, f.warn[:46], (20, 116), 0.5, COLOUR[1])

    y = 140
    label, scale, ticks = ex.PRIMARY
    text(p, label, (20, y + 5), 0.5, FG)
    bar(p, y, f.drop / scale, (200, 160, 60), ticks=[t / scale for t in ticks])
    text(p, f"{f.drop:.2f}", (312, y + 5), 0.45, FG)
    y += 32
    for k, (label, (good, warn), *_) in ex.METRICS.items():
        v, g = f.live[k]
        lo, hi = ex.RANGE[k]
        text(p, label, (20, y + 5), 0.5, FG if g is not None else DIM)
        if g is not None:
            bar(p, y, (v - lo) / (hi - lo), COLOUR[g], ticks=[(t - lo) / (hi - lo) for t in (good, warn)])
            text(p, fmt(k, v), (312, y + 5), 0.45, FG)
        else:
            bar(p, y, 0, COLOUR[None])
            text(p, "n/a", (312, y + 5), 0.45, DIM)
        y += 32

    text(p, f"tempo  down {f.t_down:.1f}s   up {f.t_up:.1f}s", (20, y + 8), 0.5, FG)
    y += 40
    tally = Counter(fault for r in f.reps for fault in r.faults)
    text(p, "FAULTS", (20, y), 0.45, DIM)
    text(p, "   ".join(f"{k} x{n}" for k, n in tally.most_common(3)) or "none yet", (85, y), 0.45, FG)
    y += 30
    text(p, "REP LOG", (20, y), 0.45, DIM)
    y += 22
    for r in f.reps[-max(1, (h - y) // 22):]:
        cv2.circle(p, (28, y - 5), 6, COLOUR[r.grade], -1)
        text(p, f"#{r.n:<3}{r.t_down:.1f}/{r.t_up:.1f}s  {', '.join(r.faults) or 'clean'}", (44, y), 0.42, FG)
        y += 22
    return p

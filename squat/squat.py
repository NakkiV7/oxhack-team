"""Squat: rep counting on hip travel, depth / lean / knee / balance grades, coaching events.

Rep signal is vertical hip travel as a fraction of standing leg length (view independent). The knee angle
only confirms a descent, so walking toward the camera is not a rep. Shallow dips are recorded, not counted.
"""
import numpy as np

from common import AMBER, GREEN, RED, Frame, Rep, angle, grade
from pose import L_ANK, L_HIP, L_KNEE, L_SHO, R_ANK, R_HIP, R_KNEE, R_SHO

NAME, EXAMPLE, TARGET = "Squat", "example_side.mp4", 8
HINT = "side-on, 2-3 m away, feet in frame"
VIS = 0.5                        # landmark visibility needed to trust a joint
ALPHA = 0.5                      # EMA on measured signals (landmarks jitter frame to frame)
START, END = 0.15, 0.08          # hip drop (fraction of leg length) that starts / ends a rep
MIN_DROP = 0.22                  # smaller max drop = a dip: recorded, not counted
MIN_DUR, MAX_DUR = 0.5, 15.0
FAST_DESCENT_S, SLOW_ASCENT_S = 0.45, 2.2

# name: (label, (good, warn), view it is valid in, fault name, cue). Tune vs UI-PRMD / Fitness-AQA.
METRICS = {
    "depth":   ("Depth",   (-0.10, -0.35), "both",  "shallow",      "Deeper. Hips to knee height"),  # (hip_y-knee_y)/thigh
    "lean":    ("Lean",    (40, 55),       "side",  "forward lean", "Chest up"),                      # torso from vertical
    "knees":   ("Knees",   (0.85, 0.70),   "front", "knees in",     "Knees out"),                     # knee / ankle width
    "balance": ("Balance", (12, 18),       "front", "uneven",       "Even weight on both feet"),      # hip vs shoulder tilt
}
AGG = {"depth": max, "lean": max, "knees": min, "balance": max}   # how each metric accumulates over a rep
SMOOTHED = ("hip_y", "knee_y", "thigh", "height", "knee", "knee_max", "lean", "knees", "balance")






class SquatAnalyzer:
    def __init__(self):
        self.reps: list[Rep] = []
        self.dips = 0
        self.state = "standing"
        self.s: dict | None = None           # smoothed signals
        self.base: dict | None = None        # standing reference: hip_y, leg, thigh
        self.cur: dict = {}
        self.max_drop = 0.0
        self.t_start = self.t_bottom = self.lost = 0.0
        self.recent: list[tuple[float, float]] = []    # (t, drop) over the last 3 s
        self.facing, self._view = 1.0, "front"

    def view(self, lm) -> str:
        sho, hip = (lm[L_SHO] + lm[R_SHO]) / 2, (lm[L_HIP] + lm[R_HIP]) / 2
        ratio = abs(lm[L_SHO][0] - lm[R_SHO][0]) / (np.linalg.norm(sho[:2] - hip[:2]) + 1e-6)
        self.facing = 0.9 * self.facing + 0.1 * ratio
        if self.facing > 0.5:
            self._view = "front"
        elif self.facing < 0.35:
            self._view = "side"
        return self._view

    @staticmethod
    def measure(lm, view: str, h: float) -> dict:
        vis = lm[:, 3]
        legs = [(lm[L_HIP + s], lm[L_KNEE + s], lm[L_ANK + s]) for s in (0, 1)]
        seen = [min(k[3], a[3]) >= VIS for _, k, a in legs]            # MediaPipe extrapolates joints just off-frame
        side = 0 if min(vis[L_HIP], vis[L_KNEE], vis[L_ANK]) >= min(vis[R_HIP], vis[R_KNEE], vis[R_ANK]) else 1
        hip, knee, ank = legs[side]                                       # best-seen leg (a side view hides one)
        sho = (lm[L_SHO] + lm[R_SHO]) / 2
        feet = seen[side]
        knees_in = max(lm[L_KNEE][1], lm[R_KNEE][1]) < 1.05 * h           # knee metrics need real, in-frame joints
        feet_in = max(lm[L_ANK][1], lm[R_ANK][1]) < 1.05 * h
        angles = [angle(*leg) for leg, ok in zip(legs, seen) if ok]       # 2D: a straight leg is collinear from any view
        thigh = float(np.linalg.norm(hip[:2] - knee[:2]))
        up = sho[:2] - hip[:2]
        tilt = lambda a, b: np.degrees(np.arctan2(abs(a[1] - b[1]), abs(a[0] - b[0]) + 1e-6))
        return {
            "hips_ok": min(hip[3], knee[3]) >= VIS and 0 < hip[1] < 1.1 * h,   # a hallucinated hip below the frame is not a squat
            "feet_ok": feet, "knees_in": knees_in, "feet_in": feet_in,
            "hip_y": float(hip[1]), "knee_y": float(knee[1]), "thigh": thigh,
            "height": float(ank[1] - hip[1]) if feet else np.nan,             # hip height above the ankle, in pixels
            "knee": (angles[len(angles) // 2] if len(angles) < 2 else min(angles)) if angles else np.nan,   # straightest counts
            "knee_max": max(angles) if angles else np.nan,
            "lean": float(np.degrees(np.arctan2(abs(up[0]), -up[1] + 1e-6))),
            "knees": abs(lm[L_KNEE][0] - lm[R_KNEE][0]) / (abs(lm[L_ANK][0] - lm[R_ANK][0]) + 1e-6) if feet and knees_in and feet_in else 1.0,
            "balance": abs(float(tilt(lm[L_HIP], lm[R_HIP]) - tilt(lm[L_SHO], lm[R_SHO]))),
        }

    def update(self, lm: np.ndarray, t: float, h: float = 1e9) -> Frame:
        view = self.view(lm)
        m = self.measure(lm, view, h)
        warn = "" if m["knees_in"] and m["feet_in"] else "Step back so your knees and feet are in view (counting only)"
        if not m["hips_ok"]:
            self.lost = self.lost or t
            if self.state != "standing" and t - self.lost > 1.0:      # tracking gone for a second: abandon the rep
                self.state = "standing"
            return self._frame(view, m, 0.0, "Step back: hips and knees must be in view")
        self.lost = 0.0

        nan_safe = lambda new, old: old if np.isnan(new) else new if np.isnan(old) else ALPHA * new + (1 - ALPHA) * old
        self.s = dict(m) if self.s is None else m | {k: nan_safe(m[k], self.s[k]) for k in SMOOTHED}
        s = self.s
        knee_known = not np.isnan(s["knee"])
        self.base = self.base or {k: s[k] for k in ("hip_y", "height", "thigh")}
        leg = self.base["height"] if not np.isnan(self.base["height"]) else 2 * self.base["thigh"]
        # Hip travel: hip height above the ankle when feet are seen (camera motion cancels), else hip pixel y.
        drop = (1 - s["height"] / leg) if knee_known else (s["hip_y"] - self.base["hip_y"]) / leg
        s["depth"] = (s["hip_y"] - s["knee_y"]) / self.base["thigh"]
        straight = s["knee"] > 160 if knee_known else drop < END           # every seen leg straight
        bending = s["knee_max"] < 150 if knee_known else True              # every seen leg bent (a leg lift is not a squat)
        self.recent = [(t0, d) for t0, d in self.recent if t - t0 <= 3.0] + [(t, drop)]
        vals = [d for _, d in self.recent]
        parked = t - self.recent[0][0] >= 3.0 and max(vals) - min(vals) < 0.05   # hardly moved for 3 s
        valid = [k for k, v in METRICS.items() if v[2] in ("both", view)]
        if not (m["knees_in"] and m["feet_in"]):          # depth / knee tracking need real, in-frame joints
            valid = [k for k in valid if k not in ("depth", "knees")]
        events = []

        if self.state == "standing":
            if straight or parked:                       # re-baseline: moved, zoomed, bad first frame, or just standing there
                self.base = {k: 0.9 * self.base[k] + 0.1 * s[k] for k in self.base}
            elif drop > START and bending:
                self.state, self.t_start, self.max_drop = "down", t, drop
                self.cur = {k: s[k] for k in METRICS}
        elif t - self.t_start > MAX_DUR:                 # stuck: assume they are standing now and start over
            self.state, self.base = "standing", {k: s[k] for k in self.base}
        else:
            self.cur = {k: AGG[k](self.cur[k], s[k]) for k in METRICS}
            self.max_drop = max(self.max_drop, drop)
            if self.state == "down" and drop < self.max_drop - 0.04 and self.max_drop > 0.1:
                self.state, self.t_bottom = "up", t
            elif self.state == "up" and (drop < END or (straight and drop < 0.3 * self.max_drop)):
                events += self._finish(t, valid)         # back at the top, or legs straight and nearly there (baseline drift)

        if self.state == "up" and self.cur["lean"] <= 65:   # live faults on the way up, unless it's a hinge
            events += [(3, METRICS[k][4]) for k in ("lean", "knees") if k in valid and grade(METRICS[k][1], self.cur[k]) == RED]
        return self._frame(view, m, drop, warn, valid, events)

    def _finish(self, t: float, valid: list) -> list:
        self.state = "standing"
        down, up = self.t_bottom - self.t_start, t - self.t_bottom
        lean, depth = self.cur["lean"], self.cur["depth"]
        hinge = "lean" in valid and (lean > 80 or (lean > 60 and depth < -0.3))   # bent over without sitting down
        if self.max_drop > 0.9 or hinge or lean > 100:
            return []                                        # camera cut, pick-up / hinge, or garbage pose
        if self.max_drop < MIN_DROP or not MIN_DUR <= down + up <= MAX_DUR:
            if self.max_drop < MIN_DROP / 2:
                return []                                       # a wobble, not an attempt
            self.dips += 1
            return [(2, "Go lower")]
        grades = {k: grade(METRICS[k][1], self.cur[k]) for k in valid}
        faults = [METRICS[k][3] for k in valid if grades[k] >= AMBER]
        slow = up > SLOW_ASCENT_S or (len(self.reps) >= 2 and up > 1.6 * np.median([r.t_up for r in self.reps]))
        faults += ["fast descent"] * (down < FAST_DESCENT_S) + ["slow ascent"] * bool(slow)
        rep = Rep(len(self.reps) + 1, dict(self.cur), grades, self.max_drop, down, up, faults)
        self.reps.append(rep)

        events = [(3, str(rep.n))]                       # the count comes first, then any fault cue
        bad = max(valid, key=lambda k: grades[k])
        if grades[bad] >= AMBER:
            events.append((grades[bad] + 1, METRICS[bad][4]))
        if down < FAST_DESCENT_S:
            events.append((2, "Control the way down"))
        if slow:
            events.append((3, "You're slowing down. Drive up"))
        return events

    def _frame(self, view, m, drop, warn, valid=(), events=()) -> Frame:
        ref = self.cur if self.state != "standing" else (self.reps[-1].worst if self.reps else None)
        grades = {k: grade(METRICS[k][1], ref[k]) if ref and k in valid else GREEN for k in METRICS}
        segments = {"thigh": grades["depth"], "shin": grades["depth"], "knees": grades["knees"],
                    "torso": grades["lean"] if view == "side" else grades["balance"]}
        src = self.s if self.s and "depth" in self.s else m | {"depth": 0.0}
        live = {k: (src[k], grade(METRICS[k][1], src[k]) if k in valid else None) for k in METRICS}
        if self.state == "up":
            t_down, t_up = self.t_bottom - self.t_start, 0.0
        elif self.state == "down":
            t_down, t_up = 0.0, 0.0
        else:
            t_down, t_up = (self.reps[-1].t_down, self.reps[-1].t_up) if self.reps else (0.0, 0.0)
        return Frame(view, self.state, self.reps, self.dips, drop, live, grades, segments, t_down, t_up, warn, events=list(events))


Analyzer = SquatAnalyzer
PRIMARY = ("Travel", 0.8, (0.22,))                      # live bar: label, full-scale value, tick marks
RANGE = {"depth": (-0.8, 0.4), "lean": (0, 90), "knees": (0.4, 1.2), "balance": (0, 25)}   # metric bars, left -> right
LINES = [m[4] for m in METRICS.values()] + ["Go lower", "Control the way down", "You're slowing down. Drive up"]
JOINTS = (L_SHO, R_SHO, L_HIP, R_HIP, L_KNEE, R_KNEE, L_ANK, R_ANK)


def segments(f: Frame, lm) -> list:
    """Skeleton lines to draw: (landmark a, landmark b, grade, thickness)."""
    g = f.segments
    out = [(a, b, g["torso"], 4) for a, b in ((L_SHO, R_SHO), (L_SHO, L_HIP), (R_SHO, R_HIP), (L_HIP, R_HIP))]
    out += [(L_HIP, L_KNEE, g["thigh"], 4), (R_HIP, R_KNEE, g["thigh"], 4), (L_KNEE, L_ANK, g["shin"], 4), (R_KNEE, R_ANK, g["shin"], 4)]
    if f.view == "front":
        out.append((L_KNEE, R_KNEE, g["knees"], 2))
    return out

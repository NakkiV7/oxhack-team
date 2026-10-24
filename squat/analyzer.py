"""Squat form analysis: angles -> live metrics, per-rep records with named faults, coaching events."""
from dataclasses import dataclass, field

import numpy as np

from pose import L_ANK, L_HIP, L_KNEE, L_SHO, R_ANK, R_HIP, R_KNEE, R_SHO

GREEN, AMBER, RED = 0, 1, 2
STAND_KNEE = 155                          # knee angle at/above which the lifter is "standing"
FAST_DESCENT_S, SLOW_ASCENT_S = 0.45, 2.2

# name: (label, (good, warn) thresholds, view it is valid in, fault name, cue). Tune vs UI-PRMD / Fitness-AQA.
METRICS = {
    "depth":    ("Depth",   (95, 115),    "both",  "shallow",      "Deeper. Sit between your heels"),
    "lean":     ("Lean",    (40, 55),     "side",  "forward lean", "Chest up"),
    "knees":    ("Knees",   (0.85, 0.70), "front", "knees in",     "Knees out"),
    "balance":  ("Balance", (10, 16),     "front", "uneven",       "Even weight on both feet"),   # hip vs shoulder tilt, deg
}


def angle(a, b, c, dims: int = 2) -> float:
    """Angle at b (degrees) between a-b-c. dims=3 uses MediaPipe depth too (needed when facing the camera)."""
    v1, v2 = a[:dims] - b[:dims], c[:dims] - b[:dims]
    cos = np.dot(v1, v2) / (np.linalg.norm(v1) * np.linalg.norm(v2) + 1e-6)
    return float(np.degrees(np.arccos(np.clip(cos, -1, 1))))


def grade(name: str, x: float) -> int:
    good, warn = METRICS[name][1]
    if good <= warn:                       # lower is better
        return GREEN if x <= good else AMBER if x <= warn else RED
    return GREEN if x >= good else AMBER if x >= warn else RED


AGG = {"depth": min, "lean": max, "knees": min, "balance": max}   # how a metric accumulates over a rep


@dataclass
class Rep:
    n: int
    worst: dict            # metric -> worst value seen in the rep
    grades: dict           # metric -> grade, only metrics valid for the view
    t_down: float
    t_up: float
    faults: list

    @property
    def grade(self) -> int:
        return max(self.grades.values(), default=GREEN)


@dataclass
class Frame:
    view: str
    state: str                      # standing | down | up
    reps: list
    live: dict                      # metric -> (current value, instant grade or None if not valid in this view)
    grades: dict                    # metric -> sticky grade (worst so far this rep, or last rep when standing)
    segments: dict                  # skeleton segment -> grade
    t_down: float
    t_up: float
    events: list = field(default_factory=list)   # (priority, cue text)


class SquatAnalyzer:
    def __init__(self):
        self.reps: list[Rep] = []
        self.state = "standing"
        self.cur: dict = {}
        self.t_start = self.t_bottom = 0.0
        self.facing, self._view = 1.0, "front"               # smoothed shoulder-width / torso-height ratio

    def view(self, lm) -> str:
        sho, hip = (lm[L_SHO] + lm[R_SHO]) / 2, (lm[L_HIP] + lm[R_HIP]) / 2
        ratio = abs(lm[L_SHO][0] - lm[R_SHO][0]) / (np.linalg.norm(sho[:2] - hip[:2]) + 1e-6)
        self.facing = 0.9 * self.facing + 0.1 * ratio
        if self.facing > 0.5:                                # two thresholds: hold the last view in between
            self._view = "front"
        elif self.facing < 0.35:
            self._view = "side"
        return self._view

    @staticmethod
    def measure(lm, view: str) -> dict:
        sho, hip = (lm[L_SHO] + lm[R_SHO]) / 2, (lm[L_HIP] + lm[R_HIP]) / 2
        d = 2 if view == "side" else 3                       # front view: 2D angles collapse with foreshortening
        kl, kr = angle(lm[L_HIP], lm[L_KNEE], lm[L_ANK], d), angle(lm[R_HIP], lm[R_KNEE], lm[R_ANK], d)
        knee = (kl + kr) / 2
        up = sho[:2] - hip[:2]
        lean = float(np.degrees(np.arctan2(abs(up[0]), -up[1] + 1e-6)))
        kw = abs(lm[L_KNEE][0] - lm[R_KNEE][0]) / (abs(lm[L_ANK][0] - lm[R_ANK][0]) + 1e-6)
        tilt = lambda a, b: np.degrees(np.arctan2(abs(a[1] - b[1]), abs(a[0] - b[0]) + 1e-6))
        shift = abs(float(tilt(lm[L_HIP], lm[R_HIP]) - tilt(lm[L_SHO], lm[R_SHO])))   # perspective cancels out
        deep = knee < 140                                    # knee tracking / balance only mean something mid-squat
        return {"depth": knee, "lean": lean, "knees": kw if deep else 1.0, "balance": shift if deep else 0.0}

    def update(self, lm: np.ndarray, t: float) -> Frame:
        view = self.view(lm)
        m = self.measure(lm, view)
        valid = [k for k, v in METRICS.items() if v[2] in ("both", view)]
        in_squat = m["depth"] < STAND_KNEE
        events = []

        if self.state == "standing" and in_squat:
            self.state, self.cur, self.t_start = "down", dict(m), t
        elif self.state != "standing":
            self.cur = {k: AGG[k](self.cur[k], m[k]) for k in m}
            if self.state == "down" and self.cur["depth"] + 8 < m["depth"] < 140:   # turned the corner
                self.state, self.t_bottom = "up", t
            elif self.state == "up" and not in_squat:
                events += self._finish(t, valid)

        ref = self.cur if self.state != "standing" else (self.reps[-1].worst if self.reps else None)
        grades = {k: grade(k, ref[k]) if ref and k in valid else GREEN for k in METRICS}
        if self.state == "up" and self.cur["lean"] <= 65:    # live faults on the way up, unless it's a hinge/pick-up
            events += [(3, METRICS[k][4]) for k in ("lean", "knees") if grades[k] == RED]
        segments = {"thigh": grades["depth"], "shin": grades["depth"], "knees": grades["knees"],
                    "torso": grades["lean"] if view == "side" else grades["balance"]}
        live = {k: (m[k], grade(k, m[k]) if k in valid else None) for k in METRICS}
        if self.state == "down":
            t_down, t_up = t - self.t_start, 0.0
        elif self.state == "up":
            t_down, t_up = self.t_bottom - self.t_start, t - self.t_bottom
        else:
            t_down, t_up = (self.reps[-1].t_down, self.reps[-1].t_up) if self.reps else (0.0, 0.0)
        return Frame(view, self.state, self.reps, live, grades, segments, t_down, t_up, events)

    def _finish(self, t: float, valid: list) -> list:
        self.state = "standing"
        if "lean" in valid and self.cur["lean"] > 65:        # bent double: a hinge or a pick-up, not a squat
            return []
        down, up = self.t_bottom - self.t_start, t - self.t_bottom
        grades = {k: grade(k, self.cur[k]) for k in valid}
        faults = [METRICS[k][3] for k in valid if grades[k] >= AMBER]
        slow = up > SLOW_ASCENT_S or (len(self.reps) >= 2 and up > 1.6 * np.median([r.t_up for r in self.reps]))
        faults += ["fast descent"] * (down < FAST_DESCENT_S) + ["slow ascent"] * bool(slow)
        rep = Rep(len(self.reps) + 1, dict(self.cur), grades, down, up, faults)
        self.reps.append(rep)

        events = [(2, str(rep.n))]
        bad = max(valid, key=lambda k: grades[k])
        if grades[bad] >= AMBER:
            events.append((grades[bad] + 1, METRICS[bad][4]))
        if down < FAST_DESCENT_S:
            events.append((2, "Control the way down"))
        if slow:
            events.append((3, "You're slowing down. Drive up"))
        return events

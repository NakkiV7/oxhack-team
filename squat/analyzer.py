"""Squat form analysis: joint angles -> per-segment grades, rep state machine, coaching events."""
from dataclasses import dataclass, field

import numpy as np

from pose import L_ANK, L_HIP, L_KNEE, L_SHO, R_ANK, R_HIP, R_KNEE, R_SHO

GREEN, AMBER, RED = 0, 1, 2

# Thresholds (degrees unless noted). Tune against UI-PRMD / Fitness-AQA.
STAND_KNEE = 155        # knee angle at which we call the lifter "standing"
DEPTH = (95, 115)       # min knee angle in rep: <=95 green, <=115 amber, else red (shallow)
LEAN = (40, 55)         # torso angle from vertical (side view)
VALGUS = (0.85, 0.70)   # knee-width / ankle-width (front view): >=.85 green, >=.70 amber, else red
SYMMETRY = (12, 20)     # |left knee - right knee| angle difference
FAST_DESCENT_S, SLOW_ASCENT_S = 0.45, 2.2


def angle(a, b, c) -> float:
    """Angle at b (degrees) between points a-b-c, using x,y only."""
    v1, v2 = a[:2] - b[:2], c[:2] - b[:2]
    cos = np.dot(v1, v2) / (np.linalg.norm(v1) * np.linalg.norm(v2) + 1e-6)
    return float(np.degrees(np.arccos(np.clip(cos, -1, 1))))


def grade(x: float, good: float, warn: float) -> int:
    """Grade x against (good, warn) thresholds; works whether lower or higher is better."""
    if good <= warn:
        return GREEN if x <= good else AMBER if x <= warn else RED
    return GREEN if x >= good else AMBER if x >= warn else RED


@dataclass
class Frame:
    view: str                      # "side" | "front"
    state: str                     # "standing" | "down" | "up"
    reps: int
    knee: float                    # current knee angle (avg of both legs)
    lean: float                    # torso angle from vertical
    segments: dict                 # segment name -> grade (colours the skeleton)
    events: list = field(default_factory=list)  # (priority, text) cues raised this frame


class SquatAnalyzer:
    def __init__(self):
        self.reps = 0
        self.state = "standing"
        self.min_knee = 180.0
        self.prev_knee = 180.0
        self.t_start = self.t_bottom = 0.0
        self.ascents: list[float] = []
        self.last_depth = GREEN

    def update(self, lm: np.ndarray, t: float) -> Frame:
        sho = (lm[L_SHO] + lm[R_SHO]) / 2
        hip = (lm[L_HIP] + lm[R_HIP]) / 2
        torso_h = np.linalg.norm(sho[:2] - hip[:2])
        view = "side" if abs(lm[L_SHO][0] - lm[R_SHO][0]) < 0.4 * torso_h else "front"

        kl, kr = angle(lm[L_HIP], lm[L_KNEE], lm[L_ANK]), angle(lm[R_HIP], lm[R_KNEE], lm[R_ANK])
        knee = (kl + kr) / 2
        up = sho[:2] - hip[:2]
        lean = float(np.degrees(np.arctan2(abs(up[0]), -up[1] + 1e-6)))
        in_squat = knee < STAND_KNEE
        events = []

        # --- rep state machine on knee angle ---
        if self.state == "standing" and in_squat:
            self.state, self.min_knee, self.t_start = "down", knee, t
        elif self.state == "down":
            self.min_knee = min(self.min_knee, knee)
            if knee > self.min_knee + 8 and knee < 140:          # turned the corner
                self.state, self.t_bottom = "up", t
                if t - self.t_start < FAST_DESCENT_S:
                    events.append((2, "Control the way down"))
        elif self.state == "up":
            self.min_knee = min(self.min_knee, knee)
            if not in_squat:
                self.reps += 1
                self.state = "standing"
                self.last_depth = grade(self.min_knee, *DEPTH)
                asc = t - self.t_bottom
                self.ascents.append(asc)
                events.append((2, f"{self.reps}"))
                if self.last_depth == RED:
                    events.append((3, "Deeper. Sit between your heels"))
                elif self.last_depth == AMBER:
                    events.append((2, "A bit lower next rep"))
                if asc > SLOW_ASCENT_S or (len(self.ascents) >= 3 and asc > 1.6 * min(self.ascents[:-1])):
                    events.append((3, "You're slowing down. Drive up"))

        # --- live segment grades ---
        depth_g = grade(self.min_knee, *DEPTH) if self.state != "standing" else self.last_depth
        if view == "side":
            torso_g = grade(lean, *LEAN) if in_squat else GREEN
            knee_g = GREEN
            if torso_g == RED and in_squat:
                events.append((3, "Chest up"))
        else:
            kw = abs(lm[L_KNEE][0] - lm[R_KNEE][0]) / (abs(lm[L_ANK][0] - lm[R_ANK][0]) + 1e-6)
            knee_g = grade(kw, *VALGUS) if knee < 140 else GREEN
            torso_g = grade(abs(kl - kr), *SYMMETRY) if in_squat else GREEN
            if knee_g == RED:
                events.append((3, "Knees out"))

        segments = {"thigh": depth_g, "shin": depth_g, "torso": torso_g, "knees": knee_g}
        self.prev_knee = knee
        return Frame(view, self.state, self.reps, knee, lean, segments, events)

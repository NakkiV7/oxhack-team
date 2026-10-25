"""Shared types for exercise analyzers: grades, angles, per-rep records and per-frame output."""
from dataclasses import dataclass, field

import numpy as np

GREEN, AMBER, RED = 0, 1, 2


def angle(a, b, c, dims: int = 2) -> float:
    """Angle at b (degrees) between a-b-c."""
    v1, v2 = a[:dims] - b[:dims], c[:dims] - b[:dims]
    cos = np.dot(v1, v2) / (np.linalg.norm(v1) * np.linalg.norm(v2) + 1e-6)
    return float(np.degrees(np.arccos(np.clip(cos, -1, 1))))


def grade(thresholds, x: float) -> int:
    """(good, warn) thresholds; lower is better when good <= warn, else higher is better."""
    good, warn = thresholds
    if good <= warn:
        return GREEN if x <= good else AMBER if x <= warn else RED
    return GREEN if x >= good else AMBER if x >= warn else RED


@dataclass
class Rep:
    n: int
    worst: dict            # metric -> worst value in the rep
    grades: dict           # metric -> grade, only metrics valid for the view
    drop: float            # primary travel signal at the bottom (fraction)
    t_down: float
    t_up: float
    faults: list

    @property
    def grade(self) -> int:
        return max(self.grades.values(), default=GREEN)


@dataclass
class Frame:
    view: str
    state: str
    reps: list                      # counted reps only
    dips: int                       # attempts that did not count
    drop: float                     # live primary travel signal
    live: dict                      # metric -> (value, instant grade or None if not valid now)
    grades: dict                    # metric -> sticky grade (this rep so far, or last rep)
    segments: dict                  # named body segment -> grade (colours the skeleton)
    t_down: float
    t_up: float
    warn: str = ""
    side: int = 0                   # tracked body side for side-on exercises (0 left, 1 right)
    events: list = field(default_factory=list)   # (priority, cue text)

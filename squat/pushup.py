"""Push-up: a port of prototype/pushup/pushup.mjs (RepCounter) so both exercises run in the same app.

Side-on view. Elbow angle (shoulder-elbow-wrist) drives the rep state machine; the body line
(shoulder-hip-ankle, or knee for knee push-ups) and the signed hip offset judge posture.
Keep thresholds in step with VARIATIONS in pushup.mjs.
"""
import numpy as np

from common import AMBER, GREEN, RED, Frame, Rep, angle, grade

NAME, EXAMPLE, TARGET = "Push-up", "example_pushup.mp4", 8
HINT = "side-on, 2-3 m away, whole body in frame"
VIS, ALPHA = 0.5, 0.5
HYSTERESIS = 10                                   # degrees below `up` before a lowering starts
MIN_DUR, MAX_DUR = 0.5, 15.0
SLOW = 1.15                                       # rep time vs average of earlier reps = slowing down

# variation: (elbow angle for "up", elbow angle that counts as depth, body-line joint, min body-line angle, gravity)
VARIATIONS = {
    "wall":     (150, 120, "ankle", 160, False),
    "incline":  (150, 105, "ankle", 160, True),
    "knee":     (150, 100, "knee", 160, True),
    "standard": (150, 95, "ankle", 165, True),
}
J = {"shoulder": (11, 12), "elbow": (13, 14), "wrist": (15, 16), "hip": (23, 24), "knee": (25, 26), "ankle": (27, 28)}
CUES = {
    "shallow": "Not low enough. Bend your elbows more",
    "sagging": "Hips sagging. Squeeze your core and glutes",
    "piking": "Hips too high. Lower them into a straight line",
    "bent": "Keep your body in one straight line",
    "slow": "You're slowing down. Push",
}
LINES = list(CUES.values())


class PushupAnalyzer:
    def __init__(self, variation: str = "standard"):
        self.up, self.down, self.ref, self.min_line, self.gravity = VARIATIONS[variation]
        self.variation = variation
        self.reps: list[Rep] = []
        self.dips = 0
        self.state = "unknown"                    # unknown -> up <-> down
        self.elbow = self.line = None
        self.hip_drop = 0.0
        self.side = 0
        self.t_start = self.t_bottom = 0.0
        self.min_elbow = self.min_line_seen = 180.0
        self.worst_drop = 0.0

    def measure(self, lm) -> dict:
        vis = lm[:, 3]
        score = lambda s: sum(vis[J[j][s]] for j in J)
        self.side = 0 if score(0) >= score(1) else 1
        p = lambda j: lm[J[j][self.side]]
        sh, el, wr, hip, ref = p("shoulder"), p("elbow"), p("wrist"), p("hip"), p(self.ref)
        d = ref[:2] - sh[:2]
        t = float(np.dot(hip[:2] - sh[:2], d) / (np.dot(d, d) or 1.0))
        proj_y = sh[1] + t * d[1]
        torso = float(np.linalg.norm(hip[:2] - sh[:2])) or 1.0
        return {
            "elbow": angle(sh, el, wr), "line": angle(sh, hip, ref),
            "hip_drop": float(hip[1] - proj_y) / torso,          # + = hips below the line (sag), - = piking
            "min_vis": float(min(sh[3], el[3], wr[3], hip[3], ref[3])),
        }

    def update(self, lm: np.ndarray, t: float, h: float = 1e9) -> Frame:
        m = self.measure(lm)
        if m["min_vis"] < VIS or np.isnan(m["elbow"]):
            return self._frame(m, "Some joints are hidden: turn side-on to the camera")
        self.elbow = m["elbow"] if self.elbow is None else ALPHA * m["elbow"] + (1 - ALPHA) * self.elbow
        self.line = m["line"] if self.line is None else ALPHA * m["line"] + (1 - ALPHA) * self.line
        self.hip_drop = ALPHA * m["hip_drop"] + (1 - ALPHA) * self.hip_drop
        events = []

        if self.state == "unknown":
            if self.elbow >= self.up:
                self.state = "up"
        elif self.state == "up" and self.elbow < self.up - HYSTERESIS:
            self.state, self.t_start, self.t_bottom = "down", t, t
            self.min_elbow, self.min_line_seen, self.worst_drop = 180.0, 180.0, 0.0
        elif self.state == "down":
            if self.elbow < self.min_elbow:
                self.min_elbow, self.t_bottom = self.elbow, t
            if self.line < self.min_line_seen:
                self.min_line_seen, self.worst_drop = self.line, self.hip_drop
            if self.elbow >= self.up:
                self.state = "up"
                events = self._finish(t)
            elif t - self.t_start > MAX_DUR:
                self.state = "unknown"
        return self._frame(m, "", events)

    def _finish(self, t: float) -> list:
        down, up = self.t_bottom - self.t_start, t - self.t_bottom
        if self.min_elbow > self.down or down + up < MIN_DUR:
            self.dips += 1
            return [(2, CUES["shallow"])]
        posture = self._posture()
        faults = [posture] if posture else []
        secs = down + up
        slow = len(self.reps) >= 3 and secs > SLOW * np.mean([r.t_down + r.t_up for r in self.reps])
        faults += ["slow"] * bool(slow)
        grades = {"elbow": GREEN, "line": RED if posture else GREEN, "hip": GREEN if not posture else AMBER}
        rep = Rep(len(self.reps) + 1, {"elbow": self.min_elbow, "line": self.min_line_seen, "hip": self.worst_drop},
                  grades, self._bend(self.min_elbow), down, up, faults)
        self.reps.append(rep)
        events = [(3, str(rep.n))]
        if posture:
            events.append((3, CUES[posture]))
        if slow:
            events.append((3, CUES["slow"]))
        return events

    def _posture(self):
        if self.min_line_seen >= self.min_line:
            return None
        if not self.gravity:
            return "bent"
        return "sagging" if self.worst_drop > 0 else "piking"

    def _bend(self, elbow: float) -> float:
        return float(np.clip((180 - elbow) / (180 - self.down), 0, 1.2))     # 1.0 = reached depth

    def _frame(self, m, warn, events=()) -> Frame:
        elbow = self.elbow if self.elbow is not None else m["elbow"]
        line = self.line if self.line is not None else m["line"]
        in_rep = self.state == "down"
        last = self.reps[-1] if self.reps else None
        depth_g = (GREEN if self.min_elbow <= self.down else AMBER) if in_rep else (GREEN if last else AMBER)
        line_g = GREEN if line >= self.min_line else RED
        hip_g = GREEN if abs(self.hip_drop) < 0.08 else AMBER if abs(self.hip_drop) < 0.15 else RED
        live = {"elbow": (elbow, depth_g), "line": (line, line_g), "hip": (self.hip_drop, hip_g)}
        grades = {"elbow": depth_g, "line": line_g, "hip": hip_g}
        segments = {"arm": depth_g, "body": line_g}
        if in_rep:
            t_down, t_up = 0.0, 0.0
        else:
            t_down, t_up = (last.t_down, last.t_up) if last else (0.0, 0.0)
        return Frame("side", self.state, self.reps, self.dips, self._bend(elbow), live, grades, segments,
                     t_down, t_up, warn, side=self.side, events=list(events))


Analyzer = PushupAnalyzer
PRIMARY = ("Elbow bend", 1.2, (1.0,))
METRICS = {   # label, (good, warn) ticks, view, fault, cue; the Analyzer applies the rules itself
    "elbow": ("Elbow", (95, 110), "side", "shallow", CUES["shallow"]),
    "line": ("Body line", (165, 157), "side", "bent", CUES["bent"]),
    "hip": ("Hip offset", (0.08, 0.15), "side", "sagging", CUES["sagging"]),
}
RANGE = {"elbow": (180, 60), "line": (120, 180), "hip": (-0.3, 0.3)}
JOINTS = ()                                       # filled per frame in segments()


def segments(f: Frame, lm) -> list:
    s = f.side
    sh, el, wr, hip, kn, an = (J[j][s] for j in ("shoulder", "elbow", "wrist", "hip", "knee", "ankle"))
    return [(sh, el, f.segments["arm"], 4), (el, wr, f.segments["arm"], 4),
            (sh, hip, f.segments["body"], 4), (hip, kn, f.segments["body"], 4), (kn, an, f.segments["body"], 4)]


def joints(f: Frame) -> tuple:
    return tuple(J[j][f.side] for j in ("shoulder", "elbow", "wrist", "hip", "knee", "ankle"))

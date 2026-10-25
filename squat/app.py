"""Guided demo for squats and push-ups: title -> example set (with voice) -> countdown -> your set -> results.

Usage: python app.py [--exercise squat|pushup] [--voice elevenlabs|say|off] [--target 8] [--source 0|clip.mp4] [--headless --out flow.mp4]
Keys: SPACE continue / start, ENTER skip the example, R go again, Q quit.
"""
import argparse
import importlib
import json
import os
import subprocess
import time
from collections import Counter
from datetime import datetime
from pathlib import Path

import cv2
import numpy as np

from common import GREEN
from coach import Coach
from main import draw
from panel import BG, COLOUR, DIM, FG, W as PANEL_W, panel, text
from pose import MODELS, Pose
from voice import STANDARD_LINES, Voice, load_env

HERE = Path(__file__).parent
CW, CH = 1360, 680                      # window canvas
D, S = cv2.FONT_HERSHEY_DUPLEX, cv2.FONT_HERSHEY_SIMPLEX
ACCENT = (200, 160, 60)


def canvas():
    return np.full((CH, CW, 3), BG, np.uint8)


def fit(img, top=70, bottom=50):
    """Letterbox img into the canvas between a top and bottom strip."""
    c = canvas()
    h, w = img.shape[:2]
    k = min(CW / w, (CH - top - bottom) / h)
    nw, nh = int(w * k), int(h * k)
    x, y = (CW - nw) // 2, top + (CH - top - bottom - nh) // 2
    c[y:y + nh, x:x + nw] = cv2.resize(img, (nw, nh))
    return c


def centred(c, s, y, scale, colour=FG, thick=1, font=D):
    (tw, _), _ = cv2.getTextSize(s, font, scale, thick)
    text(c, s, ((CW - tw) // 2, y), scale, colour, thick, font)


def strip(c, left, right=""):
    text(c, left, (24, 44), 0.8, FG, 1, D)
    if right:
        (tw, _), _ = cv2.getTextSize(right, S, 0.55, 1)
        text(c, right, (CW - tw - 24, 44), 0.55, DIM)


class App:
    def __init__(self, a):
        self.a = a
        self.ex = importlib.import_module(a.exercise)
        self.example_path = HERE / "assets" / self.ex.EXAMPLE
        self.voice = Voice(a.voice, STANDARD_LINES + self.ex.LINES) if a.voice != "off" else print
        self.pose = None
        self.cap = None
        self.writer = None
        self.last_key = -1

    # --- plumbing -------------------------------------------------------------------------------
    def show(self, frame, wait_ms=1, *, finish_on_q=False):
        if self.a.out:
            self.writer = self.writer or cv2.VideoWriter(self.a.out, cv2.VideoWriter_fourcc(*"mp4v"), 30, (CW, CH))
            self.writer.write(frame)
        if self.a.headless:
            return -1
        cv2.imshow("Spottr", frame)
        k = cv2.waitKey(wait_ms) & 0xFF
        if (k == ord("q") and not finish_on_q) or k == 27 or cv2.getWindowProperty("Spottr", cv2.WND_PROP_VISIBLE) < 1:
            raise KeyboardInterrupt
        return k

    def hold(self, frame, seconds, keys=(32, 13)):
        """Show a static frame until a key in `keys` or (headless) `seconds` pass. Returns the key."""
        if self.a.headless:
            for _ in range(int(seconds * 30)):
                self.show(frame)
            return -1
        while True:
            k = self.show(frame, 30)
            if k in keys:
                return k

    def camera(self):
        if self.cap is None:
            live = self.a.source.isdigit()
            self.cap = cv2.VideoCapture(int(self.a.source) if live else self.a.source)
            if not self.cap.isOpened():
                raise SystemExit(f"cannot open {self.a.source!r} (grant camera access to your terminal app)")
            self.is_live = live
            self.fps = self.cap.get(cv2.CAP_PROP_FPS) or 30
        return self.cap

    # --- screens --------------------------------------------------------------------------------
    def intro(self):
        c = canvas()
        centred(c, "SPOTTR", 230, 3.2, FG, 4)
        centred(c, f"{self.ex.NAME} coach: form, tempo and when to push", 290, 0.9, DIM, 1, S)
        centred(c, "SPACE  watch an example set", 420, 0.9, ACCENT)
        centred(c, "ENTER  skip straight to your set", 470, 0.9, FG)
        centred(c, "Q  quit", 520, 0.7, DIM, 1, S)
        return self.hold(c, 2)

    def example(self):
        if not self.example_path.is_file():
            print("Example unavailable; skipping it. Press Enter on the title screen to skip examples.")
            return
        cap = cv2.VideoCapture(str(self.example_path))
        fps = cap.get(cv2.CAP_PROP_FPS) or 30
        audio = self.example_path.with_suffix(".m4a")
        player = subprocess.Popen(["afplay", str(audio)]) if audio.exists() and not self.a.headless and self.a.voice != "off" else None
        t0, n = time.monotonic(), 0
        try:
            while True:
                ok, img = cap.read()
                if not ok:
                    break
                c = fit(img)
                strip(c, "Example set", "SPACE  skip to your set")
                centred(c, "Watch the skeleton colours and listen to the coach", CH - 18, 0.6, DIM, 1, S)
                n += 1
                wait = max(1, int((t0 + n / fps - time.monotonic()) * 1000)) if not self.a.headless else 1
                if self.show(c, wait) == 32:
                    break
        finally:
            cap.release()
            if player:
                player.terminate()

    def countdown(self):
        cap = self.camera()
        for n in (3, 2, 1):
            t0 = time.monotonic()
            while time.monotonic() - t0 < 1.0:
                ok, img = cap.read() if self.is_live else (True, None)   # a file source keeps its frames for the set
                if not ok:
                    return
                c = fit(img) if img is not None else canvas()
                strip(c, "Get ready", self.ex.HINT)
                centred(c, str(n), 400, 5, ACCENT, 6)
                self.show(c, 30)
        if callable(self.voice) and self.a.voice != "off":
            self.voice("Go")

    def live(self):
        cap = self.camera()
        if not self.is_live:
            cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
        if self.pose is not None:
            self.pose.close()
        self.pose = Pose(MODELS[self.a.model])
        analyzer, coach = self.ex.Analyzer(), Coach(speak=self.voice)
        f, n, t0 = None, 0, time.monotonic()
        while True:
            ok, img = cap.read()
            if not ok:
                break
            t = time.monotonic() - t0 if self.is_live else n / self.fps
            lm = self.pose(img, int(t * 1000))
            if lm is not None:
                f = analyzer.update(lm, t, img.shape[0])
                coach.handle(f.events, t)
                draw(img, lm, f, coach.showing(t), self.ex)
            img = np.hstack([img, panel(f, img.shape[0], self.ex) if f else np.full((img.shape[0], PANEL_W, 3), BG, np.uint8)])
            c = fit(img)
            strip(c, f"Your set  {len(analyzer.reps)} / {self.a.target}", "Q  finish early")
            key = self.show(c, finish_on_q=True)
            if key == ord("q") or (key == 32 and len(analyzer.reps)):
                break
            n += 1
            if len(analyzer.reps) >= self.a.target:
                if self.a.voice != "off":
                    self.voice("Set complete. Nice work")
                time.sleep(0 if self.a.headless else 1.5)
                break
        return analyzer, coach

    def results(self, analyzer, coach):
        reps = analyzer.reps
        clean = sum(r.grade == GREEN for r in reps)
        faults = Counter(x for r in reps for x in r.faults)
        c = canvas()
        strip(c, "Your results")
        text(c, str(len(reps)), (60, 200), 4, FG, 5, D)
        text(c, "REPS", (60 + 60 * len(str(len(reps))) + 30, 200), 1.0, DIM, 1, S)
        text(c, f"{clean} clean   {analyzer.dips} attempts not counted", (60, 250), 0.75, FG, 1, S)
        if reps:
            down, up = np.mean([r.t_down for r in reps]), np.mean([r.t_up for r in reps])
            text(c, f"tempo  down {down:.1f}s   up {up:.1f}s", (60, 290), 0.75, FG, 1, S)
            text(c, "FAULTS  " + ("   ".join(f"{k} x{v}" for k, v in faults.most_common(4)) or "none"), (60, 330), 0.7, FG, 1, S)
            text(c, "COACH SAID  " + "  |  ".join(dict.fromkeys(t for _, t in coach.history if not t.isdigit())) [:90], (60, 370), 0.6, DIM, 1, S)
        y = 200
        text(c, "REP LOG", (760, y - 30), 0.55, DIM, 1, S)
        for r in reps[-14:]:
            cv2.circle(c, (770, y - 6), 7, COLOUR[r.grade], -1)
            text(c, f"#{r.n:<3}{r.t_down:.1f}/{r.t_up:.1f}s  {', '.join(r.faults) or 'clean'}", (790, y), 0.55, FG, 1, S)
            y += 28
        centred(c, "R  go again      SPACE  watch the example      Q  quit", CH - 24, 0.75, ACCENT)
        out = HERE / "sessions" / f"{datetime.now():%Y%m%d-%H%M%S}.json"
        out.parent.mkdir(exist_ok=True)
        with out.open("w") as log:
            json.dump({"reps": [vars(r) for r in reps], "cues": coach.history}, log, indent=1, default=float)
        return self.hold(c, 3, keys=(32, 13, ord("r")))

    # --- flow -----------------------------------------------------------------------------------
    def run(self):
        try:
            k = self.intro()
            while True:
                if k != 13:
                    self.example()
                self.countdown()
                k = self.results(*self.live())
                if k == ord("r"):
                    k = 13
                if self.a.headless:
                    break
        except KeyboardInterrupt:
            pass
        finally:
            if self.writer:
                self.writer.release()
            if self.cap:
                self.cap.release()
            if self.pose is not None:
                self.pose.close()
            cv2.destroyAllWindows()


def main():
    load_env()
    ap = argparse.ArgumentParser()
    ap.add_argument("--exercise", default="squat", choices=["squat", "pushup"])
    ap.add_argument("--voice", default="off", choices=["off", "say", "elevenlabs"])
    ap.add_argument("--target", type=int, default=8, help="reps in your set")
    ap.add_argument("--source", default="0", help="camera index or a video to stand in for the camera")
    ap.add_argument("--model", default="full", choices=list(MODELS))
    ap.add_argument("--headless", action="store_true")
    ap.add_argument("--out", help="record the whole flow to this mp4")
    App(ap.parse_args()).run()


if __name__ == "__main__":
    main()

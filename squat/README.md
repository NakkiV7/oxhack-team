# Form tracker and guided demo: squats and push-ups

MediaPipe pose → hip travel + joint geometry → green / amber / red skeleton, a side panel with
reps, live metric bars, tempo, fault tally and per-rep log, and text cues from a single
non-interrupting coach channel (swap `Coach(speak=...)` for ElevenLabs later). `--log reps.json`
dumps every rep's worst values, timings and faults; this is the record that goes to Tiger Data.

**Rep counting** uses vertical hip travel as a fraction of standing leg length (hip height above
the ankle, so camera pans cancel), which works from any angle. The 2D knee angle only confirms a
descent, so walking toward the camera is not a rep. Shallow dips are shown but not counted.
Joints below 50% visibility are ignored; with feet out of frame the tracker still counts but
warns and skips the knee metrics.

**Demo video**: annotate a clip, then add a spoken cue track and re-encode to H.264:

```bash
../.venv/bin/python main.py --source clip.mp4 --headless --out annotated.mp4 --log reps.json --caption "Footage: <credit>"
../.venv/bin/python demo.py --video annotated.mp4 --log reps.json --out demo.mp4            # free macOS voice
../.venv/bin/python demo.py --video annotated.mp4 --log reps.json --out demo.mp4 --voice elevenlabs   # needs ELEVENLABS_API_KEY in squat/.env
```

`eval.py CLIP_DIR --plots out/` scores every clip in a folder and prints a hip-travel sparkline
per clip; use it after changing any threshold. `main.py --record raw.mp4` saves the raw camera
feed so a failing session can be replayed with `--source raw.mp4`.

**Guided demo** (what to show judges): title screen, the example set with the coach's voice, a
countdown, your own set against a target, then a results screen. Session logs land in `sessions/`.
One program, one UI, two exercises:

```bash
cd squat && ../.venv/bin/python app.py                      # squats;  --target 8, --voice elevenlabs|say|off
cd squat && ../.venv/bin/python app.py --exercise pushup    # push-ups
```

Every tool takes `--exercise squat|pushup`. An exercise is one module (`squat.py`, `pushup.py`) that
exposes `Analyzer`, `METRICS`, `RANGE`, `PRIMARY`, `segments()`, `LINES`, `EXAMPLE` and `HINT`; the app,
panel, cue channel, voice, eval harness and demo renderer are shared. `pushup.py` is a port of the
browser prototype's `prototype/pushup/pushup.mjs` (same variations, thresholds, side pick, smoothing and
hysteresis), so the two push-up paths agree; keep them in step.

```bash
python -m venv .venv && .venv/bin/pip install -r requirements.txt
curl -sSLo squat/models/pose_landmarker_full.task https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_full/float16/latest/pose_landmarker_full.task
cd squat && ../.venv/bin/python main.py            # webcam
../.venv/bin/python main.py --source clip.mp4 --out annotated.mp4 --log reps.json
```

| Signal | View | Green | Amber | Red | Cue |
|---|---|---|---|---|---|
| Depth: hip below knee, in thigh lengths | both | ≥ -0.10 (parallel) | ≥ -0.35 | shallower | "Deeper…" |
| Torso lean from vertical | side | < 40° | < 55° | more | "Chest up" |
| Knee width / ankle width | front | ≥ 0.85 | ≥ 0.70 | less | "Knees out" |
| Hip tilt minus shoulder tilt (weight shift) | front | < 12° | < 18° | more | "Even weight on both feet" |

A rep with torso lean over 80° (side view) is treated as a hinge or pick-up and not counted. A rep
needs every visible leg to bend, so a single-leg lift is not a squat, and the hip must be inside the
frame, so someone leaning into the camera is not one either.
| Descent time | both | | | < 0.45 s | "Control the way down" |
| Ascent time | both | | | > 2.2 s or 1.6× your fastest | "You're slowing down" |

Thresholds live at the top of `analyzer.py`; the ascent-time trend is the hook for the
"push to failure / back off" logic once watch heart rate is fused in.

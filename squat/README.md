# Squat form demo

MediaPipe pose → joint angles → green / amber / red skeleton, rep counting, and text cues
from a single non-interrupting coach channel (swap `Coach(speak=...)` for ElevenLabs later).

```bash
python -m venv .venv && .venv/bin/pip install -r requirements.txt
curl -sSLo squat/models/pose_landmarker_lite.task https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/latest/pose_landmarker_lite.task
cd squat && ../.venv/bin/python main.py            # webcam
../.venv/bin/python main.py --source clip.mp4 --out annotated.mp4
```

| Signal | View | Green | Amber | Red | Cue |
|---|---|---|---|---|---|
| Depth (min knee angle per rep) | both | ≤ 95° | ≤ 115° | shallower | "Deeper…" |
| Torso lean from vertical | side | < 40° | < 55° | more | "Chest up" |
| Knee width / ankle width | front | ≥ 0.85 | ≥ 0.70 | less | "Knees out" |
| Left vs right knee angle | front | < 12° | < 20° | more | — |
| Descent time | both | | | < 0.45 s | "Control the way down" |
| Ascent time | both | | | > 2.2 s or 1.6× your fastest | "You're slowing down" |

Thresholds live at the top of `analyzer.py`; the ascent-time trend is the hook for the
"push to failure / back off" logic once watch heart rate is fused in.

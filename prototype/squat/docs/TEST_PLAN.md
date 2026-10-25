# Test plan

What is checked automatically, what was checked by hand, and how to re-check after changing anything.

## Automated

`npm test` runs 39 node checks with no network and no model download:

- `test/ask.test.mjs`: the coach Q&A guardrails (shared with the push-up prototype).
- `test/tiger-stream.test.mjs`: the Tiger batch validation, the ingest against a fake pool (frames, reps, forecasts, outcomes), the strict-TLS pool guard and the migration files (see [TIGER.md](TIGER.md)).
- `test/hrt.test.mjs`: the tempo forecaster (target boundaries, past-only features, two-rep horizons and exclusions, shadow and coaching actions, cooldown, outcome linkage, immutability, parity with the offline definition); see [HRT.md](HRT.md).
- `test/squat.test.mjs`:
  - angle and grade helpers;
  - a synthetic side-on figure whose hip drops along a sine profile: three full squats count three and are clean; a shallow dip is listed but not counted; a tiny wobble is ignored; a rep under half a second does not count; bending at the hips with the torso folded is a hinge, not a squat; hallucinated hips below the frame are rejected; standing closer to the camera re-baselines instead of counting; the half-squat variation grades a shallow rep good while the standard one does not;
  - **one real clip**: `test/fixtures/kb_racked_squat_01.json` holds the MediaPipe landmarks of a five-rep kettlebell racked squat (Cavemantraining, CC BY-SA 4.0). It must count exactly 5, all good form.

## Parity with the Python reference

`squat.mjs` is a line-for-line port of [`squat/squat.py`](../../../squat/squat.py). The Python side has the evaluation harness (`squat/eval.py`) and was tuned on 16 Creative Commons clips plus a webcam session. On identical landmark input the two implementations agree on all 17 clips:

| Clip | Reps |
|---|---|
| kb_side (beach, side, deep) | 6 |
| kb_racked_squat (low angle) | 5 |
| squat_frontal_raise (gym, side) | 6 |
| demo_front (barbell, three-quarter) | 2 |
| goblet_squat_kb (three-quarter) | 2 |
| overhead_kb_squat_single_arm (front) | 16 |
| half_squat_home_cdc (320×240 webcam-style, half squats) | 6 |
| team webcam session, 2:41, three testers | 21 |
| nine other clips with cuts, jumps, pistols, an animation and a tutorial | as the reference |

To rerun the comparison after a change: dump landmarks for the clips with the Python wrapper (see the snippet in the repository history under "parity"), run a node script that feeds each clip's frames to `RepCounter` with `aspect = width / height` and `t = frame / fps`, and compare counts with `squat/eval.py` on the same folder. Any difference means the port drifted from the reference.

## Browser checks done by hand

- Single pass of the 50 s side clip through **Upload video**: 6 of 6 counted, all good form, cues and tempo trend shown.
- A 15 s clip on loop: counting continues across loops; one rep per loop is typically lost at the jump back to the start, which is a property of looping, not of the counter.
- Spoken coach during a replayed set: "1, 2, 3", a motivational line, "4, 5, 6", a second line, each played to the end before the next; all lines served from the cache after the first synthesis.
- Tutorial dialog renders both videos and steps in light and dark themes; videos pause when the dialog closes.
- Theme switch persists across reloads.
- Tempo forecast, held-out replay of the raw six-rep side clip with *pause at forecast*: the clip played once, paused at the forecasts after reps 3 and 4 with the status line naming the rep, resumed on the Pause button, ended the set itself at the end of the clip; "What we anticipated" read both forecasts back from Tiger with the observed outcome (rep 5 outside the range) and lead times of 16.4 s and 8.5 s; the Evidence dialog drew the stored timeline with the onset marker. Shadow mode throughout; with the frozen threshold no cue was due.
- Tiger Data card with the team's service configured: the replayed side clip streamed 1,266 frames and 6 reps, the card's counters and sparkline updated every two seconds from the database, End workout wrote the end mark, Compress now converted the closed chunk. Same pass on the push-up page (6,083 frames, 24 reps). Details and numbers in [TIGER.md](TIGER.md).

Not yet checked by hand: a live camera session in the browser on this machine, and a phone client against the squat state.

## How to tune a threshold

1. Change it in `squat/squat.py` first and run `squat/eval.py CLIP_DIR` on the reference clips; every clean set must still count exactly.
2. Mirror the change in `squat.mjs` (`VARIATIONS`, `METRICS` or the constants at the top).
3. `npm test`; the real-clip fixture must still count 5.
4. Rerun the parity comparison above.
5. Update the References dialog text in `index.html` and the thresholds table in [ALGORITHM.md](ALGORITHM.md).

## Known gaps

- Front-view thresholds (knees, balance) were tuned on fewer clips than side-view ones.
- No labelled push-up or squat form-error dataset with real video was available; form grades rest on angle rules checked against clips, not on a trained classifier.

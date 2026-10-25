# Push-up CV test plan (feat/pushup-cv)

Goal: measure how well the MediaPipe-based push-up counter and posture cues work on real side-view clips, then tune the push-up policy (thresholds, cue rules) without duplicating the shared pose pipeline.

Status: plan only. The Spottr shared foundation (`Shared/Core/PoseGeometry.swift`, `RepCounter.swift`, `Exercise.swift`) is not available yet, so numbers below are proposals to agree with the squat owner. The untuned prototype in this folder (`pushup.mjs`) is the starting point for thresholds.

## 1. Scope

| In scope | Out of scope |
|---|---|
| Count error per clip (full, partial, missed, extra reps) | Elbow flare, scapular form (2D side view cannot judge) |
| Cue behaviour: right cue, right time, no spam | New pose models or a second pipeline |
| Tracking loss, occlusion, multiple people | Medical or form-certified claims |
| Overlay alignment on a real iPhone | CI/CD (not used on this project) |

Variations to cover: standard first, then knee, incline, wall (thresholds in `VARIATIONS`).

## 2. Consent and data handling

- Only consented participants. Written or recorded consent that says: clips are used to test the app, who sees them, where they are stored, how to withdraw.
- No faces needed: frame side-on, body only; crop or blur if a face is visible.
- Clips live in a private location outside the repo (never committed). Name them by clip ID only, no names.
- Keep a consent log (participant ID, date, consent given, deletion requested) separate from the clips.
- Provider keys stay in ignored local config; clips are never sent to a cloud provider.

## 3. Recording setup (supported setup to document)

- Camera at the user's side, 2 to 3 m away, whole body in frame, landscape or portrait fixed (record which).
- Camera at about hip height, still (tripod or prop), no zoom.
- Plain background, good light, fitted clothing for the baseline set. Loose clothing is its own clip.
- 30 fps, at least 720p. Note device, orientation, lens.
- Each clip starts with 2 s standing or plank, ends with 2 s rest.

## 4. Clip matrix

Per clip the recorder writes the **ground-truth rep count** (counted by a human from the video, ideally two people) and the **expected cues**.

| ID | Scenario | What it checks | Ground truth to record |
|---|---|---|---|
| A1 | 10 full reps, good form, standard | Baseline count | 10 reps, 0 cues |
| A2 | 10 full reps, slow tempo | Tempo robustness | 10, 0 cues |
| A3 | 10 full reps, fast tempo | Frame-rate/smoothing limits | 10, 0 cues |
| B1 | 10 attempts, all partial (elbows stop above depth) | Partial reps not counted | 0 counted, "not low enough" cue per attempt |
| B2 | Mix: 5 full + 5 partial, alternating | Mixed counting | 5 counted |
| C1 | Hips sagging for several reps | Body-line cue | Reps counted or flagged per policy, sag cue |
| C2 | Hips piked high | Body-line cue (other direction) | Pike cue |
| C3 | Good form then form breaks mid-set | Cue timing, recovery | Cue appears at break, clears after fix |
| D1 | User steps out of frame mid-set, returns | Tracking loss; no phantom reps | Reps before + after only |
| D2 | Brief landmark dropout (hand or object blocks camera briefly) | Short loss tolerance | No change in count |
| D3 | Camera pointed front-on instead of side | Unsupported setup behaviour | Documented result, no crash |
| E1 | Occlusion: near arm hidden behind torso (side view) | Side auto-pick | Count matches |
| E2 | Occlusion: furniture or bench between camera and legs | Body-line with missing ankle/knee | Documented cue behaviour |
| F1 | Second person walks through the background | Multiple people, wrong-person lock | Count only for the exerciser |
| F2 | Second person exercising next to the first | Which person is tracked | Documented limitation or rule |
| G1 | Knee / incline / wall sets (10 reps each, good form) | Per-variation thresholds | 10 each |
| G2 | Different body types, sleeves, loose top (3+ participants) | Generalisation | 10 each |
| H1 | Pause the session mid-set, resume | Pause guard | No reps counted while paused |
| H2 | Switch source (camera to video, or restart) mid-set | Source/generation guard | Stale frames from old source ignored |

Minimum: at least 3 participants for A1, B2, C1, G2; 1 participant is enough for the stress clips (D, E, F, H).

## 5. Metrics

Per clip:

- **Count error** = counted − truth. Report signed (over or under count) and absolute.
- **Rep match**: each counted rep matched to a truth rep by time (within ±0.5 s). Gives false positives (counted, no real rep) and false negatives (missed).
- **Cue precision**: cues shown that match an expected issue / all cues shown.
- **Cue recall**: expected issues that produced a cue / all expected issues.
- **Cue latency**: seconds from the issue starting to the cue appearing.
- **Cue spam**: same cue repeated more than once per rep, or flicker (appears/disappears faster than 1 s).
- **Tracking uptime**: fraction of frames with a usable pose.

Across clips: mean and worst absolute count error, and the same grouped by scenario.

Proposed pass criteria (to agree with the team before running):

| Metric | Target |
|---|---|
| Count error, clean side-view clips (A, G) | within ±1 rep per 10, and ≤ 5% mean absolute error |
| Partial reps counted (B) | 0 |
| Phantom reps from tracking loss / other people (D, F1) | 0 |
| Cue precision / recall (C) | ≥ 80% / ≥ 80% |
| Cue latency | ≤ 1.5 s |
| Pause / source / generation guards (H) | 0 reps counted from paused or stale frames |

## 6. Procedure

1. Record clips per section 3 and fill the ground-truth sheet (section 8) before running the app, so results cannot bias the labels.
2. Run each clip through the app **file/video source** with the baseline thresholds. Log counted reps with timestamps and every cue with timestamps (export from the app or screen-record).
3. Compute section 5 metrics per clip; fill the results table.
4. Tune **only the push-up policy** (elbow `up`/`down`, body-line minimum, debounce/hold frames, cue cooldown, minimum visibility for landmarks). No changes to the shared pose pipeline; if a shared change looks necessary, raise it with the squat owner first.
5. Re-run the whole set after each tuning round. Record the thresholds used. Keep a held-out set (e.g. one participant never used for tuning) to confirm the tuned values generalise.
6. Repeat on a real iPhone with the live camera for a short subset (A1, C1, D1, H1, H2).

## 7. Real iPhone overlay alignment

- Run on a physical iPhone, not only the simulator. Record model, iOS version, orientation, front or back camera, mirroring.
- With a person standing still, check the drawn joints against the body at 5 points (shoulder, elbow, wrist, hip, ankle). Take screenshots in portrait and landscape.
- Measure the offset in pixels or as a fraction of body height; flag anything above about 3% of body height, especially after rotating the device, switching cameras, or with aspect-fill vs fit video.
- Check mirrored front-camera behaviour and that left/right side pick still follows the correct body side.
- Record any lag between body motion and overlay (count frames or note by slow-motion screen recording).

## 8. Results template

Ground truth sheet:

| Clip | Participant | Variation | Device/orientation | Truth reps | Expected cues (type, time) | Notes |
|---|---|---|---|---|---|---|

Results:

| Clip | Counted | Error | False pos | False neg | Cues shown | Cue precision | Cue recall | Latency | Spam | Uptime | Thresholds |
|---|---|---|---|---|---|---|---|---|---|---|---|

Tuning log:

| Round | Change (parameter: old → new) | Reason | Mean abs count error | Cue precision/recall |
|---|---|---|---|---|

## 9. Deliverables

- Filled results and tuning log.
- Final push-up policy values (in `Exercise.swift` when the foundation exists) plus exercise-specific tests that encode the clip scenarios as landmark sequences (partial rep, tracking loss, pause, source switch).
- "Supported setup and limitations" doc: side-on camera at 2 to 3 m, one person in frame, lighting, clothing, what happens on tracking loss and with multiple people, no elbow-flare or scapular judgement, results per device.

## 10. Open questions for the team

- Where are clips stored, and who holds the consent log?
- Agree pass criteria in section 5.
- Which person does the tracker follow when two people are in frame (largest, closest, first locked)? This is a shared-pose decision with the squat owner.
- Does the shared counter already have the pause/source/generation guards, and how are they tested?

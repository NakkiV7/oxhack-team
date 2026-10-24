# Spottr: personal learning and training

Design proposal, 24 October 2026. No personalised predictor has been implemented or trained.

Omar prefers custom model training when Leeds compute is available. Use Calder/AIRE for a bounded, reproducible public-data training/evaluation job; update the user's small calibration layer after each eligible set on the phone/backend. Those are different jobs: shared model development can use GPUs; personal adaptation should be cheap and immediate.

## What gets learned

Keep planned reps remaining separate from estimated reps in reserve. `12 planned - 8 completed = 4 left` is exact session progress and belongs on the Arduino. A prediction of how many more clean reps a person could perform is uncertain and exercise-specific. Do not silently substitute one for the other.

After a set, ask “How many more could you do?” with 0 / 1 / 2 / 3+ / Skip. Ask why they stopped: target reached, voluntary stop, form slipping, unable to complete another rep, or discomfort. Do not preselect an answer in the real app. Repeated usage supplies personal evidence; it does not automatically establish ground truth.

Capture exercise/variation, rep phase, normalized range of motion, concentric/eccentric timing, within-set slowing, repetition count, set/rest history, timestamped HR with freshness/quality, and user feedback. Treat sleep/resting HR as dated context, not live measurements. Track signal loss and camera changes.

## Small online updates

1. Train a compact exercise/motion encoder offline using eligible public data with documented labels. Omar selected existing open-source models for the first app and his own push-up testing, with custom landmark-detector training also in scope later. Start with MediaPipe Pose Landmarker Lite and separately test its landmark quality, rep counting and form rules. Preserve a simple feature/baseline model for comparison.
2. Freeze the encoder during a set. Keep a small per-person, per-exercise ordinal/survival calibration head. Initialise it conservatively with an explicit cold-start state; show no numerical reserve prediction until evidence and uncertainty checks support it.
3. At set end, make a bounded update to the personal head from quality-approved observations and feedback. For a reported 3+ reserve label use an interval, not an exact 3. Self-reported reserve labels receive lower weight than an observed, explicitly characterised endpoint; all remain provenance-tagged.
4. A voluntary or planned stop is a censored endpoint: it says the person reached at least that count, not that their maximum is that count. Form breakdown is a technical endpoint distinct from physiological failure. Discomfort never becomes an “optimal fatigue” example or a reason to recommend more effort.
5. Retain a bounded calibration buffer, uncertainty and model version. Limit parameter drift; compare predictions against later eligible observations, detect shifts and roll back the head if held-out/prequential error worsens. Skip updates when the source/time alignment or label quality is inadequate.

This is continual adaptation of a small prediction layer, not unbounded retraining of the whole model. Predict before observing the outcome, then score it, then update. Log the order so evaluation cannot accidentally use the same endpoint for training and testing. Evaluate by session/participant, including cold start and changes of exercise/variation. Respect any forgetting policy for old feedback.

## What HPC can and cannot supply

Use `sbatch`, explicit CPU/memory/GPU requests, an isolated project directory, fixed input manifests and a short smoke job before training. Follow `/Users/scsoc/.codex/hpc/LEEDS_HPC.md` and `/Users/scsoc/.claude/AI.md`. No personal biometric data are sent to Leeds HPC; start with public data whose terms permit the intended computation. User-specific adaptation can stay on the device or separately authorised backend.

MM-Fit can train/validate movement recognition and rep segmentation. UI-PRMD adds small, staged squat-quality labels. Neither supplies physiological failure ground truth. Compute cannot fix that missing target. A reserve head needs a documented appropriate public endpoint source or prospectively collected user feedback; a landmark/tempo model alone must not be presented as a validated failure predictor.

Before a job: inspect live access/queue/resources, finalise the target and split, inspect data inventory and licences, run the exact schema on a small eligible subset, then submit a bounded experiment. Access and job submission are not training success; completed logs and independent evaluation are required. No job was submitted during this design revision.

## Evidence behind the approach

Individual RIR–velocity relationships have shown better fit than general relationships in a controlled free-weight back-squat study, but that does not validate monocular bodyweight exercise estimates: [Jukic et al., 2024](https://doi.org/10.14814/phy2.15955). Another controlled study found substantial variation across sets, loads and exercises and poor transfer of first-set velocity thresholds: [Mansfield et al., 2023](https://doi.org/10.1080/17461391.2023.2235314). These support evaluating personal calibration and uncertainty; they do not establish that the proposed online algorithm works.

## Arduino

UNO Q display rotates between **planned reps left**, **sets remaining**, and a concise coach message. Use its 8×13 matrix for two-digit counts/brief glyphs, scroll longer messages, and use an available RGB LED for cue priority. Preserve system indicators. A stop or stale event clears encouragement; disconnect shows an unknown/idle pattern. Messages have a session ID, sequence number and expiry so late cues cannot restart an ended set. No prediction is formatted as a guaranteed remaining capacity.

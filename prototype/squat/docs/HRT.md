# HRT: short-horizon tempo forecasting

What the forecast feature is, how it was specified before any model was fitted, what the evidence says today, and how to demonstrate and reproduce it. Code: [`hrt.mjs`](../hrt.mjs) (shared logic, used live and offline), [`hrt/train.mjs`](../hrt/train.mjs) (experiment), [`hrt/build_dataset.mjs`](../hrt/build_dataset.mjs) (dataset), [`hrt-evidence.mjs`](../hrt-evidence.mjs) (evidence dialog), Tiger tables in [`prototype/shared/db/003_hrt.sql`](../../shared/db/003_hrt.sql). Paper: `docs/hrt-paper/`.

This is not an injury predictor, a medical assessment, or a validated predictor of muscular failure. It forecasts whether a tracker-derived tempo target will be missed.

## 1. Where things live (capability map)

The task brief was written for the native app. The feature was built into the squat browser prototype because that is where the inputs exist:

| Needed | Exists in | Notes |
|---|---|---|
| Lowering and rising duration per rep | `squat.mjs` rep record (`tDown`, `tUp`, 0.1 s) | The native core measures total rep time only |
| Rep events, attempts that did not count | `RepCounter.reps` | Attempts carry `counted: false` |
| Pose quality signals | `RepCounter.live`, `warn` | Depth is NULL when knees or feet are out of frame |
| Cue scheduler with priority, cooldown, expiry, stop | page speech queue (`say`) | Forecast cue uses priority 1 |
| Persistent store | Tiger Data `spottr_cv` (see [TIGER.md](TIGER.md)) | Frames, reps, workouts; now predictions and outcomes |
| Gemini, ElevenLabs | server `/say`, coach | Not used for the numerical forecast |
| Biometrics | none recorded | Watch and Presage have no live data; the model works without them |
| Recordings | 17 landmark dumps of CC clips and the team session | Development material; held-out recordings pending |

Verified before building: rows arrive (TIGER.md), workout and rep identifiers join, timestamps are the page's clock in seconds (replays use video time, so offline and live agree), replays are deduplicated by natural keys, and `received_at` is kept apart from `measured_at` so late rows are distinguishable from live ones.

## 2. The prediction task (frozen 25 October 2026, before fitting)

- **Unit**: a counted squat rep `t` in one set. `d_t` = lowering duration (first frame past 15% hip travel to the bottom).
- **Programme target** `[L, U]`: "Controlled lowering, 0.6 to 1.5 s" by default (a second programme, 2 to 4 s, is selectable). A target is a prescription, not a definition of correct technique. `v_t = 1` when `d_t` is outside `[L, U]`.
- **Outcome** `Y_t = 1` if `v = 1` for rep `t+1` or `t+2`; `Y_t = 0` if both are counted reps that meet the target.
- **Eligible origin**: at least 3 counted reps, `v_t = 0`, same variation and target throughout the set. The forecast is emitted at the rep boundary (measured latency below 1 ms), so the horizon is never already spent.
- **Excluded horizons**, never labelled negative: `set_ended` (fewer than two further counted reps), `invalid_rep_in_horizon` (an attempt that did not count inside the next two attempts), target or variation change (a change starts a new set in the page).
- **Features** (`f1`, window 3, past only): latest lowering duration, median of the last three, change against the median of the previous reps, range of the last three, normalised distance to the nearer edge of the target, latest rising duration and its change, rep number, elapsed time since the first rep began, depth change against the previous reps, and a flag when depth is not judged. No personal history across sessions yet (cold start is the baseline state).
- **Model**: L2 logistic regression on standardised features, intercept unpenalised, λ chosen by nested leave-one-recording-out log loss from {0.01, 0.1, 1, 10}.
- **Baselines**: A constant (Laplace-smoothed training prevalence); B set position only; C the page's existing slow-ascent rule (ascent over 2.2 s or 1.6× the median of earlier ascents) as a deterministic alert; D the model above. Ablations: position, tempo, tempo + pose.
- **Policy**: alert when `p ≥ τ`, at most one alert per horizon (2 reps). `τ` maximises event recall subject to at most **0.5 false alerts per monitored set** (a product choice). Events are onsets: the first violating rep after a compliant one; a warning matches an onset in its horizon once; lead time is the time from the origin rep's end to the onset rep's end.
- **Splits**: recordings are the groups. All 17 current recordings are development material (the counter was tuned on them). Held-out recordings made by the team go to the locked test split and are evaluated once.
- **Metrics**: Brier (primary), log loss, average precision, event recall at the budget, false alerts per set, lead time, coverage; paired cluster bootstrap over recordings (1000 resamples, seed 7) for the differences. Primary comparison: D against A on Brier; policy: D against C on recall under the budget.

## 3. Evidence today

Development set: 14 recordings with counted reps, 78 counted reps, **22 eligible observed origins, 8 positive**, in 8 recordings (the others are too short). Out of fold:

| model | Brier | log loss | recall at budget | false alerts/set |
|---|---|---|---|---|
| A constant | 0.479 | 1.19 | 0 | 0 |
| B set position | 0.701 | 6.96 | none within budget | |
| D tempo + pose | 0.537 | 1.36 | 0 (τ = 0.95) | 0 |
| C slow-ascent rule | | | 0.17 (1 of 6 events) | 0 |

Bootstrap difference in Brier, D − A: +0.048 [0.007, 0.085]. **The model is worse than the constant baseline on this data, and no threshold meets the budget, so the deployed policy stays silent.** The existing rule catches one event in six with no false alerts. The regression fallback (next lowering duration) is also lost by the ridge model: MAE 0.87 s against 0.25 s for last-value persistence.

This is the expected result for 22 examples from eight unrelated clips of different people, loads and angles. It is reported as such in the evidence dialog and the paper. What is demonstrable now is the infrastructure: forecasts at every eligible origin in shadow mode, persisted before their outcome, resolved and scored, read back into the review and the evidence panel.

Held-out recordings change this. The plan: each teammate records two or three ordinary sets side-on; sets from two people join the development split (more origins for selection), sets from the other two are the locked test. The assignment is written into `hrt/data/recordings.json` before any of them is looked at.

## 4. Run-time behaviour (page)

1. The counter finishes a rep. `Forecaster.onRep` checks eligibility, builds past-only features, predicts, applies the policy, and returns an immutable forecast record plus any outcomes the new rep resolves.
2. The forecast is queued and flushed to Tiger at once (`spottr_cv.prediction`); outcomes follow when the horizon closes (`spottr_cv.prediction_outcome`). The model is registered once in `spottr_cv.model_run`.
3. **Shadow mode** (default): forecasts are recorded and shown in "Why this?", nothing is spoken. **Cue me** turns on coaching mode: a forecast at or above the threshold speaks one cue through the existing queue, with one cue per horizon; outcomes after a cue are flagged `coached` and the review labels them "observed after coaching".
4. Card states: learning your pace (n of 3), tracking your next reps, last rep outside the range, cue, framing problem (hips and knees not tracked), prediction unavailable (no model), set finished. The card changes only at rep boundaries. No red styling.
5. "Why this?" shows the forecast criterion, the recent lowering durations against the target, the trend, the model id, and the probability labelled preliminary and uncalibrated.
6. End workout: "What we anticipated" in the summary is rendered from the stored rows: each forecast, whether it would have cued, what was observed, the lead time, horizons left incomplete, and onsets that had no eligible warning.
7. **Evidence** button: the dialog renders `hrt/results.json` (baselines, bootstrap, calibration, frontier, ablations, dataset card, reproducibility) and the stored timeline of the last workout.

## 5. Demo

**Part A, forecasting evidence (replay, shadow mode).** Tick *pause at forecast*, upload a held-out clip (a raw recording, not the tutorial video, which has the overlay burned in). The page pauses the video at each forecast before the next reps play; the card and "Why this?" show the forecast and its evidence cutoff. Resume to reveal the next two reps; the card and later the review show the recorded outcome and lead time. Then open **Evidence**. Everything the replay emits uses only the prefix that has played, because the counter has not seen the rest.

**Part B, live coaching.** Start the camera. The card collects the baseline, then tracks. With the current policy no cue fires (nothing met the budget); say so and show the monitoring state, then end the set and open "What we anticipated". If the held-out evaluation later selects a usable threshold, tick *cue me* and the same flow speaks the cue.

**Ninety seconds**: "Every rep's lowering time goes into Tiger. After three reps the model forecasts whether one of the next two will leave the programme range. Here it forecast after rep 4, we reveal reps 5 and 6, and the stored outcome says rep 6 missed with a 4-second warning. The evidence panel shows this honestly: on 22 development origins the model does not beat a constant, so the coach stays quiet; the held-out test is what decides it."

## 6. Reproduce

```bash
cd prototype/squat
node hrt/build_dataset.mjs <dir of landmark JSON dumps>   # writes hrt/data/reps.csv and landmark hashes
node hrt/train.mjs                                         # writes hrt/model.json, hrt/results.json, split manifest
npm test                                                   # 39 offline checks incl. 15 for the forecaster
```

Landmark dumps are produced from clips with the Python reference (`squat/` at the repository root, MediaPipe full model); their SHA-256s are in `hrt/data/landmark-hashes.json`. Provenance and split for every recording are in `hrt/data/recordings.json`.

## 7. Tests

`test/hrt.test.mjs`: target boundaries, three-rep cold start, past-only features (future reps cannot change an origin), missing depth, eligibility, two-rep horizons with pending, set-ended and invalid-attempt exclusions, the slow-ascent rule, probability bounds and NaN imputation, shadow versus coaching actions, cooldown, silent forecasts, outcome linkage and lead time, immutability of forecast records, feature parity between the live forecaster and the offline definition, and cue text without a probability. `test/tiger-stream.test.mjs` covers validation and single-write semantics of prediction and outcome rows. Test counts measure software behaviour, not predictive accuracy.

## 8. Not done, and why

- No held-out evaluation yet: no test recordings exist. The evidence dialog says "not yet evaluated" rather than guessing.
- No calibration fitted: too few events per class.
- No personal history across sessions, no Watch or Presage features: no such data recorded.
- No survival model: future work.
- Native app: not touched; this feature lives in the browser prototype where the measurements are.

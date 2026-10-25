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

## 2. The prediction task (frozen 25 October 2026 06:30, before any held-out evaluation)

**Protocol log.** The specification was revised three times on development data, each time before any held-out recording existed, and each revision is recorded here with its reason:

| when | change | why |
|---|---|---|
| 25 Oct 03:40 | v1: fixed programme range 0.6 to 1.5 s, any single rep outside the range within the next 2 reps, phase durations to 0.1 s | the task brief's preferred target |
| 25 Oct 05:40 | relative target added and made primary; durations to 0.01 s; set-baseline drift features (f2); λ grid to 100 | the author's natural pace sits on the fixed 0.6 s edge, so labels there were rounding noise; the apparent gain on 56 origins vanished at 520 |
| 25 Oct 06:05 | label v2: the event is the **first sustained departure** of the set (a rep outside the band with at least two of three consecutive reps outside); origins after it are excluded | long sets showed the tempo shifts regime once and flickers at the boundary afterwards; half the single-rep "onsets" were blips at the noise floor |
| 25 Oct 06:30 | horizon 5 reps primary (2 reported); prespecified one-feature drift rule added as policy E; cross-validation grouped by person | a drift that builds over tens of reps gives two positive origins at a two-rep horizon; three of the Creative Commons sets share one subject |

- **Unit**: a counted squat rep `t` in one set; a set ends at a rest pause longer than 12 s. `d_t` = lowering duration (first frame past 15% hip travel to the bottom), to 0.01 s.
- **Bounds**: relative (primary, `relative-v1`): within 25% of the median lowering duration of the set's first three counted reps, frozen once they exist. Fixed (`controlled-v1`): 0.6 to 1.5 s. A second fixed programme (2 to 4 s) is selectable. None defines correct technique. `v_t = 1` when `d_t` is outside.
- **Event** (`tempo-v2`): the set's first sustained departure, at the first rep `k` with `v_k = 1` and at least two of reps `k..k+2` outside. One event per set at most.
- **Outcome** `Y_t = 1` if the first departure starts at any of reps `t+1 .. t+5`; `Y_t = 0` when those reps are observed and none starts one. A rep inside the band rules itself out immediately; a rep outside needs the two after it to tell a blip from a departure.
- **Eligible origin**: at least 3 counted reps, `v_t = 0`, no departure yet, same variation and target throughout the set. Forecasts are emitted at the rep boundary (measured latency under 1 ms).
- **Excluded horizons**, never labelled negative: `set_ended`, `invalid_rep_in_horizon` (an attempt that did not count inside the deciding window), `after_departure`.
- **Features** (`f2`, window 3, past only): latest lowering duration, median of the last three, change against the median of the previous reps, range of the last three, drift of the last-three median from the set's first-three median, normalised distance to the nearer bound, the same for the rising phase (latest, change, drift), rep number, elapsed time since the first rep began, depth change against the previous reps, a flag when depth is not judged. Offline only: the median lowering of the same person's earlier sets (ablation "history").
- **Model**: L2 logistic regression on standardised features, intercept unpenalised, λ by nested leave-one-person-out log loss from {0.01, 0.1, 1, 10, 100}.
- **Baselines and policies**: A constant (Laplace-smoothed training prevalence); B set position only; C the page's slow-ascent rule as a deterministic alert; D the model above; E a prespecified one-feature **drift rule**: alert when the last-three median lowering has drifted from the first-three median by at least θ of it (θ chosen under the budget like τ). Ablations: position, tempo, tempo + pose, + history.
- **Policy**: alert when `p ≥ τ` (or drift ≥ θ), at most one alert per horizon. τ and θ maximise event recall subject to at most **0.5 false alerts per monitored set**. A warning matches the departure once if it precedes it within the horizon; lead time runs from the origin rep's end to the departure rep's end. The deployed artifact carries whichever of D or E recalled more on development data.
- **Splits**: groups are people where known (several recordings of one person stay together), recordings otherwise. Everything to date is development material. Held-out recordings of other people go to the locked test split, assigned in `hrt/data/recordings.json` before being examined, and are evaluated once for both targets and both horizons.
- **Metrics**: Brier (primary), log loss, average precision, event recall at the budget, false alerts per set, lead time, coverage; paired cluster bootstrap over people (1000 resamples, seed 7). Primary comparisons: D against A on Brier; D and E against C on recall under the budget.

## 3. Evidence today (25 October 06:30)

Development set: 23 recordings of 11 people, 710 counted reps: 16 Creative Commons clips, the team session as three recordings, the author's four webcam sets of 15 fast air squats, and six long YouTube Creative Commons sets (50 to 153 reps; three of them one subject).

Under the relative target and the first-departure label, **only five sets contain a departure**, all in the long sets. At a five-rep horizon that is 15 positive origins of 376 in 7 groups; at two reps, 8 of 401. Out of fold:

| | Brier | AP | recall at budget | false alerts/set |
|---|---|---|---|---|
| A constant | 0.041 | 0.023 | 0 | 0 |
| D tempo + pose | 0.041 | 0.024 | 0 (none within budget) | |
| C slow-ascent rule | | | 0 | 0 |
| E drift rule (θ = 0.23) | | | 0.20 (1 of 5), 5.8 s / 3 reps ahead | 0.43 |

The logistic model cannot learn from five events and matches the constant; the drift rule gives one early warning. On the fixed range at a natural pace almost every rep is already outside (614 of 710 origins ineligible) and the experiment has insufficient data. The earlier single-rep label produced many more "events", and an apparent model win on 56 origins that disappeared at 520: those events were boundary flicker, and that finding is why the label changed.

What is demonstrable now is the infrastructure and the honesty of the evaluation: forecasts at every eligible origin in shadow mode, persisted before their outcome, resolved and scored, read back into the review and the evidence panel, with a frozen protocol and an empty test split. What decides the result is data: each set recorded to natural slowing contributes one event. More long Creative Commons sets are being collected, and the team's own recordings become the locked test.

## 4. Run-time behaviour (page)

1. The counter finishes a rep. `Forecaster.onRep` checks eligibility, builds past-only features, predicts, applies the policy, and returns an immutable forecast record plus any outcomes the new rep resolves.
2. The forecast is queued and flushed to Tiger at once (`spottr_cv.prediction`); outcomes follow when the horizon closes (`spottr_cv.prediction_outcome`). The model is registered once in `spottr_cv.model_run`.
3. **Shadow mode** (default): forecasts are recorded and shown in "Why this?", nothing is spoken. **Cue me** turns on coaching mode: a forecast at or above the threshold speaks one cue through the existing queue, with one cue per horizon; outcomes after a cue are flagged `coached` and the review labels them "observed after coaching".
4. Card states: learning your pace (n of 3), tracking your next reps, last rep outside the range, cue, your tempo has shifted (forecasting stops for the set), framing problem (hips and knees not tracked), prediction unavailable (no model), set finished. The card changes only at rep boundaries. No red styling.
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
node --env-file=.env hrt/build_dataset.mjs <dir of landmark JSON dumps> --tiger   # writes hrt/data/reps.csv and landmark hashes; --tiger adds the app's camera sets
node hrt/train.mjs --target relative --horizon 5           # writes hrt/model-relative.json, hrt/results-relative.json, split manifest
node hrt/train.mjs --target controlled --horizon 5         # the fixed-range artifacts; --suffix -h2 for the two-rep variant
npm test                                                   # 41 offline checks incl. 17 for the forecaster
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

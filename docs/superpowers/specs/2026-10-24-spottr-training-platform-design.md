# Spottr: build your real-life stats

## Intent and decisions

Extend the native local coach into a training companion that helps people choose, complete and understand their training. Preserve the approved white/black design, simple generated pose graphics and fast local set controls. Omar requested session/weekly reports, equipment-free exercises, a visible skill tree, earned attributes, editable AI workout suggestions, live Watch BPM above the timer, richer sensor reports and a later UNO Q side camera. Both manual and camera-tracked sets count toward progression; show their source. This was explicitly confirmed by Omar. Display progression titles such as **Push-ups I–V**, with the variation, pose image and exact target underneath.

Builder choices: interpret “free weights without gym equipment” as bodyweight exercises plus optional household wall/sofa support. Attribute points are game progress, not measured physiological capability. All exercises remain available to explore/practise; challenge unlocks award achievements rather than blocking someone who already knows an advanced exercise. Progression order and targets are editable product defaults, not a universal difficulty or readiness assessment.

Builder check resolved: this milestone is a single-owner hackathon prototype with local history, no account wall and no cross-device cloud sync. Future selected cloud ingestion uses an authenticated installation/user identity; multi-user sign-in and conflict resolution are outside this milestone. This follows the existing demo scope. The reviewer found no other important unanswered questions.

## App shape

- **Today:** current plan, actual exercise-based category (Upper body / Lower body / Core / Conditioning / Mobility / Full body), time and sets; compact library entry. Current six-set squat/push-up routine remains usable.
- **Live:** count, live Watch heart rate above elapsed time, local camera/video and a single text cue. AI tracking badge only for standard push-ups and bodyweight squats until each other variation is validated. Other exercises use explicit manual reps or timed holds, with source badges. Unknown signals stay blank.
- **Progress:** this-week overview, seven-day activity bars, exercise/category breakdown, actual totals and session cards. Each session opens a report with set table, effort/stop reasons, rep tempo when recorded, Watch signal coverage and a timestamped HR chart. Show wrist movement/rotation only if recorded. Do not interpolate missing periods as observed measurements.
- **Skills:** Strength / Stamina / Mobility / Balance points; branching exercise challenges. Neutral white/black unearned nodes, mint completed nodes, restrained amber current challenge. Node detail shows image, Roman-numeral level, movement instructions, requirement and current evidence. No body scores invented by an LLM.
- **Coach:** exercise guidance now; later grounded conversation, report explanations and structured workout proposals. Plan cards have an include control, alternatives and an explicit Add to workout action. Radio controls choose one alternative for a slot; independent exercise inclusion uses checkboxes.

## Initial catalogue and progression

Push-ups I wall → II incline on stable sofa → III knees → IV standard → V close grip. Lower body I glute bridge → II squat → III reverse lunge → IV split squat → V assisted single-leg squat. Core I dead bug → II plank → III side plank. Conditioning I step jacks → II high knees → III mountain climbers. Mobility: cat-cow and hip-flexor stretch. Balance: single-leg stand. Each has an individual generated flat pose graphic; retain the existing six-phase standard push-up/squat guides. Household support is tagged so the planner can exclude it.

Repetition challenges begin with three eligible sets at the node target, accumulated across at least two distinct training dates. Timed challenges use recorded hold seconds instead. Exact thresholds live in a versioned catalogue. A qualifying set must reach its target and must not end for pain/discomfort; reserve feedback is optional and absence is not interpreted as capacity. Repeated saves cannot award points twice. Zero-rep sets, paused/preparation time and imported-video replays do not create unlimited points. Imported video is excluded from earned progress in this milestone; manual logging is trusted self-report and labelled. No injury-prevention or safe-to-failure claim follows from unlocking a node.

Points: modest fixed points per completed eligible set, weighted by the exercise’s declared attributes; daily per-exercise caps prevent farming and penalizing rest. Strength/stamina/mobility/balance totals are deterministic and reproducible from history, not an opaque “fitness score”. This milestone awards 10 points per qualifying set, capped at three sets per exercise per local day; node completion is a visible achievement without a second points bonus. Never remove earned progress for taking rest days. Unlocks are recomputed from facts and catalogue version; retain provenance of manual vs camera evidence.

## Reports and Google AI boundary

Compute statistics locally/SQL first. A `WorkoutFacts` object contains metric IDs, session/set IDs, category, exercise IDs, actual reps/hold durations, timestamps, effort/stop reasons, signal coverage and source. `WeekFacts` uses the person’s calendar/timezone and an explicit week interval; do not compare an incomplete current week with a complete previous week without labelling the window.

Three bounded Gemini jobs:

1. **Session summary:** short headline, up to three insights and one next-session focus, each citing supplied fact IDs.
2. **Weekly summary:** consistency, exercise/attribute mix and observed trends; no invented improvements or physiological conclusions from HR alone.
3. **Workout proposal:** catalogue exercise IDs only, set/repetition or hold targets, rest, explanation/fact references, and optional next-skill IDs. Model sees current tree, recent exposure by movement group, goals, available household support and user feedback. Recent training informs an easier/alternate suggestion; it does not diagnose recovery.

Use Gemini structured JSON output, then validate semantics independently: allowlisted IDs, appropriate units, bounded sets/targets, no unknown/duplicate items, no incompatible equipment, valid evidence references, and no mutation until the person approves selections. Schema compliance does not establish factual correctness. Ignore stale responses using session/generation IDs. Cache summaries by facts + model + prompt version. Network errors preserve useful deterministic reports and the existing workout. No paid calls during ordinary tests; fixtures exercise parsing and rejection. Provider key belongs in the future thin Vultr gateway, never the mobile bundle.

Reference: [Gemini structured outputs](https://ai.google.dev/gemini-api/docs/structured-output).

## Tiger Data: operational backbone

Use one PostgreSQL database for relational profiles/goals/catalogue/skills/workouts/sets plus time-series measurements. Separate hypertables for heart samples, motion samples, pose features and rep events preserve native sampling cadence and units. Include measurement time and receive time, user/session/set IDs, device/source, quality, missingness and model/policy version. Send bounded batches with idempotency keys; ingestion must not block a rep or cue. Preserve raw vectors where enabled rather than pretending 1 Hz magnitude summaries are a full high-rate stream.

Useful product queries: live HR and movement traces; per-set tempo drift and tracking coverage; repeatability across sessions; weekly muscle-group exposure; recent load and user-reported effort; skill progress provenance; observed vs forecast recovery. These make Tiger useful to the person rather than an ornamental sponsor insert.

Continuous aggregates: five-second and minute sensor summaries, per-day/exercise workload and weekly rollups. Serve live charts through real-time aggregation explicitly enabled or a materialized-plus-raw-tail query; do not assume the default includes the newest data. Use columnstore policies for older chunks and retention for raw streams after preserving needed features. Choose a refresh window shorter than raw retention so deleting raw history does not erase older rollups. Benchmark latency, rows ingested and actual storage ratio; do not repeat the advertised 90% compression as a measured Spottr result.

References: [automation policies](https://www.tigerdata.com/docs/build/data-management/about-automation), [data lifecycle](https://www.tigerdata.com/docs/learn/data-lifecycle), [aggregate watermark and retention pitfalls](https://www.tigerdata.com/docs/build/tips-and-tricks/troubleshoot-continuous-aggregates).

## UNO Q side camera: later, without venue Wi-Fi

UNO Q joins the iPhone’s Personal Hotspot; a hotspot is still Wi-Fi, but no venue router or internet is required for local form analysis. Bluetooth can provision/pair and carry small controls; it is not the video transport. Initial setup is a QR device identity/pairing nonce plus hotspot credentials provisioned locally. App must request iOS local-network permission. Bonjour discovery is convenient, but retain a QR/manual local-address fallback because hotspot discovery behaviour must be verified on the actual phone.

Board camera → local pose inference → timestamped landmarks/cues and a low-resolution JPEG/MJPEG or supported encoded preview → phone overlay. Phone is the session/audio owner and rejects stale frames after source/set changes. Preview and landmarks share capture IDs/timestamps. Disconnect clears tracking and pauses counting. Measure ARM/Linux runtime support and speed before claiming board inference; forwarding frames to the phone is a distinct fallback, not proof the board ran the model. ElevenLabs later speaks selected cues; cached phrases allow feedback when external internet is absent.

Reference: [UNO Q radio and Linux capabilities](https://docs.arduino.cc/tutorials/uno-q/user-manual/). No board firmware/network changes are part of the current native-app milestone.

## Remaining tracks and demonstration

| Service/track | Concrete role | Evidence before claiming it |
|---|---|---|
| Gemini | Grounded reports + editable catalogue-only workout proposals | One session summary, one weekly summary and one approved valid proposal; rejection/timeout fixtures |
| Tiger | Actual sensor/rep ingestion, live history and skill/workload queries | Persisted rows, measured query timings, live-tail chart and compression measurement |
| Snowflake API | Batch public-data/forecast evaluation and cross-session feature analysis; return validated benchmark tables | Actual SQL API job/results and held-out evaluation lineage; complements Tiger live operations |
| HRT | Predict short-horizon HR/recovery trends and evaluate personal adaptation | Participant/session-held-out baselines, error/coverage, abstention; no fake scale or capacity claims |
| Vultr | Thin API, provider-key boundary, batch analytics and optional CV worker | Live health/request, version, measured latency and cost |
| ElevenLabs | One energetic standard voice, cached short cues and priority/interruption policy | Actual audible synthesis and stop/interruption check; no LLM per frame |
| Presage | Explicit brief still-camera recovery check, separate from Watch | One final bounded physical measurement with quality/source; preserve ~50-minute budget |
| Delta | Real development/prompt evaluation collaboration | Actual threads and judge cases in Delta after installation; do not claim Codex work as Delta usage |
| DEV | Evidence-based build story after functioning demo | Draft from verified features; publication later |
| Arduino | Side preview, edge inference if feasible, rep/set matrix output | Actual board-to-phone preview/landmarks and disconnect behaviour |

Slide deck later: problem → physical demo → skill progression → reports → architecture/integration roles → dataset/evaluation evidence → latency/cost/offline behaviour → limitations/next step. Each integration gets a verified/planned status. Do not turn a plan into a claim that a service is already live.

## Delivery sequence

1. Finish and review the existing local MediaPipe/Watch milestone; live BPM placement is included now.
2. Add catalogue, manual/timed logging, deterministic skill progress and local session/weekly reports; tests for evidence, deduplication, time windows and missing signals.
3. Add schema-validated Gemini proposal/report adapters with fixture tests; connect live API only during the deliberately bounded integration stage.
4. Tiger ingestion/rollups and Vultr gateway; then Snowflake/HRT evaluation, minimal voice and final Presage check.
5. UNO Q camera/connection demo, landing polish, real Delta evaluation and factual deck/DEV story.

Current authority: user requested these additions and approved both manual and tracked progression. Cloud spend and physical performance remain separately verified stages. Design choices not fixed by Omar are identified above and can be adjusted without rewriting the pose engine.

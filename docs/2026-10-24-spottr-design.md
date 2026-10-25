# Spottr: design proposal

24 October 2026 · Not yet approved for production implementation.

## Intent

A personal training companion for push-ups and bodyweight squats. Phone vision observes movement; Apple Watch adds heart rate and wrist motion; the person supplies goals, effort and discomfort. The coach gives one brief, useful cue at the right time. Tie to the opening deck's **Time** theme through rep tempo, cue timing, rest and progress over time.

Omar wants an energetic, direct coach, a fast uncluttered experience, minimal code, minimal paid API use and a demonstrable role for every selected integration. Preserve priority: **phone + Watch → landing page → optional Arduino hardware**. All MLH tracks except Solana are in scope as aspirations; additionally HRT and Zed's Built with Delta challenge. Do DEV writing after the demo works.

## Current evidence and authority

- Workspace started empty. The 90-page `/Users/scsoc/Downloads/Opening Ceremony Slides.pdf` was text-extracted and visually reviewed in three contact sheets. Relevant slides: HRT 21; Zed/Delta 27–30; MLH 47–54; schedule 81; theme 84.
- Xcode device inventory: paired physical **Omar's Phone**, iPhone 14 Pro Max, available. No physical Watch in that inventory. Omar confirms his Ultra 3 is paired to that phone and with him. Live sensor access remains unverified.
- Reuse existing **Musalli-Test**, iPhone 17 Pro simulator, and **TinyTaps-Watch**, Watch Series 11 46mm simulator. Do not create simulators, erase their content, replace existing apps, or imply the simulated model is an Ultra 3. A working simulator connection is not a physical sensor test.
- USB registry identifies **Arduino UNO Q**, vendor Arduino, USB ID 0x2341:0x0078; serial device `/dev/cu.usbmodem34850118662`. Board filesystem, firmware, network, RAM and peripherals not inspected. Do not flash or replace an existing application during this design phase.
- No paid API calls or health reads were performed. No API keys are needed for design review; later configuration stays outside source control and screenshots.
- User explicitly asks to review app and landing designs before frontend build. Current preview code is a disposable visual design aid, not an app scaffold.

## Current visual direction

Omar selected a clean white theme with black text. Use restrained neutral surfaces, real icons for ordinary controls/metadata, and simple AI-generated flat graphics. No authored SVGs, synthetic human photos, realistic musculature or 3D mannequins. The current exercise sheet contains six side-view phases: squat standing / middle / bottom and push-up extended / middle / bottom. Keep posture and joints clear; future real-person photography may use Omar's own supplied photos.

Use Lucide for the browser design and SF Symbols for native implementation where suitable. Use the generated flat strength graphic for category artwork. Clock, sets, heart, Watch and navigation icons communicate meaning. Body pose overlays in a real native app must come from observed landmarks, with unknown state when tracking fails.

White #ffffff, text #141414, secondary text #737373, surface #f5f5f4, functional green #26745a, amber #946a18 and red #ac3535. System typography. Remove “design preview”, “sample data”, “no live connection” and “designed for” from product screens. Keep provenance and limitations in review notes and honest completion reports, rather than repeating them through the interface. The browser designs remain illustrative; removal of labels does not establish a live implementation.

Energetic copy: “Control the descent.” “Strong rhythm. Stay controlled.” “Reset your stance.” One clear cue at a time. Name and white theme are decided and need no repeated confirmation.

## Screens and behaviour

1. **Today:** goal, two-exercise plan and one Start action. No login wall for local demo. Ask permissions when needed and explain them. First session collects goal/experience, chosen reps, perceived effort and any reason to avoid training. Never fill missing health history with invented data.
2. **Camera setup:** exercise-specific side view, adequate light, full body visible and one person. Calibrate neutral stance and comfortable range, show a countdown, then start. Setup can be a short overlay rather than another permanent screen. Add this state during implementation after design selection.
3. **Live set:** camera and coloured skeleton, rep count, one cue, heart rate with source/freshness, rep duration and set time. Pause/end always available. Phone performs pose and cue selection locally; cloud outages cannot freeze it.
4. **Watch:** count, current cue, heart rate, pause/end and optional haptic. Host workout session on Watch; mirror to phone. Reuse existing simulators for UI and transport tests. Replay fixtures are labelled. Preserve all existing TinyTaps and other simulator apps/data.
5. **Recovery:** suggested rest, recent heart-rate trajectory, self-reported effort and explicit ready/finish choices. Optional Presage still-camera check, initiated by the person, only late in integration testing. No auto-resume based on heart rate. “Too much” routes to finishing, not another set. Countdown is not proof of readiness.
6. **Review:** reps, sets, tempo changes and recorded heart-rate trajectory. Show evidence-backed observations and one next-session focus. Forecasts and generated explanations are labelled. Avoid invented percent form scores.
7. **Coach:** text conversation grounded in session events and known history. Later add explicit voice input and ElevenLabs output. During a set, pause conversational exchanges when a more important form cue is due.

Current designs show Today / Train / Recover / Progress / Coach, a Watch companion and an Arduino display. Phase controls expose all six exercise graphics. Review values and takeaways are illustrative, not analytical findings. Their provenance is documented here and in the design verification notes.

## Proposed implementation shape — builder decisions, not user-approved stack

Use **native SwiftUI iOS + watchOS**, HealthKit, Core Motion and workout mirroring for the first app. The Watch requirement makes native simpler than adding a React Native bridge. Omar prefers custom training when compute is available. Plan a bounded public-data experiment for exercise/form and fatigue-related features, with personal calibration after each eligible set. Omar has now selected available open-source models for the first app, followed by testing with his own push-ups; custom landmark-detector training remains in scope later. Start with MediaPipe Pose Landmarker Lite, then use observed errors and eligible public training labels to justify a bounded detector/quality experiment. Apple Vision can remain a separate native reference baseline. Do not submit a large training job before its target, data terms and split are fixed. Do not claim medically validated form assessment. See [personal learning](personal-learning.md).

One small backend on Vultr serves ingestion, chat/voice adapters and reports; one optional worker runs offline forecasts/clip inference. Choose the backend language when implementation starts, favouring one process over microservices. A Python service is reasonable if it also runs the chosen CV/forecast model; otherwise strict TypeScript can handle the thin API. Both are implementation choices. No Kubernetes, message broker, vector database or generic plugin framework.

Data path: Watch workout/motion → phone alignment + local CV + deterministic cue policy → async batched Vultr ingest → Tiger Data time series. At set/session end, export a compact feature/forecast/evaluation table to Snowflake; query it for progress and generate one grounded retrospective insight using Cortex. Gemini handles live conversational explanation from structured facts. ElevenLabs only speaks selected text.

The phone remains usable without network; buffer bounded events locally and retry idempotently. Store timestamp, monotonic/device time, source, units, quality/missingness, sample age, session/set/rep ID and model/policy version. Align Watch and phone clocks, preserve actual sampling times and do not forward-fill missing sensor values as observed measurements. No raw video upload by default. Explicit opt-in clip mode supports real Vultr CV testing without routing every frame to the cloud.

## Integration map and demonstration evidence

| Track/service | Specific job | Evidence needed before claiming it works |
|---|---|---|
| Apple Watch | Workout HR, wrist acceleration and device-motion features; context from authorised HealthKit history | Physical HR updates, known wrist movement, phone/Watch timestamps, pause/resume and stale-data behaviour |
| Gemini | Goal-aware text chat and concise explanation of selected observations | One successful real response grounded in a saved session fixture, then a live session; timeout fallback |
| ElevenLabs | Short selected coaching cues, then conversation; licensed standard voice | Cached generated cues plus one real synthesis request and audible phone playback; interruption scenario |
| Tiger Data | High-rate session events, per-rep features and time-bucketed trends | Real inserts, persisted row counts and an actual trend query; continuous aggregates' live tail must be explicitly enabled or queried separately |
| Snowflake API | Cross-session/public-data feature analysis and forecast evaluation; retrospective “what changed?” insight through Cortex REST | Actual SQL API results plus Cortex output traceable to those rows. This complements Gemini's in-session role |
| Presage | Brief still-camera pulse/breathing estimate between sets; compare with Watch as two distinct sources | One physical iPhone measurement with valid signal quality, timestamps and a visible source label. No assumed equivalence or manufactured confidence |
| Vultr | Real API hosting, forecast worker and opt-in clip/landmark processing | Live health/API request, model version and measured inference timing for the actual enabled path. No need for a GPU if CPU meets measured demand |
| HRT | Leakage-controlled evaluation of short-horizon HR forecasts and honest data-driven pacing choices | Participant/session-held-out metrics, baseline comparison, uncertainty and abstention; real dataset size, not fabricated events |
| Zed: Built with Delta | Actual development collaboration and a responsive product | Work and review in Delta threads, with shareable evidence. A screenshot of Delta or developing entirely in Codex does not meet this claim |
| DEV | Technical story after working demo | Later explicit publication request and a fact-checked post separating tested/live/replayed paths |
| Arduino UNO Q | Planned reps left, sets remaining and short messages rotate on the 8×13 blue matrix; spare RGB LED encodes cue state, unknown stays neutral | A real phone/backend event changes board output. Disconnected board visibly times out. Do not repurpose system-status LEDs blindly |

Sponsor/event sources: [MLH tracks](https://www.mlh.com/events/oxhack-26), opening deck slides listed above. API sources: [Snowflake SQL API](https://docs.snowflake.com/en/developer-guide/sql-api), [Cortex REST](https://docs.snowflake.com/en/developer-guide/snowflake-rest-api/reference/cortex-inference), [Tiger continuous aggregates](https://www.tigerdata.com/docs/learn/continuous-aggregates), [Presage Swift setup](https://smartspectra.presagetech.com/rc/docs/swift/option-1-api-key/).

## Watch signal scope

Collect useful available streams, not every hardware output indiscriminately. Permission, OS, region, background execution and sample availability determine access.

| Category | Proposed signals | Access limitation |
|---|---|---|
| During workout | Heart rate, workout elapsed time, energy estimates; accelerometer and processed motion/rotation/attitude where exposed | HealthKit workout builder plus Core Motion on Watch; inspect availability and actual cadence. Energy is an estimate, not raw physiology |
| Historical context | Resting HR, HRV **SDNN**, sleep duration/stages, workouts, activity, respiratory rate, VO2max, weight if authorised | Often sparse or delayed; retain collection time, source and missingness. These are not continuously live workout streams |
| Optional history | Oxygen saturation, wrist temperature, user-recorded ECG | Availability-dependent; no continuous ECG, on-demand raw PPG or live core-body-temperature claim. Watch SDNN differs from Presage RMSSD |
| Irrelevant to indoor set | GPS, altitude, compass, depth and water temperature | Hardware existence does not imply usable API access or relevance; omit from demo unless the activity requires it |

Regular HealthKit/Core Motion access does **not** grant unrestricted raw sensor access. Apple's SensorKit raw optical/electrical heart data path requires an approved research entitlement; do not design the demo around receiving it. No glucose, lactate, blood pressure or “muscle failure” sensor inference. No measurement of sensors was verified this turn.

Sources: [Ultra 3 hardware](https://support.apple.com/en-mide/125095), [HealthKit](https://developer.apple.com/documentation/healthkit), [Core Motion](https://developer.apple.com/documentation/coremotion/cmmotionmanager), [Apple sensor/API explanation, pp. 25–26](https://images.apple.com/my/health/pdf/Heart_Rate_Calorimetry_Activity_on_Apple_Watch_November_2024.pdf), [multidevice workouts](https://developer.apple.com/documentation/healthkit/building-a-multidevice-workout-app).

## Local coaching and speaking policy

Pose model → confidence/view gate → smoothed kinematic features → exercise state machine → cue priority → text immediately → optional voice/haptic. Track top/bottom transitions with hysteresis, valid movement duration and return-to-start; occlusion cannot count as a rep. Smooth without excessive lag. Calibrate by person/view; generic degree thresholds are provisional, not universal good-form definitions. A side view cannot reliably assess frontal knee alignment or hidden joints. Low confidence means “Move into view,” not red “bad form.”

Policies in priority order: user stop/discomfort → pause/reset cue from reliable observations → form cue → pace cue → encouragement → conversation. User stop cancels all output and advances the session generation ID. Symptoms are taken from user report, not diagnosed from sensor thresholds. Never urge someone to push through pain or chase physiological failure. The person chooses reps and can decline a suggestion. Self-reported effort is not replaced by a heart-rate score.

Prevent overlap through one audio owner. Ordinary coaching finishes its short phrase; queue at most one still-relevant cue and drop expired repetitions. Urgent stop/pause supersedes ordinary speech; user stop always interrupts. Cancel in-flight chat/TTS and ignore late responses from previous sessions. Assistant audio is not fed back as user speech. Preserve system audio-route interruptions and mute. No promise that speech can never be interrupted by the OS.

Builder starting values: require a sustained observation across several frames; aim for 4–6 seconds between ordinary form cues, no chatter per rep, urgent cue immediate after validity checks. Tune on the real device and record latency rather than inventing measured performance. Pre-generate/cache a small phrase set with a single voice and model; never use a paid LLM per frame. Templates select routine cues; Gemini explains them when asked.

## Prediction and personal learning

For a public-data benchmark, one measurable predictive target is: **heart rate 30 seconds ahead during clearly marked rest intervals**, optionally 60 seconds if supported by the recording length. Compare persistence and exponential-decay/EWMA baselines against a small pretrained Chronos model. This is an experiment, not an established ability or a medically safe-to-continue detector. Show prediction intervals only after their empirical coverage is checked. During cold start, irregular measurements, motion noise or shift, abstain and show observed trends.

Personal adaptation is now an explicit product direction: learn a small per-exercise calibration layer after eligible sets using rep-reserve feedback, stop reason and motion history; preserve censoring and uncertainty. This complements the public-data HR benchmark. The proposal is detailed in [personal learning](personal-learning.md). Only estimate future rep-tempo deterioration if separately labelled data and held-out evaluation exist. No current dataset establishes an individual’s safe exertion ceiling or reps-to-failure. Offline “more useful rest suggestion” needs a predefined reference; no causal benefit or injury reduction claim from a replay. Details and exact datasets are in the research brief.

## Staged build and spending

1. Review the revised white Spottr designs and adjust the flow. Current phase ends with mockups and research, not a production scaffold.
2. Implement a thin phone/Watch UI slice using the existing simulators and marked replay fixtures. Read full `/Users/scsoc/.claude/TDD.md` before production work. Behaviour-first tests for rep transitions, stale samples, stop/pause, cue expiry and late async responses. Native Swift/XCTest follows the same test-first intent without forcing TypeScript into watchOS.
3. Exercise physical camera/pose and Watch workout HR/motion before adding cloud providers. Read `/Users/scsoc/.claude/AI.md` before ML development/validation. Test one exercise well, then the other. No large training job is required for this milestone.
4. Add real Tiger ingestion and Vultr hosting; one endpoint and one replay verification each. Add evaluation dataset subsets and forecasting only when target observability is established.
5. Connect Gemini with a bounded output, then ElevenLabs with a small cached phrase set. Use text fixtures and fake adapters for routine tests. Default live-provider testing off; no fallback secretly spends another provider's credits.
6. Connect Snowflake SQL/Cortex to one session/report; execute one report and verify grounded results. Presage comes late: one deliberately started, time-bounded physical measurement, no auto-start, no background polling. Omar reports ~50 minutes of remaining Presage credits; that balance is not independently verified. Manual demo enable/stop, track actual usage, stop on quota errors; do not retry indefinitely.
7. Polish the landing page. Then Arduino RGB/matrix output. Optional local camera inference on UNO Q only after the core demo works and a USB camera/power path is available. Jetson removed from current plan.
8. Demo rehearsal: physical set, rest, one question, a voice cue, history insight, network failure and user stop. Show actual live versus replay status. Preserve screenshots, timings, record IDs and provider request IDs without secrets. Write DEV story last.

Omar explicitly deferred Delta until it is installed. Prompt/fixture preparation can proceed; actual Delta work and judge runs remain pending. See [Delta prompt evaluation](delta-prompt-evaluation.md). No dataset bulk downloads, provider provisioning, credential copying, firmware changes or Delta account setup occurred in the design phase. Delta needs genuine usage, account sign-in and model configuration before claiming that track. Setup reference: [Delta quickstart](https://delta.dev/docs/getting-started/quick-start) and [OpenRouter provider setup](https://delta.dev/docs/agents/models-and-providers#add-an-api-key).

## Hardware recommendation

Current board is a UNO Q, not a basic UNO. Official [hardware](https://www.arduino.cc/product-uno-q) and [user manual](https://docs.arduino.cc/tutorials/uno-q/user-manual/) document its Linux/MCU split, matrix and RGB LEDs. Start with its own display/LED, receiving low-rate cue/rep events. Do not attach it to the user or represent it as another biometrics sensor. Network transport or a Mac USB bridge is a builder choice after discovery; iPhone USB serial support is not assumed.

The [MLH catalogue](https://www.mlh.com/resources/hardware) lists a **Logitech USB webcam** and **JBL Go 3 speaker**. For optional UNO Q inference, request the webcam plus an appropriately powered USB-C hub and compatible 5 V/3 A supply; check event stock, not just the generic catalogue. Existing phone/speaker is enough for the primary demo. The catalogue is not a reservation. UNO Q Linux camera inference and native iPhone inference are different implementations; neither is verified on this board yet.

## Acceptance and open decisions

Spottr name and white/black direction are confirmed. Review the revised layout and six pose graphics. User has selected energetic/direct tone, confirmed Watch pairing, supplied UNO Q and required simulator reuse. Do not ask those again.

Implementation can choose exact versions, backend language, pose runtime and modest latency targets after measuring the physical path. Provider accounts, region, model access and budgets require current read-only verification when connecting them. Public dataset/model restrictions must be honoured; use approved open subsets, not a bulk restricted corpus upload. No dependency on other teammates or undisclosed assets is assumed.

Completion claims are per layer: design reviewed; tests pass; simulator path exercised; physical device path exercised; provider path exercised; deployment verified; demo rehearsed. They are not interchangeable.

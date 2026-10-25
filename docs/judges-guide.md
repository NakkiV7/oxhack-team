# Spottr judges' guide

Local 10-slide presentation, based on the evidence snapshot at 00:09 UTC on 25 October 2026. The deck uses actual simulator captures, existing exercise artwork, and recorded public-data results. It includes merged Tiger/landing evidence and the Gemini compatibility correction. Exact source/receipt hashes pin the evidence; not every provider is live. Recheck status labels before presenting because integration work continues.

[Editable PowerPoint](../presentation/output/spottr-judges.pptx), [static PDF](../presentation/output/spottr-judges-rendered.pdf), and [overview](../presentation/output/preview-montage.png).

## Presentation sequence

| Slide | Main point | Presenter detail |
|---|---|---|
|1|Spottr and the user problem|Short workout feedback needs fresh evidence. The Today image is an actual iPhone simulator capture.|
|2|The implemented workout flow|Start approved work, track/log a set, retain pause/stop controls, then review actual records.|
|3|Phone, Watch and Pi roles|The phone owns pose inference/session decisions. Watch capture is not physically accepted. Pi delivered real initial frames but USB disconnects block sustained capture.|
|4|Actual timing decisions|Complete-cycle counting, movement reset on gaps, prior-rep pacing baseline and camera-independent discomfort priority. PR #64 passed 23 native/26 core checks with fake playback. These rules do not establish clinical or rep-count accuracy.|
|5|Skills and engagement|All prerequisites must complete. Three qualifying sets across two days, source labels, tree/linear choice and practice access. Game points are not physical capacity.|
|6|Gemini's four request types|Chat, proposal, session summary and weekly summary. Facts, canonical camera/manual capabilities and generation IDs bound responses. All four native request types have actual provider responses: two chats plus proposal/session/week checks after the provider-only fix. The three structured actions used an isolated synthetic namespace; they do not establish real-user guidance quality.|
|7|Tiger and Snowflake roles|Tiger Explorer accepted the empty gateway schema; the separate strict Node TLS connection and ingestion remain blocked. Snowflake public-data batch import/reconciliation is tested offline; live warehouse acceptance remains pending.|
|8|Actual PAMAP2 evidence|Participant-held-out forecasting with last-value comparison. The short test participant and negative adaptation result remain visible.|
|9|Provider gates|Distinguish real Gemini responses, offline checks and unavailable provider acceptance. The standalone web prototype passed 92 offline checks and a mock-profile browser flow, with real upload still pending. The revised white-screen landing passed local browser checks; it is not publicly deployed.|
|10|A two-minute demo|Suggested rehearsal with fixture/live labels. Builds 1 and 2 are internally available; only build 1 is externally submitted, with beta review pending. This sequence is not a completed rehearsal.|

## Two-minute demo

- 00:00 Today and goals. Preserve real history and show the actual starting state.
- 00:15 A tracked workout. Show the camera path, cue and pause/stop controls. Name fixture/simulator input if used.
- 00:55 Pause, end and review. Show recorded sets, timing and source badges.
- 01:20 Skills and Coach. Show prerequisites and an explicit request action. Do not call a prepared response a new provider request.
- 01:45 Saved HR evidence and remaining gates. Use the offline plot/result with its coverage limitations.

The local app remains useful while optional providers are pending. Avoid an unrehearsed paid-provider call during judging. Physical Watch physiology, sustained Pi capture, audible phone playback and rep-count accuracy remain separate acceptance work.

## HR result wording

“On a locked PAMAP2 participant split, validation selected a small HR-only ridge model. At 10 seconds its participant-macro error was 2.808 bpm versus 3.081 for last-value persistence. One test person supplied 803 forecasts and the other only four. At 30 seconds, one person supplied 799 forecasts and the short recording supplied none. The fixed adaptive bias worsened error, so we retained that negative result.”

The target is a future five-second mean of actual recorded HR, with a 60-second causal input history. This experiment does not establish recovery, readiness, reps in reserve, failure prediction or Apple Watch transfer. The test outcomes have been examined and cannot be reused to select a revised model. [Full evidence](../research/hr_forecast/results/README.md).

## Current provider and release boundaries

Gemini has actual synthetic gateway responses for all four types and two signed-simulator native chat checks. The second correctly distinguished base push-up/squat camera support from manual reps and active hold timers. Three further explicit native production actions accepted a workout proposal, weekly summary and session summary after a provider-only schema projection removed outbound maxItems constraints. The original full output validator remains unchanged. The proposal offered three exercises; Squats alone was selected, with no approval or saved plan. One isolated synthetic manual Squats set of two reps, with no profile or Watch data, supplied the reports. Both reports accurately displayed the supplied counts and a neutral continue-recording focus. This accepts the exercised synthetic native/provider/display path; physical networking and real-user coaching quality remain pending. Tiger's authenticated Explorer accepted the exact gateway migration and catalogue checks: two empty tables, 15 columns, seven validated PK/CHECK constraints, a one-day scalar hypertable and four usable indexes. No workout or sensor rows were inserted. The separate Node connection still rejects the private-CA chain under strict TLS. Gateway ingestion/replay/readback, rollups, native sync and the standalone prototype database path remain unverified. Snowflake’s pinned public-PAMAP2 import/reconciliation is tested offline with dry-run as default; an existing warehouse and bounded live SQL acceptance remain pending. Vultr’s local ARM64 image/runtime and Caddy checks passed; credit/spending/hostname scope is needed before hosted deployment. ElevenLabs needs a working secret and separate audible acceptance. Presage needs an explicit decision on derived-vitals LLM egress and verified credits. Delta has a prepared packet and zero judge requests, with an operator installation/legal step outstanding.

Build **0.1 (1)** passed Apple validation/upload and processing (`VALID`) and is assigned to the owner’s internal TestFlight group (`IN_BETA_TESTING`). External build 1 is `WAITING_FOR_BETA_REVIEW`; the 25-person invitation is not yet a usable external download. No public App Store release or physical installation is established.

Build **0.1 (2)** from `b7bf563` passed signed archive/export and Apple validation; upload succeeded at **23:08:00 UTC on 24 October**. At **23:10:33 UTC**, App Store Connect reported `VALID` and `IN_BETA_TESTING` after assignment to the existing internal group. Build 2 is not externally submitted (`READY_FOR_BETA_SUBMISSION`); only build 1 remains in the OxHack external group. Actual phone/Watch installation is unverified. It includes the later manual-set wording and configured manual/hold discomfort-cue fix; those changes are absent from build 1. The manual recovery stop message and next-set block already exist in build 1. The upstream MediaPipe privacy/origin-signature concern remains separate from Apple processing. Local Apple speech has fake-playback tests; audible acceptance remains pending.

The native and standalone browser paths remain separate. The browser prototype’s 92 offline checks and mock-profile rehearsal do not validate physical counting, independently labelled form, or its corrected live Tiger transaction path. A separate Codex judge reviewed authored synthetic cue controls; it is not a Delta run or evidence of live Gemini coaching quality.

The landing now displays actual white iPhone Today and Watch simulator captures, with no fabricated heart-rate reading or dark concept phones. Local CUA/Chrome checks accepted desktop/tablet and 390/320px previews, keyboard navigation, reduced motion, both image loads and clean console logs. This is not physical Safari/touchscreen or public deployment acceptance. The external TestFlight invitation remains pending.

## Evidence pointers and refresh

- [Current ledger](integration-readiness.md), [work references](ISSUES.md), [app guide](app-guide.md).
- [Watch capture limits](watch-telemetry.md), [Pi physical evidence](../hardware/pi/EVIDENCE-2026-10-24.md), [local speech](voice-feedback.md).
- [Goal-aware Coach](coach-goals.md), [actual native Gemini chats](evidence/native-gemini-chat-2026-10-24.md), [native structured-response compatibility and acceptance](evidence/gemini-structured-compatibility-2026-10-25.md), [configured cue correction](coaching-policy.md).
- [Prototype integrity](evidence/pushup-prototype-integrity-2026-10-24.md), [Tiger console schema receipt](evidence/tiger-console-2026-10-24.md), [Node TLS diagnosis](tiger-live-readiness.md), [release packaging](release-readiness.md), [build 2 receipt](evidence/testflight-build-2-2026-10-24.md).
- [Landing browser receipt](evidence/landing-browser-2026-10-24.md), [landing source and local setup](../landing/README.md).
- [PAMAP2 protocol and results](public-data-benchmark.md), [Delta packet](../evaluations/delta/2026-10-24/README.md), [separate synthetic Codex review](../evaluations/codex/2026-10-24-cue-review/README.md).

The editable builder and asset/source manifest live under `presentation/source/`. Change status copy in the source, export a new revision, then render and inspect every affected slide. Keep results and screenshots labeled by their actual origin. Publication, provider spending, physical acceptance and external beta approval remain separate tasks.

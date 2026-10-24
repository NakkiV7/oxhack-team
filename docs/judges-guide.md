# Spottr judges' guide

Local 10-slide presentation, based on the evidence snapshot at 20:55 UTC on 24 October 2026. The deck uses actual simulator captures, existing exercise artwork, and recorded public-data results. It does not claim every provider is live. Recheck status labels before presenting because integration work continues.

[Editable PowerPoint](../presentation/output/spottr-judges.pptx), [static PDF](../presentation/output/spottr-judges-rendered.pdf), and [overview](../presentation/output/preview-montage.png).

## Presentation sequence

| Slide | Main point | Presenter detail |
|---|---|---|
|1|Spottr and the user problem|Short workout feedback needs fresh evidence. The Today image is an actual iPhone simulator capture.|
|2|The implemented workout flow|Start approved work, track/log a set, retain pause/stop controls, then review actual records.|
|3|Phone, Watch and Pi roles|The phone owns pose inference/session decisions. Watch capture is not physically accepted. Pi delivered real initial frames but USB disconnects block sustained capture.|
|4|Actual timing decisions|Complete-cycle counting, movement reset on gaps, prior-rep pacing baseline and stop priority. These rules do not establish clinical or rep-count accuracy.|
|5|Skills and engagement|All prerequisites must complete. Three qualifying sets across two days, source labels, tree/linear choice and practice access. Game points are not physical capacity.|
|6|Gemini's four request types|Chat, proposal, session summary and weekly summary. Facts, catalogue constraints and generation IDs bound responses. Requests are explicit.|
|7|Tiger and Snowflake roles|Operational timestamps versus batch evaluation. Both roles remain prospective until real database acceptance.|
|8|Actual PAMAP2 evidence|Participant-held-out forecasting with last-value comparison. The short test participant and negative adaptation result remain visible.|
|9|Provider gates|Distinguish real synthetic Gemini responses, offline tests, proposed integrations and unavailable provider acceptance.|
|10|A two-minute demo|Suggested rehearsal, with fixture/live labels and release gates. A suggested sequence is not evidence that a rehearsal happened.|

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

Gemini has actual synthetic gateway responses for all four types. Native provider acceptance and factual review remain pending. Tiger's current service presents a private-CA chain that strict TLS rejects. Snowflake needs a bounded live SQL statement. Vultr needs credit/spending/hostname scope before deployment. ElevenLabs needs a working secret and separate audible acceptance. Presage needs an explicit decision on derived-vitals LLM egress and verified credits. Delta has a prepared packet and zero judge requests, with an operator installation/legal step outstanding.

App Store Connect and explicit host/Watch profiles exist. No accepted TestFlight build is claimed. Archive/export, vendor SDK privacy/signature validation, upload and processing remain separate. The local Apple speech implementation has fake-playback tests, with audible acceptance still pending.

## Evidence pointers and refresh

- [Current ledger](integration-readiness.md), [work references](ISSUES.md), [app guide](app-guide.md).
- [Watch capture limits](watch-telemetry.md), [Pi physical evidence](../hardware/pi/EVIDENCE-2026-10-24.md), [local speech](voice-feedback.md).
- [Goal-aware Coach](coach-goals.md), [Tiger diagnosis](tiger-live-readiness.md), [release packaging](release-readiness.md).
- [PAMAP2 protocol and results](public-data-benchmark.md), [Delta packet](../evaluations/delta/2026-10-24/README.md).

The editable builder and asset/source manifest live under `presentation/source/`. Change status copy in the source, export a new revision, then render and inspect every affected slide. Keep results and screenshots labeled by their actual origin. Publication, provider spending and TestFlight submission remain separate tasks.

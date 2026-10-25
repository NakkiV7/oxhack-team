# Spottr judges' guide

Local 10-slide presentation, based on the evidence snapshot at **01:43 UTC on 25 October 2026**. The [00:36 checkpoint](../presentation/output/spottr-judges.pptx) remains unchanged as historical evidence. The deck uses actual simulator captures, existing exercise artwork, and recorded public-data results. It includes merged Tiger/landing evidence and the Gemini compatibility correction. Exact source/receipt hashes pin the evidence; not every provider is live. Recheck status labels before presenting because integration work continues.

**Release checkpoint — 25 October 05:05:16.755 UTC:** build **0.1 (5)** from `f3eae89ced8547e283bd93abe6c560c9e1ce8e2c` passed archive/export/independent audit, Apple validation/upload and internal/external beta approval. Internal builds are **5/4/3/2/1**, external **5/4/3/1**. [Build 5 receipt](evidence/testflight-build-5-2026-10-25.md). PR #114 closed simulator navigation #110; physical Watch #7 remains. PR #115 accepted one synthetic chat loading toolbar with zero external providers; cancellation/offscreen checks were not exercised. Energy #102 merged later in PR #117 and is not included. At that checkpoint, no new public-page or installation check had occurred. Later provider/landing updates below supersede status only; dated deck artifacts remain unchanged.

[Editable PowerPoint](../presentation/checkpoints/20261025T0143Z/output/spottr-judges.pptx), [static PDF](../presentation/checkpoints/20261025T0143Z/output/spottr-judges-rendered.pdf), and [overview](../presentation/checkpoints/20261025T0143Z/output/preview-montage.png).

## Presentation sequence

| Slide | Main point | Presenter detail |
|---|---|---|
|1|Spottr and the user problem|Short workout feedback needs fresh evidence. The Today image is an actual iPhone simulator capture.|
|2|The implemented workout flow|Start approved work, track/log a set, retain pause/stop controls, then review actual records.|
|3|Phone, Watch and Pi roles|The phone owns pose inference/session decisions. Watch capture is not physically accepted. Pi delivered real initial frames but USB disconnects block sustained capture.|
|4|Actual timing decisions|Complete-cycle counting, movement reset on gaps, prior-rep pacing baseline and camera-independent discomfort priority. PR #64 passed 23 native/26 core checks with fake playback. These rules do not establish clinical or rep-count accuracy.|
|5|Skills and engagement|All prerequisites must complete. Three qualifying sets across two days, source labels, tree/linear choice and practice access. Game points are not physical capacity.|
|6|Gemini's four request types|Chat, proposal, session summary and weekly summary. Facts, canonical camera/manual capabilities and generation IDs bound responses. All four native request types have actual provider responses: two chats plus proposal/session/week checks after the provider-only fix. A later explicit real proposal was selected, approved and executed as three synthetic manual Squats sets of 3/2/1 reps. It used a signed Debug simulator and loopback gateway, with no physical or coaching-quality acceptance.|
|7|Tiger and Snowflake roles|Tiger Explorer accepted the empty gateway schema; the separate strict Node TLS connection and ingestion remain blocked. Snowflake public-data batch import/reconciliation is tested offline; live warehouse acceptance remains pending.|
|8|Actual PAMAP2 evidence|Participant-held-out forecasting with last-value comparison. The short test participant and negative adaptation result remain visible.|
|9|Provider gates|Distinguish real Gemini responses, offline checks and unavailable provider acceptance. The standalone web prototype passed 92 offline checks and a mock-profile browser flow, with real upload still pending. The separate Python contributor demo passed 13 offline behavior checks; it has no native/Tiger adapter or measured accuracy. At the 01:43 slide checkpoint, the revised white landing had local browser acceptance only; later public deployment is recorded below.|
|10|A two-minute demo|Suggested rehearsal with fixture/live labels. The slide retains its build-4 checkpoint; the operator update above records current build-5 availability. This sequence is not a completed rehearsal.|

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

The [six-provider prize map](../README.md#provider-integrations-and-oxhack-prizes) links the official OxHack categories, implementation files and demonstration boundaries. Use it alongside the dated slides; the deck is not a current provider-status dashboard.

**Gemini and Vultr have real acceptance.** Synthetic native chat/proposal/session/week responses and an explicitly approved Squats-only manual workout passed their exercised paths. On **25 October 07:13 UTC**, the restricted hosted HTTPS gateway returned a matching, factual synthetic chat response in **935 ms**. Two deliberate hosted attempts occurred; only the second has a retained accepted result. The earlier **06:57** hosting check made zero AI calls. Merged [PR #131](https://github.com/NakkiV7/oxhack-team/pull/131) subsequently published the white landing and accepted real HTTPS/assets, four browser widths, keyboard/reduced motion and Apple invitation navigation. API routes remain operator-restricted. Neither result establishes physical-phone networking, installation or coaching quality.

**Tiger and Snowflake are not live data demonstrations.** Tiger’s empty schema has provider-console acceptance, but the original Node service still failed strict TLS at **07:23:45 UTC**. Open PR #132 adds tested owner/workout rollups; it does not establish ingestion or deployment. Snowflake’s pinned public-data import/reconciliation is offline-tested; token, database/schema and existing-role/table privileges remain gates. Its role here is SQL analytics, not a demonstrated Snowflake LLM/Cortex feature.

**ElevenLabs and Presage remain bounded source integrations.** Native/server voice adapters have fake-provider tests; actual API secret, voice entitlement, synthesis and audible acceptance remain missing. SmartSpectra 3.4.0 compiles/links and fake-driver tests pass, but no SDK start or camera-vitals measurement has occurred. Native authentication/credits, automatic numeric-vitals LLM-egress consent and duplicate-class compatibility auditing remain gates. Do not call local Apple speech ElevenLabs, or a camera estimate validated physiology. The newer voice/rollup source is not accepted by the frozen hosted-server receipt.

Delta, running, zones, cloud accounts and Watch complications are [deferred](POST-HACKATHON.md). Retain the separate public-PAMAP2 results and their limitations; no provider integration turns game XP into physical capacity. Exact current access actions are in the [ledger](integration-readiness.md#prize-fit-and-remaining-access-actions).

Build **0.1 (5)** is `VALID`, encryption `false`, internally/externally `IN_BETA_TESTING`, and review `APPROVED` (`submittedDate: null`) at the **25 October 05:05:16.755 UTC** read-back. Internal contains **5/4/3/2/1**; external **5/4/3/1**. Build 2 remains internal only. The existing 25-person [public invitation](https://testflight.apple.com/join/f3MhePbf) is unchanged. No new public-page/landing-link check, invitation acceptance, physical installation or public App Store release is established.

The dated deck source inventory is main `485a33c`, with native build 4 frozen at `7f4b5ba5f5478b0efa2c18605eb0252c6f9cb3ec`. Current build 5 is frozen separately at `f3eae89ced8547e283bd93abe6c560c9e1ce8e2c` and adds the later weekly/profile/check-in/report/Coach and compact Watch work. The Gemini gateway and standalone Python demo are separate from the binary. The upstream MediaPipe privacy/origin-signature concern remains open; experimental SDK source work has not replaced the app's downloaded SDK. Local Apple speech has fake-playback tests; physical networking, audible acceptance and actual phone/Watch installation remain unverified.

The native and standalone browser paths remain separate. The [Python squat/push-up demo](../squat/README.md), imported from @NakkiV7 at exact `42043df`, also remains separate: pretrained MediaPipe plus geometry/state rules, 13 offline behavior checks with fake dependencies, no real inference or physical/accuracy/audio acceptance, and no native/Tiger adapter. Its imported exercise thresholds were preserved. The browser prototype’s 92 offline checks and mock-profile rehearsal do not validate physical counting, independently labelled form, or its corrected live Tiger transaction path. A separate Codex judge reviewed authored synthetic cue controls; it is not a Delta run or evidence of live Gemini coaching quality.

The public landing retains actual white iPhone Today and Watch simulator captures, with no fabricated heart-rate reading or dark concept phones. Its later hosted #131 acceptance is distinct from the historical local browser receipt. Invitation acceptance, installation and physical Safari/touchscreen behavior remain unverified.

## Evidence pointers and refresh

- [Current ledger](integration-readiness.md), [work references](ISSUES.md), [app guide](app-guide.md).
- [Watch capture limits](watch-telemetry.md), [Pi physical evidence](../hardware/pi/EVIDENCE-2026-10-24.md), [local speech](voice-feedback.md).
- [Goal-aware Coach](coach-goals.md), [actual native Gemini chats](evidence/native-gemini-chat-2026-10-24.md), [native structured-response compatibility and acceptance](evidence/gemini-structured-compatibility-2026-10-25.md), [configured cue correction](coaching-policy.md).
- [Prototype integrity](evidence/pushup-prototype-integrity-2026-10-24.md), [Tiger console schema receipt](evidence/tiger-console-2026-10-24.md), [Node TLS diagnosis](tiger-live-readiness.md), [release packaging](release-readiness.md), [build 2 receipt](evidence/testflight-build-2-2026-10-24.md), [build 3 receipt](evidence/testflight-build-3-2026-10-25.md), [historical build 4 receipt](evidence/testflight-build-4-2026-10-25.md), [current build 5 receipt](evidence/testflight-build-5-2026-10-25.md), [approved-plan execution](evidence/native-gemini-plan-execution-2026-10-25.md).
- [Landing browser receipt](evidence/landing-browser-2026-10-24.md), [public invitation and landing-link receipt](evidence/testflight-availability-2026-10-25.md), [landing source and local setup](../landing/README.md).
- [PAMAP2 protocol and results](public-data-benchmark.md), [Delta v2 packet](../evaluations/delta/2026-10-25-v2/README.md), [separate synthetic Codex review](../evaluations/codex/2026-10-24-cue-review/README.md).

The current editable builder and source/provenance manifest live under `presentation/checkpoints/20261025T0143Z/source/`; existing shared assets remain under `presentation/assets/`. The untouched historical builder and manifest remain under `presentation/source/`. Change status copy in the source, export a new revision, then render and inspect every affected slide. Keep results and screenshots labeled by their actual origin. Publication, provider spending and physical acceptance remain separate tasks. TestFlight beta approval does not establish any of them.

Unreleased/requested scope: active-energy #102 merged later in PR #117 after passing software checks; it has no build-5 or physical acceptance. Optional local measurements/BMI source is under separate native/UI verification; broader Health onboarding under #102 and [account management #116](https://github.com/NakkiV7/oxhack-team/issues/116) remain pending. A local guest profile does not establish a cloud account or deletion of synced copies.

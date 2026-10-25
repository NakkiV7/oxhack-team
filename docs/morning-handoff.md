# Morning handoff

Snapshot: **25 October 2026, 00:58 UTC**, with release state verified at 00:36 UTC and later local Gemini acceptance through 00:56 UTC. Native milestones merged through [PR #69](https://github.com/NakkiV7/oxhack-team/pull/69), with the subsequent Gemini gateway acceptance below. The local iPhone/Watch MVP is ready for a practical device rehearsal. Build **0.1 (3)** is `VALID` and internally `IN_BETA_TESTING` alongside builds 1 and 2. It includes the rendering/history refactor; the Gemini correction runs separately on the gateway. Build 3 is also externally `IN_BETA_TESTING`, with its beta submission `APPROVED`. External OxHack contains builds 3 and 1; build 1 remains a fallback and build 2 stays internal only. The 25-person invitation and public Apple beta page are verified. [Build 3 evidence](evidence/testflight-build-3-2026-10-25.md) and [iPhone/Watch installation](testflight.md). Actual installation and device behavior remain unverified; Xcode discovery is not part of that installation route.

[PR #48](https://github.com/NakkiV7/oxhack-team/pull/48) is now merged: failed Watch collection releases the old capture so recording can be retried. Its source-double checks and Watch simulator build passed; real HealthKit acceptance is still separate. [Custom workouts #19](https://github.com/NakkiV7/oxhack-team/issues/19) and [artwork #18](https://github.com/NakkiV7/oxhack-team/issues/18) are closed; #19 was completed by PR #47.

## What works

- Today, local profile/goals, onboarding, history/data controls, connected and linear Skills, and deterministic session/week reports. Skill points describe game progress, not physical capacity.
- All 19 exercise lessons/icons, six push-up/squat phase illustrations, filming guides and private side-by-side video imports. Omar still needs to record the real lesson clips; automatic person cropping/background removal is not implemented.
- Approved Coach plans execute in catalogue order with explicit Start/Pause/End, real rest timing, manual reps and hold timers. Only base push-up/squat offer opt-in phone/Pi camera counting. Changing input confirms an unfinished-set reset; targets never invent reps or automatically end sets. Mixed sources/timings stay ordered in saved reports. [Usage and test evidence](custom-workouts.md).
- On-device pose inference, deterministic form/pacing cues, explicit local Apple voice feedback, and source-aware Watch controls. Voice starts off. Simulated/fake playback and callback tests passed; actual counting, real sensor capture and audible behavior still need the checks below.
- Goal-aware Gemini chat, proposals and session/week summaries share supplied training facts and goals only after an explicit action. The optional profile name stays local. All four request types have real synthetic responses in the signed simulator. Chat correctly distinguished camera/manual/timed capabilities. A later native proposal exposed an upstream schema rejection; the provider-only correction preserves full local validation. The corrected proposal displayed independently selectable exercises, and both report summaries matched one synthetic manual set. A later real proposal was explicitly approved for Squats alone, then three synthetic manual sets of 3/2/1 reps were saved in order with self-report provenance, 96.807 seconds of active time and observed rest. Its one-attempt loopback guard rejected the next chat before another provider request. [Approved-plan execution and cleanup](evidence/native-gemini-plan-execution-2026-10-25.md), [structured correction](evidence/gemini-structured-compatibility-2026-10-25.md), [chat evidence](evidence/native-gemini-chat-2026-10-24.md), and the earlier [zero-provider fixture check](evidence/native-synthetic-coach-2026-10-24.md). Temporary history/plan were removed, original preferences restored and the task gateway stopped. Physical networking, real exercise and real-user guidance quality remain pending.

The latest [performance refactor](evidence/history-persistence-2026-10-25.md) shares one Skills evaluation per render, defers offscreen report cards and removes the redundant read/decode after save. Six UI checks, one native data-control check and the focused core checks passed. Save/init/export still do synchronous whole-history work; no measured device speedup is claimed.

The final configured UI test passed Cancel-preserves-count, confirmed reset, voice-off default, manual fallback, hold exclusion and saving. The shared suite passed 59 XCTest + 90 Swift Testing tests; the final reviewed snapshot passed 35 native checks, plus the full configured workout UI flow and a Watch simulator build. These establish software behavior, not physical exercise accuracy.

## Start locally

Use Xcode with iOS/watchOS 26+ platform support, Swift 6 and Ruby's `xcodeproj` gem. From a fresh checkout, run setup once:

```sh
./scripts/bootstrap.sh
open Spottr.xcodeproj
```

An already prepared checkout can open the project directly. Bootstrap fetches only missing pinned MediaPipe artifacts and regenerates the project; coordinate before running it in a shared working tree. Local workouts/reports require no account or provider key.

Choose the `Spottr` scheme and reuse an existing iPhone simulator. List installed devices with `xcrun simctl list devices available`; use the existing Musalli-Test device on Omar's Mac if available. For Watch work, select `SpottrWatch` and the existing paired Watch. Do not create, erase or reset simulators as a setup shortcut. Physical builds require the intended signing team and matching host/Watch identities.

Optional gateway, with Node 22.9+:

```sh
./scripts/local-config.py
cd server
npm ci
npm start
```

The helper prepares ignored `.env` and a local gateway token without printing values. Add a provider key privately with `./scripts/local-config.py GEMINI_API_KEY` from the repository root, then restart the server. In **Coach → Coach settings**, enter the gateway URL and separate gateway token. Fresh setups default to `http://127.0.0.1:8787`; the existing gateway on Omar’s Mac uses **8788** because another service occupies 8787. Preserve that service. A physical phone needs reachable HTTPS. `GET /health` makes no provider request. The current server suite passes 62 offline checks. For an explicitly bounded owner session, use the [optional demo guard guide](../integrations/gateway/OWNER-DEMO.md); its offline checks and accepted one-attempt loopback flow do not establish a public HTTPS relay.

For offline checks after dependency setup, use `./scripts/check.sh` (also needs Python 3.10+). `--static` checks syntax only. Native/UI checks run separately in Xcode against the existing simulator. [Accounts and variable names](SETUP.md), [gateway configuration](../integrations/gateway/README.md), and [contributor boundaries](../CONTRIBUTING.md) have the details. Never put server keys or pairing credentials in Swift, screenshots, issues or PRs.

## Morning device rehearsal

1. **iPhone:** run a manual/hold plan first. For base squat/push-up, select phone camera, explicitly Start, check framing/overlay, compare a few visible full and partial cycles with the observed count, then Pause/Resume/End. Confirm source labels and saved timing. Retain any missed/extra-rep finding; do not describe this as an accuracy study.
2. **Pi USB:** investigate the known camera disconnect after roughly two seconds before promising a sustained demo. Test stable capture and phone inference with the existing authenticated/pinned connection. If it drops, show the paused state and explicit manual/phone fallback. Preserve other Pi services. [Physical evidence](../hardware/pi/EVIDENCE-2026-10-24.md).
3. **Physical Watch:** verify pairing, permissions, recording start, fresh HR/motion, pause/resume, set commands and stop/save. Missing readings must stay missing. Check compact camera and hold screens plus larger text. A simulator command walkthrough does not establish HealthKit capture. [Watch guide](watch-telemetry.md).
4. **Audible voice:** confirm off by default, enable it, trigger one fresh cue, then mute/pause during speech. Start another workout and verify off again. Check music/audio-route behavior on the phone; fake synthesizer tests did not establish this. [Voice boundary](voice-feedback.md).
5. **Demo/release:** rehearse the actual local flow with explicit fixture/live labels. Use the [judges' deck and script](judges-guide.md), updated to the 00:36 UTC release snapshot. Build 0.1 (3) is `VALID` and internally available alongside builds 1 and 2; export compliance is recorded. Latest build 3 is externally `IN_BETA_TESTING` with an `APPROVED` submission and the enabled 25-person invitation under [TestFlight #31](https://github.com/NakkiV7/oxhack-team/issues/31). The external group retains build 1 as a fallback; build 2 stays internal only. The public Apple page is verified. Install via the [iPhone/Watch guide](testflight.md), then verify actual device behavior. No install was performed during the public-page check. [Release notes](release-readiness.md).

## Owners and optional services

| Owner | Current next task |
| --- | --- |
| Misha — [voice #1](https://github.com/NakkiV7/oxhack-team/issues/1), [landing #2](https://github.com/NakkiV7/oxhack-team/issues/2) | Both open. ElevenLabs synthesis is unimplemented; use the existing playback/priority boundary. Landing improvements are merged, with browser acceptance and publication separate. |
| Nakki — [squat #4](https://github.com/NakkiV7/oxhack-team/issues/4) | Open. Check actual demo framing, full/partial cycles and observed errors before tuning shared geometry/counter code. |
| Azhar — [push-up #3](https://github.com/NakkiV7/oxhack-team/issues/3) | Closed. Native/prototype integration boundaries are documented; physical demo robustness and any count-accuracy follow-up remain distinct from issue closure. Coordinate shared counter edits with Nakki. PR #59 added standalone profile/cloud experiments; the [corrective checkpoint](evidence/pushup-prototype-integrity-2026-10-24.md) covers explicit uploads, provenance and 92 offline checks. Corrected prototype Tiger transaction and physical capture acceptance remain pending; the separate gateway schema acceptance does not validate this prototype path. |
| Omar — integration and remaining tracks | Device rehearsal, final release and explicit provider acceptance. [Team handoff](TEAM.md), [CV integration boundaries](teammate-integration.md). |

Tiger's gateway schema now has [provider-console acceptance](evidence/tiger-console-2026-10-24.md), with no data rows. Its adapter is tested offline, while the separate Node client's private-CA TLS failure still blocks live app persistence. Vultr packaging passed actual local image, restricted nonroot runtime, HTTP-boundary and Caddy parsing checks with zero provider calls; no hosted VM or HTTPS acceptance is claimed. Snowflake has an immutable public-benchmark import/evaluation path tested with fake responses. An authenticated read-only console check found the existing account and three suspended XS warehouses; no SQL workload or SQL API acceptance occurred. SQL API credentials, benchmark database/schema and bounded credit scope remain pending. The public PAMAP2 HR experiment has held-out results, including sparse coverage and a losing adaptation; it is not Watch/readiness/failure validation. Presage remains a proposal pending derived-vitals egress and account/credit decisions. Delta has a prepared v2 packet and no actual Delta run. A separate six-pair Codex calibration matched author controls; human adjudication, held-out judging and generated-output quality remain pending. Use the linked guides before spending credits or presenting a provider as live: [Tiger](tiger-live-readiness.md), [Vultr](vultr-deployment.md), [Snowflake](snowflake-analytics.md), [public benchmark](public-data-benchmark.md), [Presage](presage-integration.md), [Delta](delta-workflow.md).

# Morning handoff

Snapshot: 25 October 2026, merged through [PR #64](https://github.com/NakkiV7/oxhack-team/pull/64). The local iPhone/Watch MVP is ready for a practical device rehearsal. The remaining work is mostly physical acceptance and optional provider execution. Build **0.1 (2)** is processed and available to the owner’s **Spottr Internal** TestFlight group alongside build 1. The external OxHack group still contains only build 1, waiting for Apple beta review; build 2 was not submitted externally. [Build 2 evidence](evidence/testflight-build-2-2026-10-24.md) and [iPhone/Watch installation](testflight.md). Actual installation and device behavior remain unverified; Xcode discovery is not part of that installation route.

[PR #48](https://github.com/NakkiV7/oxhack-team/pull/48) is now merged: failed Watch collection releases the old capture so recording can be retried. Its source-double checks and Watch simulator build passed; real HealthKit acceptance is still separate. [Custom workouts #19](https://github.com/NakkiV7/oxhack-team/issues/19) and [artwork #18](https://github.com/NakkiV7/oxhack-team/issues/18) are closed; #19 was completed by PR #47.

## What works

- Today, local profile/goals, onboarding, history/data controls, connected and linear Skills, and deterministic session/week reports. Skill points describe game progress, not physical capacity.
- All 19 exercise lessons/icons, six push-up/squat phase illustrations, filming guides and private side-by-side video imports. Omar still needs to record the real lesson clips; automatic person cropping/background removal is not implemented.
- Approved Coach plans execute in catalogue order with explicit Start/Pause/End, real rest timing, manual reps and hold timers. Only base push-up/squat offer opt-in phone/Pi camera counting. Changing input confirms an unfinished-set reset; targets never invent reps or automatically end sets. Mixed sources/timings stay ordered in saved reports. [Usage and test evidence](custom-workouts.md).
- On-device pose inference, deterministic form/pacing cues, explicit local Apple voice feedback, and source-aware Watch controls. Voice starts off. Simulated/fake playback and callback tests passed; actual counting, real sensor capture and audible behavior still need the checks below.
- Goal-aware Gemini chat, proposals and session/week summaries share supplied training facts and goals only after an explicit action. The optional profile name stays local. All four gateway request types returned real synthetic 200 responses; two signed-simulator chat checks reached Google and displayed their actual answers. Physical phone networking and native live Gemini proposal/report acceptance remain pending. A [separate local HTTP fixture check](evidence/native-synthetic-coach-2026-10-24.md) displayed marked synthetic proposals/session/week summaries and an actionable connection failure with no external provider calls; its test records were cleaned up. Chat now receives server-owned catalogue/camera capability context after the first native response correctly abstained without it; one additional bounded native Send accepted the revised prompt by correctly distinguishing base push-up/squat camera tracking from manual reps and timed holds. [Actual reply and screenshot](evidence/native-gemini-chat-2026-10-24.md).

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

The helper prepares ignored `.env` and a local gateway token without printing values. Add a provider key privately with `./scripts/local-config.py GEMINI_API_KEY` from the repository root, then restart the server. In **Coach → Coach settings**, enter the gateway URL and separate gateway token. Fresh setups default to `http://127.0.0.1:8787`; the existing gateway on Omar’s Mac uses **8788** because another service occupies 8787. Preserve that service. A physical phone needs reachable HTTPS. `GET /health` makes no provider request.

For offline checks after dependency setup, use `./scripts/check.sh` (also needs Python 3.10+). `--static` checks syntax only. Native/UI checks run separately in Xcode against the existing simulator. [Accounts and variable names](SETUP.md), [gateway configuration](../integrations/gateway/README.md), and [contributor boundaries](../CONTRIBUTING.md) have the details. Never put server keys or pairing credentials in Swift, screenshots, issues or PRs.

## Morning device rehearsal

1. **iPhone:** run a manual/hold plan first. For base squat/push-up, select phone camera, explicitly Start, check framing/overlay, compare a few visible full and partial cycles with the observed count, then Pause/Resume/End. Confirm source labels and saved timing. Retain any missed/extra-rep finding; do not describe this as an accuracy study.
2. **Pi USB:** investigate the known camera disconnect after roughly two seconds before promising a sustained demo. Test stable capture and phone inference with the existing authenticated/pinned connection. If it drops, show the paused state and explicit manual/phone fallback. Preserve other Pi services. [Physical evidence](../hardware/pi/EVIDENCE-2026-10-24.md).
3. **Physical Watch:** verify pairing, permissions, recording start, fresh HR/motion, pause/resume, set commands and stop/save. Missing readings must stay missing. Check compact camera and hold screens plus larger text. A simulator command walkthrough does not establish HealthKit capture. [Watch guide](watch-telemetry.md).
4. **Audible voice:** confirm off by default, enable it, trigger one fresh cue, then mute/pause during speech. Start another workout and verify off again. Check music/audio-route behavior on the phone; fake synthesizer tests did not establish this. [Voice boundary](voice-feedback.md).
5. **Demo/release:** rehearse the actual local flow with explicit fixture/live labels. Use the [judges' deck and script](judges-guide.md). Build 0.1 (2) is `VALID` and internally available alongside build 1; export compliance is recorded. External build 1 access is waiting for Apple beta review under [TestFlight #31](https://github.com/NakkiV7/oxhack-team/issues/31), and build 2 was not submitted externally. Install via the [iPhone/Watch guide](testflight.md), then verify actual device behavior. [Release notes](release-readiness.md).

## Owners and optional services

| Owner | Current next task |
| --- | --- |
| Misha — [voice #1](https://github.com/NakkiV7/oxhack-team/issues/1), [landing #2](https://github.com/NakkiV7/oxhack-team/issues/2) | Both open. ElevenLabs synthesis is unimplemented; use the existing playback/priority boundary. Landing improvements are merged, with browser acceptance and publication separate. |
| Nakki — [squat #4](https://github.com/NakkiV7/oxhack-team/issues/4) | Open. Check actual demo framing, full/partial cycles and observed errors before tuning shared geometry/counter code. |
| Azhar — [push-up #3](https://github.com/NakkiV7/oxhack-team/issues/3) | Closed. Native/prototype integration boundaries are documented; physical demo robustness and any count-accuracy follow-up remain distinct from issue closure. Coordinate shared counter edits with Nakki. PR #59 added standalone profile/cloud experiments; the [corrective checkpoint](evidence/pushup-prototype-integrity-2026-10-24.md) covers explicit uploads, provenance and 92 offline checks. Live Tiger SQL and physical capture acceptance remain pending. |
| Omar — integration and remaining tracks | Device rehearsal, final release and explicit provider acceptance. [Team handoff](TEAM.md), [CV integration boundaries](teammate-integration.md). |

Tiger's adapter is tested offline, but its current private-CA TLS chain blocks live persistence. Vultr packaging passed actual local image, restricted nonroot runtime, HTTP-boundary and Caddy parsing checks with zero provider calls; no hosted VM or HTTPS acceptance is claimed. Snowflake has an immutable public-benchmark import/evaluation path tested with fake responses, not an executed warehouse result. The public PAMAP2 HR experiment has held-out results, including sparse coverage and a losing adaptation; it is not Watch/readiness/failure validation. Presage remains a proposal pending derived-vitals egress and account/credit decisions. Delta has prepared fixtures and no completed judge run. Use the linked guides before spending credits or presenting a provider as live: [Tiger](tiger-live-readiness.md), [Vultr](vultr-deployment.md), [Snowflake](snowflake-analytics.md), [public benchmark](public-data-benchmark.md), [Presage](presage-integration.md), [Delta](delta-workflow.md).

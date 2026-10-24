# Integration readiness — 24 October 2026

Current evidence ledger, with native changes merged through [PR #48](https://github.com/NakkiV7/oxhack-team/pull/48). Historical build notes describe earlier snapshots. Local profile/onboarding is not cloud identity; the gateway remains a single-owner prototype and optional sync is explicit.

## Merged native milestones

| PR | Implemented behavior | Acceptance boundary |
| --- | --- | --- |
| [#28](https://github.com/NakkiV7/oxhack-team/pull/28) | Approved custom plans run as manual/timed sessions | Explicit quantities, active hold time and set controls; no inferred camera support for other exercises |
| [#29](https://github.com/NakkiV7/oxhack-team/pull/29) | 19 exercise icons and six push-up/squat phase illustrations | Artwork is not a real exercise recording |
| [#30](https://github.com/NakkiV7/oxhack-team/pull/30) | Connected grid/linear skill views | Shared deterministic game rules; points are not physical capacity |
| [#32](https://github.com/NakkiV7/oxhack-team/pull/32) | Local profile/goals, onboarding and 19 lessons with private video imports/recording guides | User-filmed demonstrations remain to be recorded |
| [#33](https://github.com/NakkiV7/oxhack-team/pull/33) | Watch contrast and workout layout | Compact physical Watch visual acceptance remains pending |
| [#34](https://github.com/NakkiV7/oxhack-team/pull/34) | Explicit goals/weekly target in Coach, proposals and reports; optional name excluded | Eight focused native/UI checks passed; native network-to-provider acceptance remains separate |
| [#35](https://github.com/NakkiV7/oxhack-team/pull/35) | Pi pairing, trust, preview and phone pose-inference client | 31 native/UI and 23 Python checks passed; physical USB capture stalls/disconnects |
| [#36](https://github.com/NakkiV7/oxhack-team/pull/36) | Opt-in local speech with priorities, expiry, mute and foreground/session cancellation | Seven native fake-playback and eight core tests passed; audible phone/route acceptance remains pending |

## Providers, hardware and release

| Track | Actual evidence | Remaining gate |
| --- | --- | --- |
| Gemini | Local gateway returned 200 for chat, session summary, weekly summary and workout proposal using synthetic inputs. One signed-simulator chat also traversed the local gateway and displayed a real Google response. | Physical phone networking, native proposal/report acceptance, real-user factual review and measured usage. An earlier proposal 502 was followed by a successful diagnostic request; cause unresolved, cost metadata unavailable. |
| Tiger Data | Real development service exists. Console confirms the stored endpoint is current; it presents a Timescale private-CA chain. Snapshot/scalar adapter and migration have offline tests; gateway suite 36/36 passes. | Strict TLS fails with `SELF_SIGNED_CERT_IN_CHAIN`; no successful migration, persistence or live query is accepted. Resolve supported trust before another deliberate smoke attempt; see [diagnosis](tiger-live-readiness.md). |
| Vultr | Docker/Compose/Caddy packaging and instructions prepared; Compose and isolated runtime-layout checks pass. | Docker daemon unavailable, so image build/Caddy/container/TLS acceptance is pending. No VM deployed; credit eligibility, hostname and spending ceiling need agreement. See [deployment guide](vultr-deployment.md). |
| Snowflake | Bounded SQL API check implemented and tested with doubles. | Actual fixed statement/result, then separately scoped batch analytics and usage evidence. |
| HRT research | Forecast/evaluation design exists. | Eligible data, participant/session-held-out baselines, error/coverage and abstention. No trained personal capacity/readiness predictor is established. |
| Presage | Official SDK/API research and a 30-second opt-in design prepared. | SDK automatic derived-vitals transmission to an LLM needs a privacy/configuration decision before integration. No SDK capture or live physiological measurement. Credits remain unverified; see [proposal](presage-integration.md). |
| Local voice / ElevenLabs | Apple's local synthesizer integration is merged and tested with fake playback. | Audible phone acceptance. ElevenLabs synthesis is separate and has not run; an earlier supplied value was a key ID, not a working API secret. |
| Pi camera | Companion deployed; real authenticated HTTPS start/frames/stop and exact native transport trust checks succeeded. | USB camera disconnects after roughly two seconds; sustained iPhone capture/counting is unverified. Phone performs pose inference; no Pi inference claim. See [physical evidence](../hardware/pi/EVIDENCE-2026-10-24.md). |
| Watch | Companion transport, sensor adapter and merged contrast/layout exist. | Physical HealthKit/Core Motion recording, permission/source/freshness acceptance and compact-screen visual review. Simulator values cannot establish physiology. |
| Delta | Synthetic five-case judge packet and blocked run record prepared; zero judge/provider requests. | App was not found/launchable in filesystem checks. Official installation/download/legal step requires operator action; actual thread, review and iteration remain pending. See [packet](../evaluations/delta/2026-10-24/README.md). |
| App Store / TestFlight | App Store Connect record `6826666965` exists. Three actual-bundle privacy/identity tests passed; host/Watch App Store profiles are created, decoded and installed. | Build 0.1 (1) archived/exported, Apple validation/upload succeeded, and processing is VALID. Export-compliance information, beta review and tester availability remain pending; vendor SDK auditing remains separate. See [release audit](release-readiness.md) and [profiles](testflight-provisioning.md). |
| Landing / DEV / slides | Landing work and evidence handoffs exist locally. | Rendered/link/accessibility review, accurate illustrative/live labels, then separately authorized publication. No public release is implied by an app record or local page. |

## Reading the evidence

An implemented adapter is not a live connection. Synthetic inputs sent to a real Gemini endpoint establish protocol behavior, not personal coaching quality. Simulator/UI success establishes the exercised app flow, not a physical rep, audible output or sensor reading. A provisioned service/profile is not a persisted workout or a TestFlight build. Prepared judge controls are authored expectations, not evaluation scores.

Use [Gemini contracts](../integrations/gemini/README.md), [gateway setup](../integrations/gateway/README.md) and the focused guides above for reproduction. Do not revive the historical `noWindowsAvailable` report as a current UI blocker: subsequent native/UI runs passed. Native end-to-end provider networking still needs its own deliberate acceptance.

Release update: a signed iPhone archive containing the Watch companion passed the preflight archive step using the existing distribution identity and explicit profiles. IPA export also succeeded. Final configured-camera changes, Apple validation/processing and tester availability remain separate checkpoints. Watch callback fixes and a default-size visual cue check are merged in [PR39](https://github.com/NakkiV7/oxhack-team/pull/39). The public wearable benchmark is merged in [PR40](https://github.com/NakkiV7/oxhack-team/pull/40), with its limited participant coverage and losing adaptive result retained.

Latest acceptance: mixed configured camera/manual sets are merged in [PR #47](https://github.com/NakkiV7/oxhack-team/pull/47), with the complete UI save flow and 35 focused native checks passing. Watch collection failure/retry cleanup is merged in [PR #48](https://github.com/NakkiV7/oxhack-team/pull/48). The [morning handoff](morning-handoff.md) lists device checks; [native Gemini evidence](evidence/native-gemini-chat-2026-10-24.md) records the single bounded chat check.

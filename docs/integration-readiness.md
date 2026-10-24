# Integration readiness — 24 October 2026

Current evidence ledger, with changes merged through [PR #51](https://github.com/NakkiV7/oxhack-team/pull/51). Historical build notes describe earlier snapshots. Local profile/onboarding is not cloud identity; the gateway remains a single-owner prototype and optional sync is explicit.

## Merged native milestones

| PR | Implemented behavior | Acceptance boundary |
| --- | --- | --- |
| [#28](https://github.com/NakkiV7/oxhack-team/pull/28) | Approved custom plans run as manual/timed sessions | Explicit quantities, active hold time and set controls; no inferred camera support for other exercises |
| [#29](https://github.com/NakkiV7/oxhack-team/pull/29) | 19 exercise icons and six push-up/squat phase illustrations | Artwork is not a real exercise recording |
| [#30](https://github.com/NakkiV7/oxhack-team/pull/30) | Connected grid/linear skill views | Shared deterministic game rules; points are not physical capacity |
| [#32](https://github.com/NakkiV7/oxhack-team/pull/32) | Local profile/goals, onboarding and 19 lessons with private video imports/recording guides | User-filmed demonstrations remain to be recorded |
| [#33](https://github.com/NakkiV7/oxhack-team/pull/33) | Watch contrast and workout layout | Compact physical Watch visual acceptance remains pending |
| [#34](https://github.com/NakkiV7/oxhack-team/pull/34) | Explicit goals/weekly target in Coach, proposals and reports; optional name excluded | Eight focused native/UI checks passed; one native chat later reached Google; proposals/reports and physical acceptance remain separate |
| [#35](https://github.com/NakkiV7/oxhack-team/pull/35) | Pi pairing, trust, preview and phone pose-inference client | 31 native/UI and 23 Python checks passed; physical USB capture stalls/disconnects |
| [#36](https://github.com/NakkiV7/oxhack-team/pull/36) | Opt-in local speech with priorities, expiry, mute and foreground/session cancellation | Seven native fake-playback and eight core tests passed; audible phone/route acceptance remains pending |
| [#39](https://github.com/NakkiV7/oxhack-team/pull/39), [#48](https://github.com/NakkiV7/oxhack-team/pull/48) | Watch callback ownership, compact cue layout and failed-collection retry cleanup | Simulator build, compact-screen screenshot and recorder source-double checks passed; physical capture remains pending |
| [#47](https://github.com/NakkiV7/oxhack-team/pull/47) | Mixed camera/manual/hold plans, input reset confirmation and ordered saved sets | Full UI save flow and 35 focused native checks passed; physical rep quality remains separate |

## Providers, hardware and release

| Track | Actual evidence | Remaining gate |
| --- | --- | --- |
| Gemini | Local gateway returned 200 for chat, session summary, weekly summary and workout proposal using synthetic inputs. One signed-simulator chat also traversed the local gateway and displayed a real Google response. | Physical phone networking, native proposal/report acceptance, real-user factual review and measured usage. An earlier proposal 502 remains unexplained. PR #50 adds server-owned catalogue/camera capabilities after the first native answer abstained without them; the revised prompt is offline-tested, not paid-retested. |
| Tiger Data | Real development service exists. Console confirms the stored endpoint is current; it presents a Timescale private-CA chain. Snapshot/scalar adapter and migration have offline tests; the current combined gateway suite passes 51/51. | Strict TLS fails with `SELF_SIGNED_CERT_IN_CHAIN`; no successful migration, persistence or live query is accepted. Resolve supported trust before another deliberate smoke attempt; see [diagnosis](tiger-live-readiness.md). |
| Vultr | Actual pinned ARM64 image build, restricted nonroot runtime, health/HTTP boundaries, Compose and Caddy parsing passed locally with zero provider calls. Task containers were removed and VM stopped. | No hosted VM or HTTPS acceptance. Credit eligibility, hostname and spending ceiling need agreement. See [deployment guide and receipt](vultr-deployment.md). |
| Snowflake | Bounded SQL API check plus pinned public-benchmark import/reconciliation are implemented and tested offline. Default dry-run makes no network requests. | Real account/warehouse configuration and deliberate live SQL/import/usage acceptance. See [analytics workflow](snowflake-analytics.md). |
| HRT research | Public PAMAP2 participant-held-out HR forecasting completed. Frozen results report 10/30-second error, sparse coverage and a losing adaptive-bias result. | No Watch transfer, personal capacity/readiness, reps-to-failure or landmark-detector validation. See [benchmark](public-data-benchmark.md). |
| Presage | Official SDK/API research and a 30-second opt-in design prepared. | SDK automatic derived-vitals transmission to an LLM needs a privacy/configuration decision before integration. No SDK capture or live physiological measurement. Credits remain unverified; see [proposal](presage-integration.md). |
| Local voice / ElevenLabs | Apple's local synthesizer integration is merged and tested with fake playback. | Audible phone acceptance. ElevenLabs synthesis is separate and has not run; an earlier supplied value was a key ID, not a working API secret. |
| Pi camera | Companion deployed; real authenticated HTTPS start/frames/stop and exact native transport trust checks succeeded. | USB camera disconnects after roughly two seconds; sustained iPhone capture/counting is unverified. Phone performs pose inference; no Pi inference claim. See [physical evidence](../hardware/pi/EVIDENCE-2026-10-24.md). |
| Watch | Companion transport, sensor adapter and merged contrast/layout exist. | Physical HealthKit/Core Motion recording, permission/source/freshness acceptance and compact-screen visual review. Simulator values cannot establish physiology. |
| Delta | Synthetic five-case judge packet and blocked run record prepared; zero judge/provider requests. | App was not found/launchable in filesystem checks. Official installation/download/legal step requires operator action; actual thread, review and iteration remain pending. See [packet](../evaluations/delta/2026-10-24/README.md). |
| App Store / TestFlight | Build 0.1 (1) archived/exported, passed Apple validation/upload and is VALID. Export compliance is saved; owner membership and internal build access are verified. Five actual-bundle packaging checks passed for the source metadata follow-up. | External access is WAITING_FOR_BETA_REVIEW; the enabled 25-person link is not yet a usable external download. Actual phone/Watch install and vendor SDK privacy/signature acceptance remain separate. [Installation](testflight.md), [release audit](release-readiness.md). |
| Landing / DEV / slides | Landing improvements and an editable ten-slide judges’ deck with PDF/previews are merged. Deck rendering and image/metric checks passed; slides state their snapshot date. | Actual demo rehearsal, final landing mobile/link/accessibility review and explicit publication. DEV writing remains deferred. See [judges’ guide](judges-guide.md). |

## Reading the evidence

An implemented adapter is not a live connection. Synthetic inputs sent to a real Gemini endpoint establish protocol behavior, not personal coaching quality. Simulator/UI success establishes the exercised app flow, not a physical rep, audible output or sensor reading. A provisioned service/profile is not a persisted workout or a TestFlight build. Prepared judge controls are authored expectations, not evaluation scores.

Use [Gemini contracts](../integrations/gemini/README.md), [gateway setup](../integrations/gateway/README.md) and the focused guides above for reproduction. Do not revive the historical `noWindowsAvailable` report as a current UI blocker: subsequent native/UI runs passed. Physical phone networking, native proposals/reports and the revised chat prompt still need deliberate acceptance.

The [morning handoff](morning-handoff.md) lists the remaining device checks. The [native Gemini receipt](evidence/native-gemini-chat-2026-10-24.md) records the single bounded chat check. The existing local gateway on Omar’s Mac is on port **8788**; `/health` returned 200 with authentication and Gemini configuration present, without a provider call. Another service occupies the default 8787; preserve it. Health configuration is not a provider response.

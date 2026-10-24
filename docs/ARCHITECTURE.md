# How Spottr works

Current source through [PR #57](https://github.com/NakkiV7/oxhack-team/pull/57), 24 October 2026. Spottr is a native iPhone/Watch app with an optional Node gateway. Local workouts, profile/goals, lessons, skill progression and deterministic reports require no provider credentials. The phone owns workout state and feedback priority. The [evidence ledger](integration-readiness.md) and [morning handoff](morning-handoff.md) distinguish software checks, live requests and physical acceptance.

## Runtime ownership

| Component | Owns | Boundary |
| --- | --- | --- |
| iPhone — `Native/iOS` | Camera/imported-video inference, configured input selection, profile, private lesson videos, local history/reports and speech | Raw frames and private lesson imports stay local. Cloud requests and workout upload are explicit. |
| Shared core — `Shared/Core` | Legacy/configured sessions, rep counter and geometry, source/freshness rules, catalogue, game progression, reports and contracts | Foundation-only Swift used by the app targets and offline tests. |
| Watch — `Native/Watch` | User-started HealthKit workout, HR/motion observations, current display and permitted commands | Session/generation-scoped messages retain observed timestamps. Missing/stale readings remain unknown. |
| Gateway — `server` | Bearer authentication, bounded Gemini requests, Tiger snapshot/scalar ingestion and fixed Snowflake workflows | Server-held provider keys. Installation-scoped, single-owner prototype; no cloud user account or multi-user identity system. |
| Pi — `hardware/pi` | Explicit authenticated HTTPS capture, fresh JPEG delivery and expiring capture leases | Phone validates certificate pin/freshness and runs pose inference. No Pi inference claim. |

## From a plan to an actual record

`TrainingStore` coordinates the existing fixed camera/video workout and `ConfigurableSession`. An approved plan preserves catalogue exercise order, set counts, targets, units and rest targets. Each configured set begins in Manual. Only exact base `pushup`/`squat` IDs offer phone or Pi camera input; other exercises retain manual reps or active hold timers. Selecting input never starts capture. Explicit Start begins the set; explicit End records its actual quantity and begins rest. Reaching a target or advancing the queue never starts or ends work automatically.

Camera observations reuse `PoseGeometry` and `RepCounter`. Configured sessions own actual count, source, timings, cue and generation. Pause, failure, input changes and set transitions invalidate late callbacks and partial movement. Changing input after Start requires confirmation, resets only unfinished work and returns to preparation. Manual fallback is explicit. Discomfort prevents further sets; Finish saves only ended sets.

Mixed camera/manual/hold records stay ordered in `loggedSets`, with actual active/rest intervals and optional observed camera-cycle `repDurations`. Reports validate timing/source rather than infer durations from manual counts or total time. Legacy records without metadata still decode. Watch shows the same actual count/unit/source and brief form cue; it cannot invent a manual count or choose the camera. [Configured behavior and tests](custom-workouts.md).

Watch recording separately guards the owning session, builder, motion stream and callback generation. Paused/old/pre-resume samples are rejected. Failed collection discards the unsaved builder, stops motion and clears capture state so recording can be retried; late failures or saves cannot replace a newer recording. Simulator/source-double tests and compact-layout screenshots establish those exercised paths, not physical HealthKit/Core Motion capture. [Watch lifecycle](watch-telemetry.md).

The 19-exercise catalogue supplies units, support and prerequisites. Grid/linear skill views share deterministic game rules; XP is not physical capacity. Lessons show illustrations beside a selected private movie with its bytes/aspect ratio preserved. Nineteen icons, six phase illustrations and recording guides are complete; real clips and any later cropping remain separate work.

## Local feedback and optional AI

The local policy evaluates fresh form and observed pacing once per second and at movement boundaries. Eligible camera timing history supplies the prior mean/sample SD; manual/replay/discomfort/form-stop and invalid durations do not seed personal rhythm. Form/tracking/discomfort outrank routine cues, which have cooldowns and expiry. Actual rest is recorded; Watch HR alone establishes neither readiness nor a coaching command.

Opt-in Apple speech consumes cue identity, generation, priority and expiry. It starts off for each workout and cancels on mute, app inactivity and session transitions. No provider runs in the frame/cue loop. Fake-playback tests are distinct from audible phone/audio-route acceptance. ElevenLabs remains a separate unimplemented adapter. [Coaching](coaching-policy.md), [voice](voice-feedback.md).

Explicit Gemini chat, proposal and session/week summary requests send derived training facts, recorded Watch summaries and supplied goals/weekly target; the optional name and raw frames/sensor streams are excluded. Goal changes invalidate late output. Chat also receives server-owned canonical catalogue/camera capabilities, so app knowledge does not depend on workout history. Schema/semantic validation bounds IDs, quantities, evidence and generation; the user selects and approves exercises before replacing a plan. Fact membership alone does not establish entailment.

All four gateway request types returned real Gemini responses from synthetic inputs. Two signed-simulator chats reached Google. The first capability abstention motivated the server-context fix; a later single native Send correctly described base push-up/squat camera support and manual/timed alternatives. Separate marked fake-provider HTTP checks displayed proposals/reports and failure handling without a provider call. Physical networking and native live proposals/reports remain open. [Receipts](evidence/native-gemini-chat-2026-10-24.md), [fixture check](evidence/native-synthetic-coach-2026-10-24.md).

## Persistence, research and deployment

The phone stores local profile/history. Explicit Tiger sync uses immutable installation/workout UUID snapshots and content hashes, plus observed scalars at their measurement times. Identical retries return the same receipt; changed content conflicts. The adapter/migration are offline-tested, but the current private-CA endpoint fails strict TLS: no successful live migration, persistence or query is accepted. [Tiger diagnosis](tiger-live-readiness.md).

The public PAMAP2 experiment has frozen participant-held-out 10/30-second HR forecasts, sparse coverage and a retained losing adaptation. It does not validate Watch transfer, capacity/readiness or reps-to-failure. Snowflake now implements pinned public-artifact import, immutable run/payload lineage and fixed SQL reconciliation against local metrics. Dry-run/fake-network checks passed; actual warehouse execution remains pending. [Research](public-data-benchmark.md), [analytics](snowflake-analytics.md).

Pinned gateway packaging passed an actual local Linux/ARM64 build, restricted nonroot/read-only runtime, health/auth/HTTP checks, Compose and Caddy parsing with zero provider calls. No hosted Vultr VM, public HTTPS or AMD64 build is accepted. [Deployment receipt](vultr-deployment.md).

Presage remains a bounded opt-in proposal pending SDK derived-vitals LLM-egress and credit decisions; no capture is integrated. A separate Codex review exercised authored cue controls and retained an action-contract disagreement. It is not Delta usage, generated-output quality or runtime validation. Delta installation/agreement and an actual review remain pending. [Presage](presage-integration.md), [Codex receipt](../evaluations/codex/2026-10-24-cue-review/), [Delta](delta-workflow.md).

## Distribution and extension

Uploaded build 0.1 (1) passed validation/processing and has owner-internal TestFlight access. External access waits for beta review; physical installation is a separate check. Current source includes later follow-ups and is not identical to that frozen build. The SDK privacy/origin-signature audit remains open despite Apple processing. [Installation](testflight.md), [release evidence](release-readiness.md), [SDK follow-up #52](https://github.com/NakkiV7/oxhack-team/issues/52).

Extend existing owners rather than add parallel engines: exercise adapters need observed failure behavior; sensors need units/timestamps/freshness; cues need priority/cancellation; providers need bounded validated contracts and offline fakes. Keep teammate scopes separate, coordinate shared counter/generator changes and reuse existing simulators. [Contributing](../CONTRIBUTING.md), [ownership](TEAM.md), [remaining gates](ROADMAP.md), [keys/setup](SETUP.md). No CI/CD is planned.

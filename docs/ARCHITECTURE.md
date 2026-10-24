# How Spottr works

Spottr is a native iPhone and Watch app with a small optional Node gateway. Local workouts, profile/goals, lessons, skill progress and deterministic reports work without provider credentials. The phone owns workout state and feedback priority. This overview reflects merged native work through PR #36; the [evidence ledger](integration-readiness.md) separates that code from physical/provider acceptance.

## Runtime boundaries

| Component | Owns | Boundary |
|---|---|---|
| iPhone, `Native/iOS` | Camera/video frames, MediaPipe pose, manual/timed plans, profile, lesson videos, local voice, history and reports | Raw frames/private demo imports stay local. User explicitly requests cloud chat, summaries or sync |
| Shared core, `Shared/Core` | Rep/session state, source/freshness validation, catalogue, game rules, computed reports, provider contracts | Foundation-only Swift compiled by SwiftPM and both app targets |
| Watch, `Native/Watch` | Workout heart rate and motion magnitudes, controls and current session display | Timestamped session/generation-scoped WatchConnectivity messages; stale/missing values remain unknown |
| Gateway, `server` | Bearer authentication, input/output bounds, Gemini REST, Tiger transactions, bounded Snowflake check | Provider keys remain on the server. The current token is a single-owner hackathon boundary, not a user account system |
| Pi, `hardware/pi` | Explicit authenticated HTTPS capture, certificate pinning, fresh JPEGs and expiring lease | Phone runs pose inference. Companion is deployed; sustained USB capture remains blocked |

Flow: phone/Pi camera pose + available Watch observations → local workout/session state → deterministic cue policy → text event → opted-in local speech. Manual/timed custom plans use explicit quantities rather than camera counts. Completed records → reports and connected skill progression. Explicit requests → derived facts to Gemini, or a snapshot to the Tiger adapter. Live Tiger persistence is not yet established.

The 19-exercise catalogue defines units, support and game prerequisites. Only push-ups and squats have camera adapters. Grid and linear skill views share the same progression rules; attribute points and unlocks are game progress. Lessons combine illustrations with a user-selected private movie at its original aspect ratio. The recording guide does not imply all 19 real demonstrations have been filmed.

## Feedback that arrives at the right time

- Evaluate once per second and at completed-rep/form boundaries, entirely locally.
- Use observed camera timing history per exercise. After five eligible samples, compare a completed rep with the previous mean plus sample standard deviation (with a 0.25 s noise margin).
- Form/tracking and discomfort take priority. Routine cues have cooldown/expiry. Pause, source change and session generation changes invalidate stale work.
- Discomfort stops encouragement and continuation for the current workout. Planned targets never establish remaining physical capacity.
- Watch heart rate can provide fresh context; it alone does not initiate a coaching command or establish readiness.
- Record actual monotonic rest between completed sets. Missing legacy timings stay unknown.
- Local `AVSpeechSynthesizer` playback consumes event identity/priority/expiry. It defaults off per tracked workout, drops obsolete/lower-priority events and cancels on mute, app inactivity and session transitions. It has no ElevenLabs dependency; audible/device interruption acceptance is separate from fake playback tests.

Details and test cases: [coaching policy](coaching-policy.md).

## AI jobs

Gemini receives allowlisted derived facts, recent conversation and catalogue IDs. Explicit profile input adds goals/weekly target but excludes the optional name; changed goals invalidate late results. It explains session/week reports and proposes a structured workout. Schema and semantic checks reject unknown IDs, invalid quantities, stale generations and absent evidence. The user selects and approves exercises before a saved plan changes, then can start that manual/timed workout. Fact-ID membership does not prove the generated sentence is correct; evaluation also checks entailment. See [goal context](coach-goals.md).

Routine tests use deterministic fake network responses and synthetic histories. Bounded live checks are separate and record model, request/result and latency where available. Fixture success is never described as real physiology or a completed provider call.

## Storage and analytics

The phone stores completed records and the local profile on-device. The Tiger adapter implements immutable snapshots by installation/workout UUID and SHA-256 plus measured-time scalar observations: identical retries return the same receipt and changed content conflicts. Offline tests cover this contract. The current service endpoint presents a private-CA chain, so migration and live persistence remain blocked by strict TLS verification. Wider aggregates/compression remain a proposal. See [Tiger diagnosis](tiger-live-readiness.md).

Snowflake's implemented connection-check command runs one fixed statement; batch public-data/feature evaluation remains future work. [Vultr packaging](vultr-deployment.md) exists, but no VM is deployed and container execution is unverified. The [Presage proposal](presage-integration.md) keeps source/quality separate from Watch; SDK automatic derived-vitals LLM transmission must be resolved before a local-only claim or live check. Delta has a prepared synthetic judge packet but no actual review. These are distinct integration boundaries, not extra per-frame services.

## Extending Spottr

- Add exercises in `ExerciseCatalog`, then define units, permitted support, game prerequisites and artwork. Do not enable camera tracking for a new variation without implementing its adapter and failure behavior.
- Add a sensor with native units, source, observation timestamp and freshness/coverage rules. Missing values stay optional; never substitute simulator physiology in normal use.
- Add a cue reason in the local policy with a behavior test, priority/cooldown/expiry and an audio-consumer test. Provider calls do not belong in the frame loop.
- Add a provider behind the existing gateway. Validate request/response contracts, bound time/size, sanitize failures, retain local functionality and use fake adapters for routine tests.
- Keep teammate CV, voice and landing work on separate feature branches. Small PRs include reproducible checks and remaining acceptance gaps. Regenerate the Xcode project only at integration to avoid generated-file conflicts.

Start with [README](../README.md), [contribution guide](../CONTRIBUTING.md), [owners](TEAM.md), [open work](ISSUES.md) and [accounts/keys](SETUP.md). No CI/CD is required.

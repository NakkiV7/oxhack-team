# How Spottr works

Spottr is a native iPhone and Watch app with a small optional Node gateway. Local workouts, form cues, history, skill progress and deterministic reports work without provider credentials. The phone owns workout state and feedback priority.

## Runtime boundaries

| Component | Owns | Boundary |
|---|---|---|
| iPhone, `Native/iOS` | Camera/video frames, MediaPipe pose, workout controls, cue presentation, local history and reports | Raw camera frames stay local in the current phone path. User explicitly requests cloud chat, summaries or sync |
| Shared core, `Shared/Core` | Rep/session state, source/freshness validation, catalogue, game rules, computed reports, provider contracts | Foundation-only Swift compiled by SwiftPM and both app targets |
| Watch, `Native/Watch` | Workout heart rate and motion magnitudes, controls and current session display | Timestamped session/generation-scoped WatchConnectivity messages; stale/missing values remain unknown |
| Gateway, `server` | Bearer authentication, input/output bounds, Gemini REST, Tiger transactions, bounded Snowflake check | Provider keys remain on the server. The current token is a single-owner hackathon boundary, not a user account system |
| Pi, `hardware/pi` | Explicit camera capture, fresh preview frames and expiring capture lease | Camera transport is separate from pose inference; actual hardware evidence is recorded separately |

Flow: camera pose + Watch observations → local workout/session state → deterministic cue policy → text event → optional audio consumer. Completed records → local reports and skill progress. Explicit requests → grounded derived facts to Gemini, or an immutable session snapshot to Tiger.

## Feedback that arrives at the right time

- Evaluate once per second and at completed-rep/form boundaries, entirely locally.
- Use observed camera timing history per exercise. After five eligible samples, compare a completed rep with the previous mean plus sample standard deviation (with a 0.25 s noise margin).
- Form/tracking and discomfort take priority. Routine cues have cooldown/expiry. Pause, source change and session generation changes invalidate stale work.
- Discomfort stops encouragement and continuation for the current workout. Planned targets never establish remaining physical capacity.
- Watch heart rate can provide fresh context; it alone does not initiate a coaching command or establish readiness.
- Record actual monotonic rest between completed sets. Missing legacy timings stay unknown.
- Voice playback consumes the event identity/priority/expiry; it must cancel obsolete requests and never overlap routine speech.

Details and test cases: [coaching policy](coaching-policy.md).

## AI jobs

Gemini receives allowlisted derived facts, recent conversation and catalogue IDs. It explains session/week reports and proposes a structured workout. Schema and semantic checks reject unknown IDs, invalid quantities, stale generations and absent evidence. The user selects and approves exercises before a saved plan changes. Fact-ID membership does not prove the generated sentence is correct; evaluation also checks entailment.

Routine tests use deterministic fake network responses and synthetic histories. Bounded live checks are separate and record model, request/result and latency where available. Fixture success is never described as real physiology or a completed provider call.

## Storage and analytics

The phone stores completed session records locally. Tiger stores immutable snapshots by installation/workout UUID and SHA-256 plus a measured-time scalar hypertable. Identical retries return the same receipt; changed content conflicts instead of overwriting. Timestamp duplication does not manufacture observations. Wider continuous aggregates and compression are a planned analytics layer until executed and measured.

Snowflake has a separate batch-evaluation role: versioned public-data/model features and retrospective comparisons exported from the operational store. Its current connection-check command runs one fixed statement; that is not yet the full analytics pipeline. Vultr is the intended gateway host. Presage is an optional explicitly started camera measurement, with quality and source kept distinct from Watch. See the [readiness ledger](integration-readiness.md).

## Extending Spottr

- Add exercises in `ExerciseCatalog`, then define units, permitted support, game prerequisites and artwork. Do not enable camera tracking for a new variation without implementing its adapter and failure behavior.
- Add a sensor with native units, source, observation timestamp and freshness/coverage rules. Missing values stay optional; never substitute simulator physiology in normal use.
- Add a cue reason in the local policy with a behavior test, priority/cooldown/expiry and an audio-consumer test. Provider calls do not belong in the frame loop.
- Add a provider behind the existing gateway. Validate request/response contracts, bound time/size, sanitize failures, retain local functionality and use fake adapters for routine tests.
- Keep teammate CV, voice and landing work on separate feature branches. Small PRs include reproducible checks and remaining acceptance gaps. Regenerate the Xcode project only at integration to avoid generated-file conflicts.

Start with [README](../README.md), [contribution guide](../CONTRIBUTING.md), [owners](TEAM.md), [open work](ISSUES.md) and [accounts/keys](SETUP.md). No CI/CD is required.

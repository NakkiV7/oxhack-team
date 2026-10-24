# Proposed Presage recovery measurement

Research snapshot: **24 October 2026**. This is a proposal, with no SDK integration or live measurement yet. No camera, account, API key, credit balance or physiological data was accessed in this research.

## Recommended role

Use the **SmartSpectra Swift SDK** for a person-initiated front-camera check between sets. It computes metrics on the phone and supplies observable lifecycle, validation and metric output. The current released package is [`SmartSpectra-Swift` v3.4.0](https://github.com/Presage-Security/SmartSpectra-Swift/releases/tag/v3.4.0), published 29 September 2026; its [package manifest](https://github.com/Presage-Security/SmartSpectra-Swift/blob/v3.4.0/Package.swift) requires iOS 17 and downloads one binary XCFramework of approximately 63 MB compressed. Pin the exact version after approval; do not add another application target. The old RC quickstart linked in the original design describes a prerelease channel and is not the version authority.

The **Physiology API / developer portal** is the account, authentication and service side of the SDK ecosystem. The official material reviewed does not establish a separate public REST contract for uploading a 30-second phone video and receiving pulse/breathing JSON. Do not invent that endpoint or forward camera video through Spottr's gateway. The existing `PRESAGE_API_KEY` environment placeholder and gateway `adapterImplemented: false` are configuration scaffolding, not a working integration.

## Constraints that affect the product

Presage's [v3.4.0 model documentation](https://github.com/Presage-Security/SmartSpectra/blob/v3.4.0/docs/model-cards-and-limitations.md) describes:

| Candidate output | Documented window / range | MVP treatment |
| --- | --- | --- |
| Pulse | 12-second average; 40–110 bpm | Optional camera estimate. Post-exercise values can exceed this supported range; abstain rather than clamp or substitute Watch data. |
| Breathing | 30-second average; 5–40 breaths/min; confidence is zero before the full window | Best effort only in a hard 30-second check. Startup, tuning or motion may leave no valid result. |
| HRV | 60-second window | Exclude from this check. |

A 30-second countdown cannot promise a breathing result. The stable mounted phone must frame one stationary person, including face and chest, with even lighting and no talking. Large motion can yield misleadingly confident estimates. SDK confidence is a quality field, not diagnostic certainty. Do not derive readiness, capacity, a safe heart-rate threshold or game attribute points from these measurements. The user still chooses when to start or finish; discomfort continues to route to stopping.

## Data-sharing decision before a live integration

The SDK's [LLM Insights documentation](https://github.com/Presage-Security/SmartSpectra/blob/v3.4.0/docs/llm-insights/index.md) describes **automatic** derived-vitals snapshots when pulse, breathing and HRV first stabilize, then every 60 seconds. The first can occur around 15 seconds. Presage forwards numeric metric series to an LLM; simply avoiding `requestInsight()` or ignoring `sdk.insight` does not disable automatic sends. Requesting fewer metrics is not documented as a reliable opt-out.

The public [Swift configuration reference](https://github.com/Presage-Security/SmartSpectra/blob/v3.4.0/swift/docs/api-reference.md) reviewed exposes no verified switch to disable those automatic insights. Resolve this with a documented supported setting/version or account configuration before describing the measurement as local-only. If automatic metric transmission cannot be disabled, enabling it needs a separate explicit product decision, accurate user disclosure and approval of the actual data path. This proposal does not authorize biometric egress.

Set `config.enableTelemetry = false` before any measurement. This disables the SDK's optional diagnostic summaries according to [its telemetry documentation](https://github.com/Presage-Security/SmartSpectra/blob/v3.4.0/docs/telemetry-and-privacy.md); it does **not** disable authentication, metering or LLM Insights. Do not request expressions, EDA, pressure waveforms or HRV. Do not retain frames, send measurements to Gemini/Tiger, or add HealthKit writes in this first integration. Review the actual SDK privacy manifest, signature and transitive dependencies before release; no SDK archive was downloaded or inspected here.

## Authentication and budget

The [API-key guide](https://github.com/Presage-Security/SmartSpectra/blob/v3.4.0/swift/docs/option-1-api-key.md) requires a Presage developer account with verified email and an account key. For an authorized internal check, inject an existing key privately into the native adapter; keep it out of source, build settings, logs and screenshots. A server environment variable alone does not authenticate a native SDK session. Missing configuration leaves the feature unavailable and does not request camera access.

For distribution, prefer the documented [OAuth flow](https://github.com/Presage-Security/SmartSpectra/blob/v3.4.0/swift/docs/option-2-oauth.md): register the exact host bundle ID `com.omarchoudhry.spottr` and team `952HTWFJX7`, obtain `PresageService-Info.plist`, and add App Attest capability/provisioning on a supported physical device. Development identities require the portal's sandbox setting; production identities include TestFlight. Those account/capability changes are not performed or authorized by this proposal.

The reported remaining ~50 minutes has not been verified. Confirm the current plan, remaining credits and billing unit before the final check; do not assume 30 seconds equals exactly one credit. The official [account tooling reference](https://github.com/Presage-Security/SmartSpectra/blob/v3.4.0/docs/mcp-server.md) distinguishes usage reads from key rotation and app registration. Do not rotate keys, register apps, purchase credits or accept terms as a side effect of checking configuration. Reserve **one deliberate, at most 30-second capture attempt** for final physical acceptance. No warm-up probe, automatic retry, poor-signal extension or background polling. Authentication/quota/network failures stop the attempt; record actual account usage before/after when available.

## Proposed native boundary and lifecycle

1. Add an optional recovery action, **Check with front camera · up to 30 sec**, available only during rest. Explain the selected data-sharing mode before the person taps Start. Neither opening recovery nor granting camera permission starts measurement.
2. Serialize a single SDK owner with existing camera workers. Stop/drain workout capture, invalidate its callbacks, and cancel voice coaching before Presage starts. Request only `[.pulseRate, .breathingRate]` after the data-sharing decision above is resolved. Use `SmartSpectraSDK`, `useCamera(.front)`, `start()` and `stop()`; no copied quickstart auto-start behavior.
3. An app-owned controller keeps session ID, set generation and a unique measurement ID. A monotonic deadline of 30 seconds starts immediately before the SDK start request, including its startup time. Stop, dismissal, scene inactivity, next set, finished workout, permission denial, quota failure and the deadline invalidate that ID and stop SDK processing. No automatic resume. Serialize teardown before another attempt; an asynchronous start that returns after cancellation must immediately be stopped and cannot publish results. Exact SDK cancellation/teardown behavior needs an adapter test and device acceptance before claiming the bound is enforced.
4. Observe `processingStatus`, `validationStatus`, `error` and `metrics`. Publish only samples from the current measurement in rest. SDK metric payloads contain newly available samples rather than a complete history: an empty pulse array is a gap, not a zero and not an instruction to clear a still-fresh retained sample. Stop/clear input state on a new attempt. Copy an accepted final result before `stop/reset` if the selected SDK method clears output.
5. Present independent **Camera estimate · Presage** and **Apple Watch** rows with their own observation times. A missing, stale or conflicting source cannot overwrite the other. No averaging, automatic source switching, agreement badge or claim that Watch is ground truth. At completion show a timestamped snapshot, then clear it for a new set/workout. Persistence is outside the first check.

## Verified sample shape and offline tests to write first

The [v3.4.0 schema](https://github.com/Presage-Security/SmartSpectra/blob/v3.4.0/docs/data-types.md) defines `MeasurementWithConfidence` with `value: Float`, `stable: Bool`, `confidence: Float` (0–100), and `timestamp: Int64` (**Unix epoch microseconds**). Swift rate arrays are `metrics.cardio.pulseRate` and `metrics.breathing.rate`. Keep these distinct from monotonic lifecycle deadlines; do not interpret microseconds as milliseconds or receipt time. SDK confidence never populates Watch data.

An SDK-independent internal sample should carry measurement/session/generation IDs, source `.presageFrontCamera`, metric/unit, value, original observation time, receipt time, stable flag, confidence and the measurement interval. This is an app adapter contract, not a proposed Presage HTTP payload. Keep source and quality outside the existing `SensorReading`/`WatchTelemetry` structures rather than disguising a camera sample as Watch telemetry.

Proposed acceptance policy, requiring validation rather than physiological claims: finite positive values, confidence within 0–100, `stable == true`, current validation `.ok`, relevant analysis window filled, supported metric range, and an observation timestamp within the current capture interval. For a live display, use a proposed five-second freshness limit and at most two seconds future clock tolerance; stale snapshots must be labeled as recorded rather than live. Preserve quality fields and missing states; never synthesize confidence.

First tests should cover: no start before explicit action; permission/config failure; one start per tap; hard deadline and no retry; cancellation during pending start; late metrics after dismissal/new set; exclusive camera ownership; timestamp-unit conversion; NaN/infinity/out-of-range confidence; stale/future/duplicate samples; empty incremental arrays; 12/30/60-second warm-up boundaries; invalid validation; missing Watch; and disagreeing synthetic Watch/camera values retained under their separate labels. Fixtures must be clearly synthetic and must never execute SDK authentication or camera capture. No fixture or source files are added at this proposal stage.

## Remaining decisions and acceptance

Proceed with the SDK-independent tests/controller after design review. Integrate the binary only after resolving automatic Insights egress and choosing internal API-key versus distribution OAuth authentication. Then verify package/API compatibility, privacy assets, camera ownership and lifecycle using fake adapter tests, followed by the single authorized physical check. Record version, actual capture duration, permissions, validation/quality, source timestamps, cancellation outcome and account usage without raw face images or private key material. A valid fixture, a compiled adapter and an actual physiological measurement are separate evidence.

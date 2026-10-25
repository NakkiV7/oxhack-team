# Watch sensor roadmap — issue #102

Code and Apple documentation reviewed **25 October 2026**. This is a proposal, not implemented sensor support or physical-device acceptance.

## Implemented

[`WorkoutRecorder`](../Native/Watch/WorkoutRecorder.swift) explicitly starts an indoor strength workout, requests workout-writing and heart-rate-reading access, and forwards timestamped bpm readings. Core Motion is requested at 10 Hz; at most one instantaneous acceleration magnitude (g) and rotation magnitude (rad/s) pair is forwarded per second. Watch messages carry latest readings approximately every two seconds, not every sensor observation. Session/stream guards reject stale callbacks; phone reports deduplicate measurement timestamps. No energy, running, respiratory or temperature fields exist in the current wire/storage contract. Physical sensor acceptance remains pending; see [capture limits](watch-telemetry.md).

## Available possibilities

| Signal | Supported direction and boundary |
| --- | --- |
| Active energy | Apple automatically records estimates; read workout statistics in kcal, preserving the accumulation interval. Never sum repeated cumulative totals. [Energy type](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/activeenergyburned). |
| Running distance/speed/pace | A deliberately selected running configuration can supply distance and other relevant types. Check actual `typesToCollect`; strength recording does not establish running coverage. Distance is cumulative; derive pace only from positive, compatible observed speed/distance intervals and label the derivation. [Workout configuration](https://developer.apple.com/documentation/healthkit/running-workout-sessions), [available types](https://developer.apple.com/documentation/healthkit/hkliveworkoutdatasource/typestocollect), [distance](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/distancewalkingrunning). |
| Cadence | A possible later Core Motion path: `CMPedometerData.currentCadence` is steps/second and can be nil or unsupported. It needs platform/runtime checks and its own authorization/interval handling; do not derive running cadence from wrist magnitude. [Apple cadence documentation](https://developer.apple.com/documentation/coremotion/cmpedometerdata/currentcadence). |
| Respiratory rate / wrist temperature | Apple documents respiratory measurements in sleep comparisons and wrist temperature during sleep, with device/settings requirements. These are potential dated historical context, not generally available live strength-workout streams. Wrist temperature cannot be requested on demand. [Sleep](https://support.apple.com/en-gb/108906), [temperature](https://support.apple.com/en-gb/102674). |

Request each HealthKit type when needed. Authorization completion and workout-writing authorization do **not** reveal heart-rate/energy/distance read grants. Empty results can reflect privacy, unsupported hardware, settings or absent samples; display “unavailable,” not “denied” or zero. Preserve measurement start/end, source, unit and receipt time separately. [Apple authorization/privacy](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data).

Zones are optional descriptive context, not safe-exercise clearance. On supported OS versions, retain HealthKit zone boundaries and their system/user/app provenance; otherwise omit zones. Do not invent thresholds with `220 − age`, infer readiness from BMI, or convert missing HR into recovery advice. [Apple zone provenance](https://developer.apple.com/documentation/healthkit/accessing-workout-zone-data).

## Smallest compatible next slice

1. **Energy first; running second.** Add optional typed interval/cumulative metrics to `Telemetry.swift`, recorder callbacks, companion transport, phone persistence and reports. Keep existing fields/old-history decoding. Explicit running mode must select activity/location; do not encode metres as reps/hold seconds or relabel strength history. Defer routes/GPS and cadence.
2. Negotiate telemetry version 2 between phone and Watch; default to version 1. Extend `WorkoutSync` with an explicit v2 projection and gateway `/v2/workouts`/readback contract; keep `/v1` strict and unchanged. Unsupported servers retain new metrics locally with an actionable message, never silently erase them.
3. Add a reviewed additive Tiger migration for interval metrics, units and accumulation semantics; preserve migration 001 and immutable workout hashes. Versioned ingestion/readback must retain owner binding, bounded payloads/time windows and exact replay/conflict behavior. Already-uploaded snapshots cannot be enriched in place; retain additional metrics locally rather than overwrite them. Deploy server/schema before enabling v2 clients; strict TLS remains a separate gate.
4. Test old/new decoding, missing/invalid units, repeated cumulative totals, pause/resume epochs, delayed callbacks, message gaps, unsupported running types, v1 fallback, export, replay/conflicts and report coverage. Then explicitly accept permissions, lifecycle and real readings on a physical Watch. Simulator/fake data cannot establish sensor accuracy or availability.

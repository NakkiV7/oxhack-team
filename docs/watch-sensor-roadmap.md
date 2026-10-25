# Watch sensor roadmap — issue #102

Code and Apple documentation reviewed **25 October 2026**. Active energy is implemented in source; it is **not in TestFlight build 5**. Other additions below remain planned. Physical sensor acceptance remains pending.

## Implemented

[`WorkoutRecorder`](../Native/Watch/WorkoutRecorder.swift) explicitly starts an indoor strength workout, requests workout-writing plus heart-rate/active-energy reading access, and forwards timestamped bpm readings. Core Motion is requested at 10 Hz; at most one instantaneous acceleration magnitude (g) and rotation magnitude (rad/s) pair is forwarded per second. Watch messages carry latest readings approximately every two seconds, not every sensor observation.

The local energy addition retains a typed **cumulative kcal estimate, recording UUID and `asOf` timestamp**. Reports select the latest observation per recording; repeated totals are not summed. Equal-time corrections can replace a previous total, including downward revisions. Old history still decodes. Energy persists in local history/export and appears on the phone report only; compact Watch metrics are unchanged. Legacy cloud sync omits energy and energy-only packets, while preserving legacy empty envelopes and mixed sensor bytes. Coach requests do not include energy. See [the dated evidence and limitations](evidence/watch-active-energy-2026-10-25.md) and [capture details](watch-telemetry.md).

## Available possibilities

| Signal | Supported direction and boundary |
| --- | --- |
| Active energy | Local implementation above uses workout statistics in kcal; cloud support remains planned. Never sum repeated cumulative totals. [Apple energy type](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/activeenergyburned). |
| Running distance/speed/pace | Deliberately select a running configuration and check actual `typesToCollect`; strength recording does not establish running coverage. Distance is cumulative. Derive pace only from compatible positive observed intervals and label the derivation. [Configuration](https://developer.apple.com/documentation/healthkit/running-workout-sessions), [available types](https://developer.apple.com/documentation/healthkit/hkliveworkoutdatasource/typestocollect), [distance](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/distancewalkingrunning). |
| Cadence | A later Core Motion path: `CMPedometerData.currentCadence` is steps/second and can be nil or unsupported. Check platform/runtime support, authorization and intervals; wrist magnitude is not running cadence. [Apple cadence](https://developer.apple.com/documentation/coremotion/cmpedometerdata/currentcadence). |
| Respiratory rate / wrist temperature | Potential dated historical context, not generally available live strength-workout streams. Apple documents sleep measurements and device/settings requirements; wrist temperature cannot be requested on demand. [Sleep](https://support.apple.com/en-gb/108906), [temperature](https://support.apple.com/en-gb/102674). |

Request each HealthKit type when needed. Authorization completion and workout-writing authorization do **not** reveal read grants. Empty results can reflect privacy, unsupported hardware, settings or absent samples; do not infer denial or zero. Preserve observed timing, source and units. [Apple privacy](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data).

Zones are descriptive context, not safe-exercise clearance. Retain system/user/app boundary provenance when supported; otherwise omit zones. Do not invent `220 − age` thresholds, infer readiness from BMI, or turn missing HR into recovery advice. [Apple zone provenance](https://developer.apple.com/documentation/healthkit/accessing-workout-zone-data).

## Smallest compatible next slice

1. Physically accept the local energy path: explicit permission flow, pause/resume, delayed callbacks, missingness and actual estimates. Simulator/fake data cannot establish sensor availability or accuracy.
2. Add running only through explicit activity/location selection and typed observed intervals. Do not encode metres as reps/hold seconds or relabel strength history. Defer GPS and cadence.
3. Before cloud energy/running, define negotiated v2 phone/Watch and gateway ingestion/readback contracts plus a reviewed additive Tiger migration. Keep strict v1, owner binding, immutable hashes and exact replay/conflict behavior; unsupported servers retain new metrics locally. No v2 or migration exists yet; strict TLS is a separate gate.
4. Test old/new decoding, units, cumulative duplicates/revisions, epochs, gaps, unsupported types, export and version fallback before enabling new clients.

# Watch telemetry: capture and limits

Spottr explicitly records a traditional indoor strength workout. Heart rate is bpm, wrist user-acceleration magnitude is g, and wrist rotation-rate magnitude is rad/s, each with its measurement timestamp. Missing readings remain absent. HealthKit authorization completion does not establish a read grant or a readable sample.

**25 October energy checkpoint:** the source adds optional local active-energy estimates; this change is **not included in TestFlight build 5**. See [the dated acceptance receipt](evidence/watch-active-energy-2026-10-25.md).

## Latest readings and cumulative energy

Motion updates are requested every 0.1 seconds, but the adapter forwards at most one instantaneous magnitude pair per second. These are not one-second averages, raw vectors, joint angles, lifting force or validated rep counts. Watch messages retain the latest readings and are sent approximately every two seconds. Phone reports deduplicate measurement timestamps and exclude stale HR/motion readings. This is not a lossless sensor archive.

The energy path requests active-energy reading access, enables that collection type on the workout data source, and reads `HKStatistics.sumQuantity()` in kcal with `endDate` as `asOf`. `ActiveEnergy` stores the recording UUID, cumulative estimate and observed timestamp. Current-run/state/measurement-time guards reject old, paused or invalid callbacks. The Watch store rejects an older same-recording `asOf`; equal-time corrections remain possible. A new recording clears the previous local estimate.

Phone session ingestion requires matching session identity, a fresh envelope, finite nonnegative kcal and a timestamp within the session/future bounds. Energy is cumulative, so its observation is not expired using HR's 12-second freshness rule. Reports keep the latest `asOf` per recording, with later envelope time resolving equal-time revisions; they neither sum repeated totals nor force values to increase. Separate recording UUIDs remain separate estimates.

Local history/export preserve energy; missing optional fields in old history decode normally. The phone report labels each value **Estimated active energy**, `kcal`, and its `asOf` time, or displays a missing-data message. Compact Watch metrics are unchanged. Energy is excluded from Coach grounding and strict `/v1/workouts` projection. Energy-only packets are omitted from that projection; legacy all-nil envelopes and mixed sensor packets retain their prior bytes. There is no cloud-energy v2 contract or Tiger migration.

## Callback lifecycle

`WatchCaptureLifecycle` owns run, collection, pause and motion-stream state. The recorder checks the originating HealthKit session/builder inside main-actor callbacks. Ending/replacing a run rejects its callbacks; pausing rejects samples. Resume starts a fresh motion stream and throttle; cached pre-resume measurements cannot become fresh merely through late delivery. Authorization finishing during a pause starts collection paused. Collection/save callbacks cannot overwrite a newer run's status.

The earlier `beginCollection(false)` cleanup gap is fixed: only the matching failed collection stops motion, clears session/builder state, ends the session and discards its builder. The injected SDK harness covers this without creating a HealthKit workout. A physical lifecycle fixture should still exercise A→B delayed callbacks/failure, pause/resume cached readings, and B's delayed save after C starts.

## Verification and remaining work

The current energy checkpoint passed **68 XCTest + 122 Swift Testing** Core cases, **10 recorder + 5 Watch-store** SDK-double cases, the Watch simulator build, and an unsigned generic-watchOS device-SDK build. The device-SDK build had two known warnings: missing AccentColor and skipped App Intents metadata. These compile/fake checks do not establish physical recording, read permission, real estimates or accuracy. The synthetic phone report and its UI RED/GREEN are documented in the [energy receipt](evidence/watch-active-energy-2026-10-25.md). Earlier layout acceptance remains [separate simulator evidence](watch-simulator-acceptance.md).

Running distance/pace/cadence, richer motion, historical HRV/sleep/respiratory context and zone provenance remain planned in the [sensor roadmap](watch-sensor-roadmap.md). No wrist-signal interpretation establishes whole-body form, readiness or recovery.

Apple references: [live collected types](https://developer.apple.com/documentation/healthkit/hkliveworkoutdatasource/typestocollect), [active energy](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/activeenergyburned), [authorization privacy](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data), and [device motion](https://developer.apple.com/documentation/coremotion/cmdevicemotion).

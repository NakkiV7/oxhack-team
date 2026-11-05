# Watch data and training pages

Continue the user's delegated overhaul of Spottr. The intended experience is a useful Today page, clear measured session reports and longitudinal Insights, optional Watch onboarding with installation/permissions, and durable Watch data across temporary disconnection. Keep core training available without a Watch/account/purchase. No faces, Chrome, new simulators, paid runtime service or health uploads. Preserve build17 and dependencies; bulk scratch remains on the Extreme SSD.

## Decisions made for this implementation

- Heart rate, active energy, wrist acceleration and angular speed are Watch measurements. Motion is summarized over bounded ten-hertz windows rather than misrepresenting a once-per-second instantaneous value as motion consistency.
- Use a durable WatchConnectivity batch alongside live latest readings. Late delivery may enrich only its matching known session, bounded to its recorded lifetime; duplicates, foreign sessions, malformed readings and future samples cannot alter counts/history. No new reps are inferred from motion.
- New session records carry optional wall-clock endedAt, with legacy decoding intact. Delayed historical telemetry uses a distinct validated import route, never bypassing live freshness checks or changing rep/set data. Saving failures must stay visible and preserve existing evidence.
- Reports include measured HR range and timeline, time-weighted HR/zone durations from nearby samples, observation coverage/gaps, true recorded rep timing and variability/cadence, active/rest time and work/rest ratio, energy from cumulative recording deltas, and wrist-motion RMS/peak/variation with units. No linear speed, force, calories, HRV or clinical readiness is invented from wrist acceleration or average HR.
- Five descriptive intensity bands use explicit optional maximum heart rate: manual max or an optional adult age-based220-minus-age estimate, clearly labelled as estimates and distinct from Apple's private zone settings. No default age/max or universal safety threshold. No zones without a configured basis. No target-exercise prescription from estimated zones.
- Optional Apple Health snapshot reads existing resting/walking HR, SDNN HRV, cardio fitness, one-minute recovery, respiration/oxygen when available, steps and walking/running distance. Latest samples show timestamps/source; daily quantities stay in their own current-day context. Historical Health readings are not labelled live workout measurements or copied into workout evidence. Authorization completion does not prove read access; absent values stay absent.
- Optional setup lives in new-user onboarding and repeatable settings/help. TestFlight Watch installation is the current route; public App Store installation is described conditionally for launch, with official instructions. Check pairing/install/reachability without pretending Health permission or physical connection was established by simulation.
- Today prioritizes next action, real weekly rhythm and recent work. Insights prioritizes trends and available physiology, while session reports disclose data provenance/coverage. Replace hardcoded six-set/strength promises with actual session choices. Keep library, path, local coach and export accessible.

## Stable interfaces

Watch worker owns additive types in Shared/Core/Telemetry.swift:
- WatchMotionWindow Codable/Equatable/Sendable with recordingID UUID, start/end Date, sampleCount Int, rmsAccelerationG/peakAccelerationG/meanRotationRadiansPerSecond/peakRotationRadiansPerSecond Double.
- WatchTelemetry.motionWindow: WatchMotionWindow? default nil; all old fields remain.
- CompanionLink.onTelemetryBatch: (([WatchTelemetry]) -> Void)? and telemetryBatch(_ samples:[WatchTelemetry]); same JSON batch key telemetryBatch. Bounded batches up to30 samples; receiver max60 samples. Live telemetry behavior remains.

Root owns Shared/Core/WorkoutAnalytics.swift:
- HeartRateZoneConfiguration(maximumHeartRate:Double, isEstimated:Bool=false) throws; static estimated(age:Int) -> optional configuration, validated adult18...100; five zones split50/60/70/80/90/100percent maximum, outside-band time separate.
- WorkoutAnalytics(record:SessionRecord,zones:HeartRateZoneConfiguration?=nil), exposes heart:HeartRateAnalysis, motion:MotionAnalysis, pace:RepPaceAnalysis, activeSeconds/restSeconds/workRestRatio, activeKilocalories. Public analysis structs expose summaries, coverage and sample arrays. Concrete signatures will be announced before UI consumption.
- SessionRecord.endedAt:Date? default nil; timestamps are optional for old history. TrainingStore owns validated late batch merge and saving, separate from live receiveTelemetry.

Health/onboarding worker owns Shared/Core/HealthSnapshot.swift, Native/iOS/HealthDataStore.swift and WatchSetupView.swift; agent announces exact snapshot API before page integration. It may read/use root HeartRateZoneConfiguration but must not edit root analytics.

Page worker owns HomeViews/InsightsView/ReportViews and new dedicated analytics views plus optional TrainingDashboard core model/tests. Root owns native project/source registration and release; one coordinated existing iPhone only for final UI/build tests.

## Review focus

Bounded gap handling and duplicated readings; late delivery after finish/pause; matching session and recording IDs; cumulative-energy resets; no Apple Health retrospective/live conflation; no fabricated maxHR/zone/HRV/linear speed; missing/denied readings; finite values and time ranges; history-save failures and migration; no telemetry loss from clearing state before final flush.

## Builder-check decisions

An established Watch recording continues if the phone's snapshot becomes stale; commands still require a fresh reachable phone. Explicit received pause/end transitions still apply. Surface recording/disconnection state and allow a separate local stop. Flush the last window and batch before clearing values. Watch worker implements a persisted bounded outbox with stable batch IDs and WC transfer acknowledgement, retries on activation/reachability, max7200 pending samples and explicit overflow/error status. Do not silently claim all samples survive arbitrary crashes or storage exhaustion.

Root adds optional SessionRecord.endedAt and timeline:[WorkoutPhaseMark] (date,phase), default empty for legacy decoding. TrainingStore records actual phase changes using wall clock and decorates saves without changing set quantities. Delayed imports are allowed only for records with endedAt, dates between start-minus2seconds and end-plus2seconds, and matching sessionID; legacy saved records without a lifetime reject historical enrichment. Merge/dedup by sentAt; sensor/energy timestamps validated separately. Motion recordingID must match packet energy recordingID when both exist; no joining motion across runs.

HR segments require adjacent valid, distinct reading timestamps no more than12seconds apart. Never extrapolate, and discard segments spanning a paused/idle/finished phase mark. Time-weighted HR and five-zone durations use left-reading intervals; durations are estimates of observed coverage. Coverage denominator is recorded session wall time excluding known pauses when endedAt exists; otherwise explicitly labelled sample-span coverage. Values above configured max are recorded separately from zone5; values below50percent are separate too. No fabricated coverage with a single reading.

Motion RMS is sqrt(sum(windowRMS²*sampleCount)/sum(sampleCount)), with nonoverlapping, valid windows only. Window sample coverage and boundaries remain visible. Cumulative energy is summed once per distinct recording; decreases within the same recording are flagged, not treated as a fresh run or added twice. Rep pace uses only complete recorded camera rep timing; manual/video/partial timing is not a measured live rep-rate signal.

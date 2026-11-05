# Watch recorder, durable telemetry and controls

Run `bash Tests/WatchRecorder/run.sh` and `bash Tests/WatchRecorder/replay.sh` from the repository root on a Mac with Swift. Scratch, compiler module caches, runtime temporary files and copied shared sources live under `/Volumes/Spottr Development/watch-telemetry-tests` by default; `SPOTTR_WATCH_TEST_ROOT` can select another scratch root. Each runner removes only its own generated temporary directory. Copying shared sources prevents another worker's edits from changing a source file during compilation.

These runners compile the actual recorder/store/link and shared types against test-only SDK boundaries. They do not access Health data, pair a Watch, use a simulator, change the native project or validate physical device behavior.

## Recorder and store checks

The additive telemetry round trip retains motion windows and still decodes legacy packets with the window absent. Twelve recorder cases cover authorization, successful collection before recording, active/paused collection failure, pending cancellation, explicit retry, stale callbacks, cumulative energy, original units and timestamp mapping. New motion coverage verifies ten-hertz samples contribute to each bounded window and the final partial window flushes before pause or end. Resume retains the recording UUID; replacement recordings use another UUID. Queued callbacks cannot add measurements after stop.

Eight store cases cover command confirmation, generation changes, recording startup, explicit phone pause, ordering/corrections, final flushing and disconnection. An explicit phone pause during startup still applies after collection completes. An established Watch recording continues when the phone snapshot becomes stale; stale snapshots cannot authorize commands or apply phase changes. A separate local stop flushes values with their original session ID before clearing transient values and does not send an iPhone finish command. Phone pause/end and a new accepted session still apply their explicit transitions. Paused collection emits its final flush and then stops publishing cached telemetry.

Motion windows expose sample count, first/last sample dates, acceleration RMS/peak in g and angular-speed mean/peak in radians per second. Windows are bounded by one second or ten samples, with gaps above 0.3 seconds starting another window. Duplicate/backward sample times do not get counted twice. Invalid samples break the window. A final single-sample window has equal start/end and supplies no duration coverage. No linear speed, repetitions, force, HRV or physiological readiness is inferred from wrist motion.

## Durable delivery checks

The replay uses real CompanionLink serialization, receiving, session ownership, local history/export and report code. Existing context/live behavior remains covered. A 35-sample backlog creates batches of 30 and 5 even while unreachable. WC transfer completion alone leaves samples queued. Stable batch IDs survive retries and file reload. Only an application `telemetryAck` removes the matching sealed batch. Root's phone consumer acknowledges after durable inbox/history persistence; a retryable phone save failure sends no ACK. A permanent foreign/deleted/invalid-lifetime rejection sends `accepted:false` and surfaces a rejection notice.

The outbox stores at most 7,200 samples, with explicit cumulative local-queue eviction counts. Sealed batches remain immutable. Atomic persistence errors preserve previous durable contents. Full batches are queued normally; partial batches flush on finalization or activation/reachability. At most four telemetry batch transfers are outstanding. Completed but unacknowledged batches wait at least 30 seconds before ordinary retry; activation/reachability can request another attempt. Malformed data, payloads over 256 KiB and batches over 60 samples do not enter application batch handling.

The public compatible batch callback is `onTelemetryBatch`; `onDurableTelemetryBatch` additionally supplies a stable UUID. The compatible callback does not imply persistence and is not automatically acknowledged. ACKs use queued WC user info, so failed ACK delivery is repaired when the Watch retries the same data and the phone acknowledges its already-durable copy.

## Limits and acceptance

A window still being accumulated can be lost if the Watch process terminates before flushing. Storage exhaustion or a corrupt queue blocks new durable writes and shows an error; data that could not be written may be missing. Overflow explicitly removes oldest local queue entries, and the 7,200-packet limit is approximately two hours at one packet per second; final/health-only packets can shorten that span. Queue writes and sensor/background delivery have not been profiled on hardware.

Watch measurements made after an offline phone session's recorded lifetime can be rejected by the phone's bounded import rules. Permanent rejections deliberately remove those packets from the Watch queue. The queue is not a HealthKit workout backup. Native builds, pairing, actual radio/background delivery, storage pressure, authorization sheets, battery cost, sensor accuracy, Crown/navigation, small/Ultra layouts and large type remain separate device acceptance checks.

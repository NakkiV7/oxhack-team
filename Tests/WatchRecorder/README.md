# Watch recorder and control behavior

Run `bash Tests/WatchRecorder/run.sh` from the repository root on a Mac with Swift.
The script compiles the actual recorder/store and shared types against small
test-only HealthKit, CoreMotion, WatchKit and companion-link boundaries in a temporary directory.
It never imports Apple's HealthKit implementation, accesses health data, uses a
physical device, or changes the Xcode project. Temporary outputs are removed.

Ten recorder cases exercise authorization/start/collection/save states,
active/paused collection failure, cancellation during authorization/startup,
workout-write denial and explicit retry, queued motion rejection and old-builder
callback isolation. Recording and motion begin only after collection succeeds;
stopping startup discards its unfinished HealthKit workout. Read denial cannot be
inferred from a missing heart-rate or energy sample. Energy checks use independent
energy-only/combined callbacks, cumulative `sumQuantity` in kilocalories and the
actual statistics `endDate`. They reject missing totals, invalid values/dates,
future/pre-run observations, pending/paused collection and old builders. Repeated
totals are not added; pause/resume retains the recording UUID, a new builder uses
a new UUID, and a lower genuine revision is retained.

Five store cases verify that End session requires an explicit, current-generation
confirmation, Cancel sends nothing, stale confirmation cannot end a replacement
context, and pending/paused recording sends no telemetry. An injected clock also
checks that an expired retained snapshot pauses the recorder, replaying that same
timestamp cannot resume recording or restart motion, and an equal timestamp with
a changed phase has no side effects. A newer fresh active snapshot can resume.
The default clock remains the current date; no waiting or wall-clock changes are
needed by these checks. Energy-only telemetry retains its original cumulative
value/date without inventing HR or adding repeated ticks. Pausing blocks sending;
changing the phone session or explicitly starting a new recording clears cached
energy. An older same-run callback cannot replace a newer as-of observation before
the next tick; equal/newer-as-of corrections may lower the value. The optional
energy field is local history/report data; the core v1 cloud
projection omits it and Coach facts remain unchanged. Those separate core contract
tests are not executed by this runner.

The Watch uses a black system tab container with separate metrics and controls,
native vertical paging and fresh heart rate in red. Manual missing reps remain
an em dash, with the compact `Manual · iPhone` instruction. Root's native build
and simulator inspection must separately check small/Ultra layouts, large type,
vertical swipe navigation, disconnected controls and end confirmation. Physical
Digital Crown, sensor availability, permission sheets and saving remain device
acceptance checks; this SDK-double runner cannot establish them.
These controlled boundary tests do not establish real Watch/HealthKit behavior;
native compilation and physical callback acceptance remain separate checks.

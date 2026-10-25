# Watch recorder and control behavior

Run `bash Tests/WatchRecorder/run.sh` from the repository root on a Mac with Swift.
The script compiles the actual recorder/store and shared types against small
test-only HealthKit, CoreMotion, WatchKit and companion-link boundaries in a temporary directory.
It never imports Apple's HealthKit implementation, accesses health data, uses a
physical device, or changes the Xcode project. Temporary outputs are removed.

Seven recorder cases exercise authorization/start/collection/save states,
active/paused collection failure, cancellation during authorization/startup,
workout-write denial and explicit retry, queued motion rejection and old-builder
callback isolation. Recording and motion begin only after collection succeeds;
stopping startup discards its unfinished HealthKit workout. Read denial cannot be
inferred from a missing heart-rate sample.

Three store cases verify that End session requires an explicit, current-generation
confirmation, Cancel sends nothing, stale confirmation cannot end a replacement
context, and pending/paused recording sends no telemetry. An injected clock also
checks that an expired retained snapshot pauses the recorder, replaying that same
timestamp cannot resume recording or restart motion, and an equal timestamp with
a changed phase has no side effects. A newer fresh active snapshot can resume.
The default clock remains the current date; no waiting or wall-clock changes are
needed by these checks. The recorder/store
interfaces remain local; no telemetry fields or persisted-history schema changed.

The Watch uses a black system tab container with separate metrics and controls,
native vertical paging and fresh heart rate in red. Manual missing reps remain
an em dash, with the compact `Manual · iPhone` instruction. Root's native build
and simulator inspection must separately check small/Ultra layouts, large type,
vertical swipe navigation, disconnected controls and end confirmation. Physical
Digital Crown, sensor availability, permission sheets and saving remain device
acceptance checks; this SDK-double runner cannot establish them.
These controlled boundary tests do not establish real Watch/HealthKit behavior;
native compilation and physical callback acceptance remain separate checks.

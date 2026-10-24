# Watch recorder callback regression

Run `bash Tests/WatchRecorder/run.sh` from the repository root on a Mac with Swift.
The script compiles the actual recorder and its shared lifecycle/reading types
against small test-only HealthKit and CoreMotion modules in a temporary directory.
It never imports Apple's HealthKit implementation, accesses health data, uses a
physical device, or changes the Xcode project. Temporary outputs are removed.

The cases exercise successful collection, active/paused collection failure,
resource shutdown without saving, retry, queued motion rejection and old-builder
callback isolation. The failure regression catches the previous behavior where a
false `beginCollection` result retained the session and motion and blocked retry.
These controlled boundary tests do not establish real Watch/HealthKit behavior;
native compilation and physical callback acceptance remain separate checks.

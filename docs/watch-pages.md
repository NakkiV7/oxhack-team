# Watch workout pages

The Watch uses native black vertical pages: **Metrics** opens first; **Controls** keeps pause/resume, end-set and recording actions separate. Swipe between pages or use the Digital Crown. Scroll within longer pages and system confirmations. Finishing returns to Metrics. The black system canvas removes the previous white rectangular control strip; physical Ultra layout acceptance remains pending.

Fresh actual heart rate is red; missing or stale heart rate remains a grey dash. Manual quantities use a dash until the phone supplies an entered count. Recording status distinguishes requesting access, starting collection, recording, pause, save and failure. The app never reports recording before collection succeeds. Cancelled startup discards its builder; stale authorization/save callbacks cannot restart or save a newer run.

End session asks for confirmation tied to the current session and generation. Cancel sends no command. Incoming snapshots must be fresh and strictly newer before they can change recorder state. This prevents a replayed retained snapshot from restarting stale capture.

## Verification

- Actual recorder SDK-double harness: seven recorder and three WatchStore cases passed. RED reproduced cancelled authorization overwriting stopped state, startup stop saving unfinished work, and stale/equal-time packet replay resuming capture before their fixes.
- Native Watch build/run passed without warnings on the existing paired TinyTaps-Watch simulator at 02:56 UTC, including the replay guard and final-page transition. Log: `build_run_sim_2026-10-25T02-56-27-592Z_pid4129_15ecbff3.log`.
- Actual CUA interaction verified the black manual Metrics page (missing count/HR dashes), swipe to separate Controls, scrolling the native confirmation, Cancel retaining the active session, and confirmed Finish reaching the phone. Blank manual work saved zero completed sets, with no invented reps or sensor values.
- Physical Crown, Ultra fit, Health permissions, sustained sensors and audible voice remain device checks. No additional sensor fields or HealthKit permissions are introduced here.

[Finished Metrics page](evidence/watch-paged-finished-2026-10-25.jpg). The simulator screenshot is software layout evidence, not a physical Ultra photo.

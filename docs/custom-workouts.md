# Run a saved workout

In Coach, select the exercises you want, approve them, then choose **Start saved workout**. Keep any required household support selected. The existing **Log** action remains available after training. The fixed camera session remains separate; custom execution currently uses manual reps and active hold timers.

- The queue preserves selected catalogue IDs, order, set counts, targets, units and rest targets.
- Press Start when in position. Targets never create completed work. Enter actual reps; hold time comes from explicit start/pause/end actions.
- End each completed set to start rest. Preparation before the next Start still counts as rest, not active time.
- Pause excludes time from the active clock. A background/inactive interruption pauses a configured workout.
- Pain/discomfort stops continuation for the workout. Already entered/observed completed work can retain that reason; missing quantities are never invented.
- Finish saves completed sets once using a stable session UUID. Unended work is not silently converted into a completed set.
- Watch displays catalogue names, correct units and generic queue position. It can start/pause/resume/end/finish within permitted phases; a Watch command cannot invent a manual rep count.

Reports preserve source, optional target/number, measured active/rest time, self-report versus active timer, and actual long holds. Legacy logs without metadata still decode. Tiger accepts the same optional fields with strict unit/origin/timing bounds. The new fields remain server-validated; a submitted client record does not establish physical accuracy.

## Verification

An isolated staged snapshot excluded concurrent profile, Pi, artwork and skill-tree work. Its shared suite passed 37 XCTest + 68 Swift Testing tests; gateway suite passed 36 tests. Native `ConfiguredWorkoutFlowTests` passed 1/1 on existing Musalli-Test (result `test_sim_2026-10-24T19-12-49-381Z_pid4129_8e5b90a2.xcresult`, 44.5 s, no warnings). The final additional shared guard rejects malformed Watch duration values before Int rendering; its decoded-wire regression was observed red, then green, and the staged shared suite was rerun.

Independent review approved tree `0cebfa2aaacc054006b1b756fdc4de2c0da5a4d1` and the subsequent two-file Watch clock hardening. No paid calls or physical exercise accuracy checks were needed. Physical Watch acceptance and camera execution inside configurable queues remain open in #7 and #19.

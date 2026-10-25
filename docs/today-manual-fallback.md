# Today camera-to-manual fallback

Today’s legacy squat/push-up session now offers **Use manual reps** when phone or Pi tracking is unavailable, or when the user chooses to stop tracking. This is separate from saved/custom-plan execution.

Opening the confirmation pauses capture and speech. **Cancel** leaves the session paused with its observed count intact. **Reset and use manual reps** starts a fresh manual set: it discards only the current unfinished count and active time, clears pose/preview and capture ownership, changes the generation, and keeps the session identity, ended sets and their recorded rest intact.

The user enters **1–200 reps actually completed**. The field starts blank; neither camera observations nor the target become a self-report. Empty, nonnumeric or out-of-range drafts clear the quantity, and the phone disables End set while its current text is invalid. Direct phone/Watch End or Finish cannot save the previous valid value after the draft is cleared. Reaching a target never ends the set automatically. Blank manual work is omitted if the session is finished. Recorded manual sets have `source: manual` and no observed rep-duration series; the phone marks them **Manual self-report**.

Phone/Pi callbacks are rejected after a generation change, and manual input rejects pose samples even with the current generation. The fallback cancels existing coaching/speech; it does not produce camera-derived personal coaching in manual mode. Existing reported-discomfort behavior remains available. Phone permission denial/unavailability now pauses the legacy set rather than leaving it running without tracking.

## Verification and limits

Root verified the final software checks on 25 October 2026:

- Full shared suite: **59 XCTest + 101 Swift Testing checks passed**, recorded in ignored `.local/app-gaps-final-core-green.log`. Coverage includes manual quantity/reset/save behavior, Watch commands and backward-compatible source metadata.
- Focused native suite: **37/37 passed**, including Pi/phone lifecycle, voice cancellation and clearing a quantity before Watch Finish. Log: `test_sim_2026-10-25T01-58-05-394Z_pid4129_253efbf1.log`; no warnings reported in this run.
- Watch simulator build/run: **passed** and launched the existing TinyTaps-Watch simulator. Log: `build_run_sim_2026-10-25T02-23-06-149Z_pid4129_e1fc74b7.log`; no warnings reported in this run.

The invalid-draft regression first reproduced stale quantity saves through End/Finish; the final optional setter and every-change UI mapping clear such drafts. Actual CUA acceptance on the existing Musalli-Test simulator covered confirmation → Cancel → paused count retained → confirmed reset → blank manual entry → two reps → clearing the field disables End set → two reps restored → End → Finish. The isolated saved history contains exactly one legacy squat set with two reps, target 12 and source manual; telemetry is empty. The earlier isolated catalogue Wall push-up record remains intact. The Watch simulator showed a missing-count dash and compact “Manual · iPhone” instruction without clipping. The two focused compact-instruction checks also passed. These are synthetic inputs, not exercise observations. [Saved phone screen](evidence/manual-fallback-saved-2026-10-25.jpg) and [Watch screen](evidence/manual-fallback-watch-2026-10-25.jpg). These software checks do not establish real phone/Pi capture, physical Watch behavior or audible voice acceptance.

A review found that idle camera-positioning copy was still visible above manual entry; the actual cleared-field screenshot reproduced this presentation error. The hint is now limited to non-manual input.

The Watch receives the explicitly entered count and source-aware manual instructions during active, paused and rest phases. Optional legacy source metadata preserves decoding of earlier snapshots; the phone remains the manual-entry surface. This change does not alter configured plans, catalogue launch behavior, saved camera counts or previous history records.

# Start a workout

From **Skills** (Grid or Linear) or the exercise library, open an exercise and choose **Start workout**. Set its number of sets, rep/hold target and suggested rest; confirm household support when shown. This local setup opens the existing Manual preparation screen without Gemini, and does not save or replace your approved Coach plan. It is available even while a skill challenge's prerequisites are pending. **Log manually** remains the separate option for work you already completed.

In Coach, approve selected exercises, then choose **Start saved workout**. Keep required household support selected. The queue preserves catalogue IDs, exercise order, set counts, targets, units and rest targets. The existing **Log** action and fixed camera workout remain available.

Every set starts in Manual. Only base **Push-up** (`pushup`) and **Squat** (`squat`) offer **Manual reps**, **iPhone camera** and **Pi side camera**. Other exercises use manual reps or active hold timers. Choosing a camera does not start capture; choose Start when in position. Pair the Pi through the input menu before starting it.

- Manual reps are self-reported. Enter the actual count; targets are never filled in for you.
- Camera sets reuse the existing pose geometry and full-cycle rep counter. The screen shows observed reps, preview, form cues and an optional Voice feedback toggle. Targets never end sets automatically. Zero observed reps does not establish that no exercise happened.
- Hold time comes from explicit Start/Pause/End actions. Preparation is excluded from active time; preparation before the next set remains part of recorded rest.
- Changing input after Start requires **Reset and switch**, which discards only that unfinished set's count and active time. Ended sets and their order remain. The new input needs Start again. Cancel preserves the unfinished work.
- Pause, app inactivity or camera failure stops capture and invalidates old callbacks. Resume is explicit. Camera failure also permits a confirmed switch to Manual; it never supplies a fabricated count.
- End starts rest. Choose the next set explicitly, then Start it separately. Pain/discomfort prevents continuing the plan; missing quantities are never invented.
- Finish saves ended sets once with a stable session UUID. Unended work is dropped. The saved review distinguishes camera observations, self-reports and active hold timers.

Watch displays the catalogue name, correct unit, camera-observed or manually entered count, and brief source-specific instructions. It can start the input selected on iPhone, pause/resume/end and finish within permitted phases. It cannot select camera mode or invent counts. Voice remains an explicit iPhone opt-in and resets off for a new plan.

## Records, reports and privacy

Mixed camera/manual/hold sets stay in queue order in `loggedSets`. Camera rows use existing camera provenance and optional completed-cycle `repDurations`; no timing is inferred from manual counts, total set time or replay. Reports and Coach facts use validated timing. Personal rhythm history excludes manual/replay, discomfort/form stops and invalid timing. No new provider request or automatic sync is introduced.

Tiger accepts absent/null timing for old records. Non-null timing requires a base camera rep exercise, zero hold seconds, no manual quantity origin, exact count matching, at most 200 durations, and finite 0.6–15-second values. Local observations are retained if a sync bound is exceeded; the app does not clamp counts or stop at 200. These constraints do not establish physical accuracy.

## Verification and remaining acceptance

Synthetic Core tests cover both supported exercises, no automatic target completion, continuity/generation guards, confirmed source reset, mixed record order/rest, report timing, camera-only rhythm history and source-aware Watch snapshots. The full shared suite passed **59 XCTest + 90 Swift Testing tests** (`/tmp/spottr-configured-final-core-green.log`). Backend contracts passed **38 tests**, including mixed-order round-trip and invalid timing/source rejection.

Focused native checks passed **23 tests** for configured routing, legacy coaching, Pi transitions and fake voice playback (`20-49-51…d319d749`, no warnings). Two fixture tests plus six existing Coach tests passed after a missing-API RED. The isolated UI flow first failed at missing Start saved workout, then at missing input menu after the DEBUG fixture loader passed. Final `testConfiguredCameraChoiceNeedsResetConfirmationAndOtherExercisesRemainManual` passed on the existing simulator: Cancel preserved 3 reps; confirmed reset returned to zero/preparation with voice off; manual fallback saved 2 reps; the following plank had no camera input; Finish/Save/Done completed. The actual Xcode log `test_sim_2026-10-24T21-05-51-283Z_pid4129_9ac2e473.log` ended `TEST EXECUTE SUCCEEDED` (393.76 s test execution, 397.889 s total), despite the tool's earlier 300-second timeout.

The UI fixture is DEBUG-only, requires a valid UUID `SPOTTR_DATA_NAMESPACE`, typed-decodes `SPOTTR_APPROVED_PLAN_FIXTURE`, and never persists or modifies the saved plan. Invalid fixtures use the existing stored-plan path; Release excludes fixture handling. UI tests finish using manual fallback without opening a camera or calling Gemini.

Sustained phone/Pi exercise counting, physical Watch rendering and audible coaching remain separate device acceptance checks. The known Pi USB disconnect remains open; this feature does not fix it.

Final reviewed snapshot: **35 focused native tests** passed without warnings, covering configured input, Coach, legacy cues, Pi lifecycle, voice cancellation and built-bundle packaging (`21-14-14…45245804`, `21-14-47…648717a7`). The same snapshot’s Watch simulator build passed without warnings (`build_sim_2026-10-24T21-13-47-813Z_pid4129_6e332d89.log`). The complete gateway suite, including the separate Snowflake additions, passed 50 tests.

## Catalogue launch check — 25 October 2026

The new factory first failed at the missing API, then all nine configured native cases passed within the 37-check app run (`test_sim_2026-10-25T01-58-05-394Z_pid4129_253efbf1.log`). All 19 catalogue entries retain canonical units and existing camera eligibility; bounds, support, actual quantities and active hold time are covered.

Actual CUA checks on the existing Musalli-Test accepted Grid → Wall push-ups → setup → support confirmation → explicit Start/End → save, retaining one synthetic manual set of 2 reps against its target of 8. Today → exercise-library sheet → base Push-ups → setup also opened preparation successfully, showing manual, iPhone and Pi choices without starting capture. A first screen check exposed Start beneath the tab bar; the persistent bottom action and numeric Done control corrected that layout. These checks used an isolated namespace, not a physical workout or TestFlight build. [Receipt](evidence/catalogue-start-2026-10-25.md).

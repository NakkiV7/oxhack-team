# Profile, skills and lesson polish

Accepted on 25 October 2026, with the UI receipt recorded at 03:15:33 UTC. Checks used the existing Musalli-Test iPhone simulator and an isolated synthetic data namespace. The installed phone build was reported successful at 02:58:52 UTC; this acceptance pass did not rebuild or relaunch it.

## Observed behavior

- **Profile autosave:** entering “Synthetic Guest” and changing the weekly target saved without pressing Save. Removing the only selected goal displayed “Choose at least one training goal.” Closing and reopening restored the last valid name, Strength goal and target of four days.
- **Optional starting point:** restarting the introduction preserved the profile. “Skip for now” was initially selected; choosing “Some practice” and completing onboarding produced corresponding local practice ideas. A later target change to five days autosaved and retained that baseline. The answer is self-report, not completion evidence.
- **Skills access:** preview started off, with 0 of 19 earned and zero XP in all four attributes. Enabling it displayed “Preview access · no achievements earned” without changing those totals. Expanding and panning reached later preview nodes and green connections; an opened node still showed zero manual and camera sets.
- **Keyboard and actions:** with the software keyboard visibly open, tapping the noninteractive profile note dismissed it. Refocusing opened it again, and dragging the form downward dismissed it. Restart, export, delete and reset actions displayed icons.
- **Lesson requirements:** the disclosure started collapsed. Expanding it showed MOV, MP4 or M4V; up to two minutes; 100 MB per video; 500 MB total; and private storage with nothing uploaded.

## Verification boundaries

Four new shared-core behavior tests passed after the expected missing-API RED: legacy profile decoding, optional baseline round-trip and unknown-answer rejection, preview without earned progress, and baseline suggestions without logged sets. Authored UI test methods were not executed by this acceptance lane; the observations above came from actual CUA interaction.

The **explicit Save profile button**, **file selection/import/replacement/cancellation feedback**, and **temporal Reduce Motion behavior** were not exercised. The animation's Reduce Motion guard was inspected in source, without toggling the setting or measuring pulse timing. No camera, microphone, audio, provider request, physical-device exercise or accuracy test was performed. Existing synthetic records were retained; this pass logged no workouts.

Capture Keyboard was restored off, software-keyboard display was restored to its original hidden state, and the temporary browser mirror tab was closed. Existing service tabs and simulator settings were preserved. The app was left on Today in the same isolated namespace; UI ownership returned to the root agent.

## Unchanged simulator captures

These three synthetic iPhone simulator captures were copied without editing. They document the visible states, not physical-device acceptance.

- [Preview access with zero earned progress and XP](evidence/skills-preview-zero-earned-2026-10-25.jpg)
- [Optional self-reported starting point](evidence/onboarding-self-report-baseline-2026-10-25.jpg)
- [Expanded lesson video requirements](evidence/lesson-video-requirements-2026-10-25.jpg)

## Save-failure review correction

Independent review found that Done/restart could hide a failed disk write. The native draft now retains valid unsaved changes, retries on Done/restart and prevents swipe dismissal until they save. Invalid goals can still close to the last saved profile; unreadable profile data requires explicit Save before replacement.

Root captured the expected missing-API RED at 03:27:13 UTC, then **four ProfileDataControlsTests passed** at 03:35:14, including real atomic-write failure caused by an isolated blocked destination, retry after an earlier debounce failure, baseline preservation and corrupt/invalid-profile policy. Eleven configured-session behavior tests also passed in that run; no warnings. Receipt: `test_sim_2026-10-25T03-35-14-533Z_pid4129_e5fe004d.log`. These are native behavior tests, not a forced storage-failure UI acceptance. The earlier independent staged shared baseline passed 59 XCTest and 105 Swift Testing cases, excluding unrelated dirty weekly/report/skip work and preceding this native-only correction.

# Catalogue workout launch — 25 October 2026

**Accepted synthetic native UI and persistence flow; physical exercise remains unverified.** The signed Debug 0.1 (1) app ran on the existing Musalli-Test iOS 26.5 simulator. This source is newer than TestFlight build 4. No provider request, camera capture, physical device or audible coaching was used.

## Exercised behavior

- Grid → Push-ups I / Wall push-ups → Start workout opened local setup. Start was disabled until Wall support was confirmed.
- The first setup screen put Start under the tab bar. After a recorded visual failure, a persistent bottom action kept it visible; the revised app build/run passed at 02:04:34 UTC (`build_run_sim_2026-10-25T02-04-34-096Z_pid4129_604cf6a5.log`).
- Start opened Manual preparation with a blank quantity. A separate Start set began active time. Two synthetic reps were entered, explicitly ended, then Finish saved only that ended set.
- Saved JSON contained `exerciseID: wallPushup`, `target: 8`, `reps: 2`, `source: manual`, `quantityOrigin: selfReport`, `activeSeconds: 51.46384079166455`, with no Watch telemetry. Targets did not supply completed work. This time records UI interaction, not real exercise.
- Today → Exercise library → base Push-ups → setup → Start workout also opened preparation from the sheet. Its input menu offered Manual reps, iPhone camera, Pi side camera and pairing; opening the menu did not start capture. The unfinished preparation was discarded by stopping the test app.

The isolated UUID namespace preserves normal profile/history. Catalogue setup never writes or replaces the approved Coach plan. Linear navigation uses the same detail/start implementation but was not independently repeated in this check.

## Software checks and scope

The missing factory/API RED was captured before implementation. All nine `ConfiguredWorkoutFlowTests` passed within the 37-case native run at 01:58:05 UTC, without reported warnings. The full shared suite passed 59 XCTest plus 101 Swift Testing checks. Cases cover every catalogue unit/camera restriction, unknown IDs, bounds/support, actual manual counts and active hold duration. The final setup layout additionally compiled in the later build above.

Camera accuracy, physical networking, real Watch capture and real-user training quality remain separate gates. These screenshots precede the later semantic-colour pass.

[Manual preparation](catalogue-wall-preparation-2026-10-25.jpg) · [Saved actual work](catalogue-wall-saved-2026-10-25.jpg).

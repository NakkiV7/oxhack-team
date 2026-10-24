# Using Spottr

Start with your goals and the number of days you want to train each week. A name is optional. This is a local profile; no cloud account is created.

- **Today:** start the camera workout or open the full exercise library. Manual logging and hold timers work without provider credentials.
- **Skills:** switch between the connected grid and linear list. Open any exercise to see its instructions, prerequisites, source-aware progress and logging controls. Locked challenges remain available to practise.
- **Progress:** open a completed session for actual sets, timings, rest, source badges and any recorded Watch signals. Missing sensor readings remain missing. Gemini summaries require a configured gateway and an explicit tap.
- **Coach:** request a catalogue-based proposal, select exercises and approve the plan. Start the saved workout, or log work afterward. Proposed targets never count as completed reps.
- **Profile & settings:** edit goals, restart the introduction, prepare a history export, or confirm local history/profile deletion separately. Deleting history also removes prepared app-owned export copies; it cannot delete files you already saved or shared elsewhere.

## Record your exercise lessons

Open **Profile & settings → Film your exercises** for the complete 19-exercise checklist. Each guide describes the camera angle, framing, start/middle/end positions, take length and whether to record both sides. You can mark an exercise filmed before importing its video.

Add a local MOV, MP4 or M4V recording to see it beside the exercise graphic. Each file must be playable, at most two minutes and 100 MB; the private library is limited to 500 MB. Imports preserve original bytes and aspect ratio. Replacing or removing a private copy requires confirmation. Lesson videos and filming checkboxes do not create workout records or earn XP.

The app does not yet crop people or remove video backgrounds. Those edits can be made after Omar supplies the recordings; transparent-source playback is supported by the player surface. A damaged lesson index pauses changes and preserves the original private files for recovery.

For development, use a valid UUID `SPOTTR_DATA_NAMESPACE` to isolate test data and `SPOTTR_FORCE_ONBOARDING=1` to exercise first-run setup. Never reset normal simulator history as a testing shortcut.

# Rep counter voice

Arnold or Goggins counts every camera-counted rep out loud and adds a motivational line every third clean rep, like the
web squat coach. It uses audio bundled in the app, so it works offline and costs nothing per rep.

## Behaviour

- **When it speaks.** Only while the workout's existing **Voice feedback** switch is on (still off by default), for camera
  reps. Video and manual sets stay silent.
- **What it says.** A start line when a camera set begins, the rep number on every counted rep (1 to 30), a rotating
  motivational line on every third clean rep, and a closing line when the set ends.
- **Queueing.** One line at a time, never cut off by another rep line. A newer count replaces one still waiting, so an old
  number is never said; counts wait at most 1.5 s, other lines a few seconds.
- **Safety.** Stop, form and pacing cues take over (`RepVoicePlayer.yield()`). Pause, stop, background, voice off and a pain
  or discomfort stop cancel it. "Pain is just information. Keep going." from the web coach is not included.
- **Choosing a voice.** Coach voice sheet → **Rep counter**: Off, Arnold or Goggins (default Arnold). It does not need the
  gateway or "Check configured voices". While it is on, the preview's "every two reps" clip and the live "Keep a steady
  rhythm." encouragement are suppressed so lines never double up.

## Code

- `Shared/Core/VoiceCuePlayback.swift`: `RepVoicePlan`, the queue rules (tests in `Tests/Core/RepVoicePlanTests.swift`).
- `Native/iOS/DemoVoicePlayback.swift`: `RepVoicePlayer`, bundled clip playback with an injectable output for tests.
- `Native/iOS/TrainingStore.swift`: `repVoiceTick` after each coaching tick, plus `yield()` when a cue speaks.
- `Native/iOS/VoiceCoachSettingsView.swift`: the Rep counter picker.
- `Tests/iOS/PreviewRepCueTests.swift`: `RepCounterVoiceTests`, and the existing preview tests run with the counter off.

No new source files, so the Xcode project file is unchanged; the clips sit in the `Native/Resources/DemoVoice` folder
reference.

## Audio

`Native/Resources/DemoVoice/arnold-reps` and `goggins-reps`: 41 clips each (counts 1–30, seven motivational lines, three
closing lines, one start line), ElevenLabs `eleven_turbo_v2_5`, `mp3_22050_32`, all under 3.4 s. They were synthesised for
the squat web prototype and reused from its cache, with no new synthesis; each folder's `manifest.json` records the text,
size and SHA-256 of every clip.

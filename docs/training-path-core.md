# Training path: Core logic

Swift port of the personalised training path and the camera coaching loop from the browser prototype
(`prototype/squat/coach.mjs` and `coach-loop.mjs` on `nakki-squat-model`). Pure `SpottrCore` code with tests and no
screens: the Skills tab, the Gemini endpoints and the camera hook-up come in later PRs.

## What is here

| File | Contents |
| --- | --- |
| `Shared/Core/TrainingPathSurvey.swift` | `PathSurvey` answers (goal, starting point, equipment, minutes, sessions per week, focus, coaching style, movements to leave out), ability statements per goal and their placement bands, equipment choices. |
| `Shared/Core/TrainingPath.swift` | `TrainingPath` graph, `PathCapability` per exercise, `PracticeTarget` bounds, and `TrainingPathRules`: placement, validation of any generated path, route, and the catalogue fallback. |
| `Shared/Core/PathProgress.swift` | `PathStatus` (step states from the person's history), `PathDiff` (what a new version changes), `PathHistory` (saved versions), `PathLevel` (game level) and `MeasuredAttributes` (Tempo, Consistency, Practice). |
| `Shared/Core/CoachAttempt.swift` | `TempoContract` (squats: lowering time 1.5 s ± 0.15 s), `AttemptComparison`, the deterministic `AttemptCue`, the `CoachAttemptLoop` state machine and `NodeVerification`. |
| `Shared/Core/RepCounter.swift` | Adds `lastRepPhases` (lowering, rising, deepest angle). Counting is unchanged. |

## Rules that stay as they are

- **Earned rule.** A step is earned with three sets at the catalogue goal across two training days, manual or camera, as in `SkillProgress`. Path progress is read from the same history, so a new path version never loses or invents progress.
- **Path gating.** Availability follows the path's own links. A person placed at squats has glute bridges marked "not required for your start", which counts as passed for unlocking but is never shown as earned. The full catalogue tree in `SkillProgress` is untouched.
- **Camera verification is a mark, not a gate.** A qualifying squat assessment shows "AI-verified"; two qualifying days show it as consistent. It never unlocks a step by itself.

## Differences from the web prototype

- Practice completion uses the earned rule above instead of "practice logged on three days".
- Equipment uses the catalogue's own support names, the same ones the Coach tab and workout setup use. "Optional nearby support" is never required.
- The survey starts from the onboarding baseline (`startingOut` → beginner, `somePractice` → intermediate, `regularPractice` → advanced) until the starting-point question is answered. Sessions per week start from the weekly target, capped at six.
- The level adds the existing attribute XP (10 per goal set, three a day per exercise) to verification bonuses: 50 for a first verified completion, 100 more for consistency.
- The range check that rejects a shallower retry uses knee flexion (180° minus the deepest knee angle), because the native counter measures angles, not hip travel.
- Lowering time runs from the first sample below the top zone (160°) to the deepest angle. The 1.5 s target was set on the web counter's hip-travel timing, so it needs a check on a phone before results are trusted.
- Push-ups stay camera counting only: no contract, no verification.

## Integration points for the next PRs

- **Project file.** The new files are in `SpottrCore`, so `swift test` covers them. The app target lists files explicitly, so they need `ruby scripts/generate-project.rb` before app code uses them. That is the primary chat's step.
- **Gemini.** A generated path must pass `TrainingPathRules.validate`, use a start from `placement(...).allowedStarts`, and fall back to `TrainingPathRules.fallback` after one repair attempt. `PathHistory.save` validates again.
- **Camera.** The squat session feeds `LoopRep(counter:)` into `CoachAttemptLoop` after each counted rep, calls `pause`, `resume` or `cameraChanged` on interruptions, and saves `record`.
- **Storage.** `PathHistory`, `PathSurvey` and `CoachAttemptRecord` are `Codable`; where they live on the device is for the primary chat to decide.

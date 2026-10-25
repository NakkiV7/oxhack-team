# Optional steady-rhythm encouragement

`CoachingInput.encouragementEnabled` defaults to `false`, preserving existing callers. An enabled policy may emit the exact positive pacing cue **“Keep a steady rhythm.”** with reason `.steadyRhythm`. This recognizes recorded timing only; it does not predict capacity, validate form or infer medical readiness.

The cue requires a newly observed, consecutive, completed camera rep, an active phase, `.controlled` camera feedback, no stop reason, a positive target and a count strictly below that target. Five prior valid same-exercise camera durations are required. Duration must be finite and 0.6–15 seconds, within prior mean ± max(sample SD, 0.25 seconds), and pass the existing 10-second ordinary-cue cooldown. Statistics exclude the current rep, retain at most 60 samples per exercise, and reuse eligible deduplicated saved camera history. Live tracking/alignment/non-controlled/stop observations cannot populate the encouragement baseline. Existing stop, tracking/alignment, target, slowdown and rest behavior retains priority. Heart rate and optional body measurements never enable this cue or imply clearance.

Manual/video observations, non-active observations, duplicate counts, count jumps, backwards timestamps, retired sessions/generations and the first snapshot after pause cannot trigger encouragement. Observed counts are consumed even while encouragement is disabled, preventing opt-in from replaying a completed rep. An ignored snapshot is not retried later when cooldown expires.

## Native integration handoff

The native owner can add the following final argument in `TrainingStore.coachingTick`'s `CoachingInput` initializer (using the current native owner's `remoteVoice.preference` API):

```swift
stopReason: stopReason, source: configured?.source ?? source,
encouragementEnabled: voiceFeedbackEnabled && remoteVoice?.preference == .david
```

The new reason also requires the native owner to update the exhaustive switch in `Native/iOS/Components.swift` before native compilation:

```diff
-            case .targetReached: return green
+            case .targetReached, .steadyRhythm: return green
```

Both are suggested integration patches, not applied here. Core passes independently; native compilation requires the switch update. David selection plus voice-feedback opt-in enables the policy option. The remote adapter separately permits intense tone only for this exact positive pacing text and only when David's intense tone is advertised. Keep native playback expiry/cancellation and local stop priority in place. If the native selection API changes, adapt the argument there; Core has no dependency on a voice provider.

## Evidence and remaining gates

Validation: `swift test --filter CoachingPolicyTests` passed 26 tests; full `swift test` passed 98 XCTest cases plus 130 Swift Testing cases, with zero failures. `git diff --check` passed.

Offline SwiftPM behavior tests exercise opt-in/default-off behavior, valid prior statistics, noise margins, fast/invalid timing, insufficient/wrong-exercise history, cue priority, targets, cooldown, source/clock/session/generation freshness, paused replay and heart-rate independence. Tests were first observed failing before the policy implementation and pause regression fixes.

No provider request, native app build, simulator/device exercise, audio playback or Safari interaction was performed in this lane. Native owner still needs to enable the argument, run native integration tests and verify actual opt-in, selected-coach, cancellation and audible behavior. This is descriptive timing feedback, not clinically validated coaching or evidence that continuing exercise is safe.

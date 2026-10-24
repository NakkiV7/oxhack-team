# Adaptive coaching policy

`CoachingPolicy` is a local, deterministic decision policy. It never invokes an AI service, creates sensor values, or estimates capacity. Native presentation owns speech cancellation, cue visibility, and event expiry; policy state should survive set changes and pause/resume, and be replaced for a new workout using `CoachingPolicy(history: history)`. The initializer defaults to an empty history, preserving `CoachingPolicy()` callers.

## Input and output

Call `mutating evaluate(_ input: CoachingInput) -> CoachingDecision?` when a completed rep changes the count and on the session's one-second timer. The input contains session/generation identity, phase, monotonic clock, exercise, observed completed rep count and last duration, camera cue, Watch readings and wall clock, actual elapsed rest, planned target, and reported stop reason. Missing measurements remain optional. The final initializer argument is `source: InputSource = .camera`; replay/manual callers must explicitly pass their actual source.

The result contains `text`, `priority` (`stop`, `form`, `pacing`, `rest`), `reason` (`discomfort`, `tracking`, `alignment`, `slowerRep`, `targetReached`, `restReminder`), concise observational `facts`, and optional `elapsed`. `elapsed` is the observed rep duration for `slowerRep`, actual rest duration for `restReminder`, and nil otherwise. Inputs and outputs are `Sendable` and `Equatable`.

## Communication rules

- Reported discomfort produces an immediate stop cue once, and suppresses further coaching for that session, including after generation changes. Native configured rep/hold workouts route the reported stop before tracking-only guards, using the same decision without assigning a fictitious camera exercise. A per-session issued marker prevents repeated actions or foreground return from restarting the event. Ordinary manual coaching remains silent.
- Non-camera input is otherwise silent: video replays and manual input cannot add personal baseline samples, produce coaching/rest interjections, or attach Watch facts. The ordinary replay camera-cue UI remains separate. Returning to a real camera generation retains the user's genuine observed baseline.
- Camera tracking loss or an alignment cue interrupts immediately, ahead of ordinary pacing or target messages. The same unresolved camera cue is not repeated. Clearing the cue allows a later recurrence to speak again.
- Ordinary cues have a ten-second cooldown. A form cue also reserves this cooldown; a new form/tracking problem or discomfort can still interrupt it. Paused, idle, and finished sessions receive no ordinary cues.
- A completed rep bypasses the one-second evaluation gate. Reaching the planned target can acknowledge that boundary once and offers ending the set, without encouraging extra reps.
- Actual elapsed rest of at least 45 seconds can produce one neutral reminder per rest period, on one-second checks. Missing, negative, or nonfinite rest durations produce no reminder. This timer is independent of Watch availability and makes no readiness or recovery claim.
- Old generations and previous session IDs are rejected. Generation changes reset timing and cue context. A new set resets its rep-count high-water mark; pause/resume preserves it so an already completed rep cannot be learned again.

## Personal tempo baseline

Each exercise starts with up to 60 valid observed completed rep durations from saved personal history. Session IDs and set IDs are deduplicated; the newest session snapshot wins, and eligible durations are processed chronologically so the latest 60 remain. Only camera sets qualify. Video replays, manual sets, and sets stopped for form or discomfort are excluded. A saved set must have a positive rep count, an exactly matching duration count, and every duration finite and within 0.6–15 seconds; malformed sets are excluded as a whole. Missing legacy timings never create samples.

During the workout, each exercise keeps its latest 60 eligible historical or newly observed completed rep durations. A sample must be finite and between 0.6 and 15 seconds inclusive. Only an increase in completed rep count can add the latest sample; duplicate frames/ticks cannot add it again, and a skipped count does not fabricate missing durations. Paused or resting inputs cannot add samples.

The first five valid durations establish the minimum baseline. For a later completed rep, compare its duration with the **previous** samples before adding it:

`slow threshold = previous mean + max(previous sample standard deviation, 0.25 seconds)`

Sample standard deviation uses denominator `n − 1`. A rep must be strictly longer than the threshold. The quarter-second minimum margin prevents zero-variance timing noise from producing repeated messages. The response describes a longer rep and offers control, a pause, or ending the set. It does not infer fatigue, ability, medical status, or tell the user to speed up. The baseline continues across sets of the same exercise, stays separate for squats and push-ups, and restores the history seed for a new session while clearing the previous session's stream and latches.

These thresholds are reviewable product heuristics, not validated medical or performance thresholds. The tests establish software behavior, not clinical accuracy or real-device acceptance.

## Watch observations

Heart rate alone never initiates coaching. When a form or tempo cue already has a reason to appear, it may include fresh Watch facts. Readings must have finite values from 1 to 300 bpm and timestamps between two seconds in the future and 30 seconds old. Timestamp duplicates count once. A current reading must satisfy the existing freshness window (no more than 12 seconds old, allowing two seconds of future clock skew). Without a fresh latest reading, no Watch facts are added.

Five or more unique valid observations in the last 30 seconds permit a mean and sample standard deviation fact. Fewer samples permit only the fresh current observation. There are no fixed medical zones, heart-rate-driven rest commands, recovery judgments, or synthetic values.

## Verification

`Tests/Core/CoachingPolicyTests.swift` exercises discomfort, camera priority/deduplication, cooldown, target boundaries, actual rest timing, sample SD and minimum noise margin, personal-history seeding and eligibility, saved-session/set deduplication, the latest-60 per-exercise limit, invalid durations, replay/manual stream exclusion, real-camera baseline retention across replay, duplicate rep observations, set/pause/session lifecycle, stale generations, invalid/backwards clocks, and Watch freshness/uniqueness. Run `swift test --scratch-path /tmp/spottr-cue-tests` for the core suite. Native presentation and device behavior require separate verification.

The configured manual/hold integration is covered by three native regressions in `Tests/iOS/CoachingFlowTests.swift`; they first reproduced the missing event, then passed with 20 existing coaching/voice/configured-flow checks (23 total). No camera, provider or physical audio was used. The unchanged recovery UI already blocked continuation; the correction connects the stop event and optional voice bridge.

The helper extraction also passed 26 focused core policy/playback checks. The existing TinyTaps-Watch target then built successfully in 2.95 seconds with no warnings (`build_sim_2026-10-24T22-56-22-507Z_pid4129_d53d0faf.log`). This verifies watchOS compilation of the shared decision; it does not exercise physical Watch sensors or audible speech.

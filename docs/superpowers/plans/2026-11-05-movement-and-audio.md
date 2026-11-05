# Movement and Audio Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Consistent complete speech and a larger, honestly tracked exercise library, installed on Omar's iPhone after all checks.
**Architecture:** Keep the existing on-device pose model; add movement profiles/geometry, robust cycle and observed-time state machines. Keep audio intent separate from a recording's lifetime and invalidate old workout contexts explicitly.
**Tech Stack:** Swift, SwiftUI, MediaPipe, AVFoundation, XCTest/Swift Testing, existing Node gateway checks.
**Spec:** docs/superpowers/specs/2026-11-05-movement-and-audio-design.md

## Global Constraints

Native Swift app; no runtime paid AI or new training; no faces; no Chrome or new/erased simulators. Preserve IDs, units, saved counts/sets/manual modes, protected build17/Vendor and evidence. Bulk output on SSD. TDD first. Physical installation happens after all changes and verification, not after an intermediate task. User authorisation for this continued feature branch, pushes/TestFlight delivery and final iPhone installation is already present in the chat.

## Review Focus

- An ordinary audio expiry/nil warning must not truncate an already-playing sentence; add controller and TrainingStore regressions in Task1.
- A missing joint at the deepest observed point must preserve countability without inventing depth; add temporal/camera pose fixtures in Task2.
- Alternating limbs must neither disappear nor be fused into a single rep; add per-limb pose-cycle tests in Task2.
- Timed camera quantity must exclude invisible time and remain distinct from active session time across input changes; add integration/report tests in Task3.
- New movement art/setup and source attribution must match the actual tracker; add catalogue/guide and UI checks in Task3.

### Task 1: Action-consistent audio lifecycle

**Files:** Shared/Core/VoiceCuePlayback.swift; Native/iOS/{RemoteVoicePlayback,DemoVoicePlayback,CoachingVoiceBridge,TrainingStore}.swift; related Tests/Core and Tests/iOS voice files. Root alone owns catalogue/CV integration and generated audio assets.
**Interfaces:** Preserve VoicePlayback, VoiceCue and existing public controller calls; small explicit transition APIs are allowed. Do not modify capture receive/geometry logic. Introduce no new dependencies.
- [ ] Write and run failing tests for natural completion beyond start expiry, nil/cleared warning, equal/lower cue, recovery transition, stop/mute/pause/input/coach/background/new-context cancellation, start/closing exactly once and interruption cleanup.
- [ ] Implement the smallest controller/player/store changes, retaining immediate safety and dropping stale deferred cues. Make repeated starts/resumes consistent and avoid rep/coaching overlap.
- [ ] Run relevant core checks with SSD scratch (jobs2 max); do not use a simulator without root coordination. Record exact red/green commands and output. Root runs native integration later.
- [ ] Self-review and commit only owned files; write a report with interfaces, evidence and remaining device limits. Controller dispatches task review and resolves findings before Task2 implementation.

### Task 2: Movement profiles, geometry and robust counters

**Files:** Shared/Core/{Exercise,ExerciseCatalog,PoseGeometry,RepCounter}.swift; new bounded movement-profile and observed-time helper files if useful; related Tests/Core. Do not edit TrainingStore, ConfigurableSession, workout UI/report files or art; Task3 owns integration.
**Interfaces:** Preserve existing Exercise IDs and MovementSample initializer compatibility. Add Exercise.isTimed (Bool), Exercise.focusJointIndices ([Int]), explicit measurement provenance if a normalised signal differs from joint angle, and movement-specific camera/profile metadata suitable for Task3. Provide a public PoseHoldCounter (or clearly documented equivalent) with observedSeconds, resetContinuity(), consume(MovementSample) and an appropriate static/dynamic timing mode. Existing PoseGeometry.measure remains the capture entry point. Record exact added interfaces in the report.
- [ ] Read spec catalogue target and establish behavioural fixtures before implementation, including existing movements and all new profile families, mirrored sides and negative cases.
- [ ] Implement levelled 53-entry catalogue and up to52 dedicated/gated tracking identities; retain catCow manual. Correctly support alternating sides, setup/orientation, movement range and hold/activity measurement without pretending to classify the whole exercise or check contact/load.
- [ ] Improve confidence/outlier/hysteresis/gap behaviour, brief witnessed-bottom counting and tempo/pause timing. Preserve prior reps and avoid side fusion or unobserved timing credit. Keep old APIs/history compatible.
- [ ] Run full core suite with SSD scratch/jobs2. Update stale tests only where intentional new capabilities supersede their old assumptions; preserve regression intent. Do not weaken evidence boundaries to make catalogue totals green.
- [ ] Self-review, commit owned files and report exact profile list, interfaces, thresholds, red/green evidence and limitations. Controller dispatches task review before Task3 implementation.

### Task 3: Phone/session/report/art integration

**Files:** Shared/Core/{ConfigurableSession,LoggedWorkout,WorkoutReports,TrainingPath,MovementIllustration,ExerciseDemonstrationGuide,CoachingPolicy,OfflineExperience}.swift; Native/iOS/{TrainingStore,ConfiguredSessionViews,SessionViews,Components,StickFigureArtwork,SkillsViews}.swift as needed; tests; server catalogue capability contracts/tests; fixed audio manifests/clips.
**Interfaces:** Consume Task2's profiles and observed-time counter. Use Task1 transition APIs without restoring cancellation-on-every-tick. Keep workout elapsed time separate from measured quantity and support camera/manual switches with provenance.
- [ ] Write/run failing integration tests for observed timed quantities, source switching, pause/reacquisition, reports/exports and old history decoding; add guide/illustration and capability tests for new families.
- [ ] Wire capture to the right measurements, counters and focused joints; preserve quick rep and configured timed flows, user quantities and existing skill chains. Show camera timing separately from rep counting/assessment. Ensure the real exercise units drive targets/coaching facts.
- [ ] Add matching faceless figures, camera-angle/support guidance and levels for new movements using existing visual language. Fix generic speech text for camera views/timed work and regenerate only required clips under the already-authorised cap, with private receipts and no POST retries.
- [ ] Run all core/gateway/static/Pi checks and relevant/full native plus selected UI journeys. Use only shared existing iPhone under root coordination, isolated test namespaces, SSD build directories and jobs2. Record all failures and their resolutions.
- [ ] Self-review, commit owned files and report. Controller dispatches broad whole-change review, then fixes and re-reviews Critical/Important findings before delivery.

### Task 4: Finished release and physical installation

**Files:** project version/generator, release/evidence/testing docs, private receipts and SSD signed builds.
- [ ] Freeze sources and audit the complete signed phone/Watch archive: signatures/profiles, canonical pose model, audio bytes, no credentials, compatible versions; recheck protected build17/Vendor and original evidence.
- [ ] Verify the connected physical iPhone and install the finished signed build with devicectl/purpose-built device tools, preserving data. Handle actual unlock/trust/developer-mode requirements through the user if needed. Do not install until Tasks1–3 and final review are complete.
- [ ] Push feature branch and deliver TestFlight candidate as already authorised, verify actual Apple state separately from upload, and record the installed device/app/version. Distinguish software checks from real movement/listening acceptance.

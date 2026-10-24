# Spottr native implementation

**Goal:** Working local iPhone + Watch apps using the approved white designs, MediaPipe push-up/squat tracking and the existing paired simulators.
**Architecture:** Pure Swift exercise/session/wire domain; thin AVFoundation + MediaPipe adapter; SwiftUI screens; WatchConnectivity companion; local Codable history. No server or paid API.
**Stack:** Swift 5 mode, iOS/watchOS 26, SwiftUI, XCTest/Swift Testing, MediaPipeTasksVision pinned to an immutable upstream revision.
**Spec:** `docs/2026-10-24-spottr-design.md`; user approved implementation on 24 October 2026.

## Global constraints

- Reuse Musalli-Test and TinyTaps-Watch. Preserve all installed apps and data.
- Use existing generated PNG graphics and SF Symbols; no authored SVGs.
- Count observed full cycles only; missing tracking, pause, stale/out-of-order data and source changes cannot complete a rep.
- No invented HR, performance, prediction or chat. No provider calls. Camera/video stay on device.
- Behavior tests first, then minimal implementation. Simulator verification does not establish physical camera accuracy or Watch sensor delivery.

## Task 1: Exercise engine

**Produces:** `Exercise`, `PoseFrame`, `RepCounter`, `TrackingResult` in `Shared/`; Swift package tests.
Write a failing full-cycle counting test, implement minimal state machine, then test partial reps, brief/noisy transitions, confidence loss, source/side switches, pause/reset, implausible timing, timestamp gaps and aspect-correct landmark geometry. Use literal hand-checked angle fixtures. Run `swift test`; expected all pass. Commit working domain.

## Task 2: Session and companion contract

**Consumes:** Exercise engine. **Produces:** `TrainingSession`, `SetRecord`, `SessionRecord`, `CompanionSnapshot`, `CompanionCommand`, local history store.
Test start/pause/resume/end/rest/next/finish behavior, no duplicate saves, feedback and stop reasons, session/generation IDs, stale companion snapshots, Codable round trip and durable history in a temporary directory. Implement through public domain API. Run `swift test`; expected all pass. Commit.

## Task 3: Native iPhone and MediaPipe

**Consumes:** Domain, generated art. **Produces:** `Spottr.xcodeproj`, iOS target, real MediaPipe camera/video adapter, Today/Train/Rest/Progress/Coach.
Generate project with existing Ruby xcodeproj. Add failing UI flow tests before screens; add failing real-model smoke test before adapter. Bundle official Lite model with source/hash and licensing notices. Camera processing on one serial worker with frame dropping; no UI-thread inference. Pause/background/end cancel processing and invalidate late results. Video import uses the same detector and domain, explicit source, bounded frame sampling. Unknown HR shown as a dash. Start/stop actions remain available. Run package suite, iOS integration/UI tests and simulator build/run; expected passing and visible approved screens. Commit.

## Task 4: Watch companion and acceptance

**Consumes:** Session wire contract. **Produces:** watchOS target with count/cue/pause/end, real HealthKit workout HR and Core Motion availability handling, WCSession transport.
Add failing contract/state tests before companion behavior. Install/run on existing TinyTaps-Watch. Exercise phone session flow, background pause, persistence and companion snapshot/command transport where simulator supports it. Never treat absent sensor data as measured. Record exact evidence and remaining physical tests. Run full package suite and native checks; expected green. Request one independent whole-change review, fix meaningful findings with red-to-green regression tests, update README and verification notes. Commit.

## Review focus

Camera orientation and displayed overlay must agree; video timestamps must be monotonic; confidence/quality gates must not call unknown form bad form; stop/pause and stale callbacks cannot count; imported clips cannot silently combine with camera sessions; old Watch commands cannot mutate a new set; sensor freshness must expire. Check device framework slices as well as simulator compilation. Inspect UI at actual simulator size and larger accessibility text. Do not claim physical exercise or sensor acceptance from synthetic tests.

## Execution notes

User explicitly asked to start building, so execute inline without another approval gate. Empty workspace has no existing git history: initialize a feature branch here, preserving all design/research artifacts. Keep this document and `docs/native-build-progress.md` as the compact execution record.

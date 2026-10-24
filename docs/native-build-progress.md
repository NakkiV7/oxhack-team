# Spottr native build progress

Plan: `docs/superpowers/plans/2026-10-24-spottr-native-implementation.md`.

Pre-flight: exercise/session types feed both UI and companion wire contract; shared Foundation-only sources compile in SwiftPM and both app targets. MediaPipe is iOS-only. No conflicting interfaces found.

Execution choice: user explicitly authorized building; native implementation proceeds inline. Ruby xcodeproj is already available, so no generator installation is needed. Fresh project starts on `feat/native-app`.

Tasks 1–2: full-cycle, tracking-loss, continuity, geometry, pause/resume, exercise progression, source restart, companion generation/freshness and durable-history tests observed red before implementation. Pure Swift suite now green. No useful abstraction beyond separate geometry, rep and session types identified.

Dependency choice: use official immutable MediaPipe 1.1.1 XCFrameworks directly (same URLs/checksums as upstream revision d761bb9a3fdc2135ebf046a093a99b95484897dc). Both arm64 device and arm64 simulator slices verified. Fetch only Vision/Common/TaskGraphs; avoid cloning the full repository and bundling unrelated task SDKs. Real-model integration test will verify required registrations/linking.

Native milestone: MediaPipe human/blank smoke test, delayed camera-permission cancellation, video pause/resume, complete UI/session/persistence flow and unavailable-camera UI all pass (5 native tests, 24 October 14:59). Core suite: 16 tests pass. Existing Musalli-Test and TinyTaps-Watch launched successfully, Watch received a real session snapshot. No physical sensor/exercise verification yet. Watch simulator refuses sensor recording rather than publishing simulated physiology.

Video test is an added characterization of the real decoder/model pipeline before migrating deprecated AVFoundation calls; its fixture does not establish rep accuracy. Camera cancellation regression was observed failing before the intent cancellation fix. Camera fallback regression was observed failing before checking hardware availability ahead of permission.

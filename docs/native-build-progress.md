# Spottr native build progress

Plan: `docs/superpowers/plans/2026-10-24-spottr-native-implementation.md`.

Pre-flight: exercise/session types feed both UI and companion wire contract; shared Foundation-only sources compile in SwiftPM and both app targets. MediaPipe is iOS-only. No conflicting interfaces found.

Execution choice: user explicitly authorized building; native implementation proceeds inline. Ruby xcodeproj is already available, so no generator installation is needed. Fresh project starts on `feat/native-app`.

Tasks 1–2: full-cycle, tracking-loss, continuity, geometry, pause/resume, exercise progression, source restart, companion generation/freshness and durable-history tests observed red before implementation. Pure Swift suite now green. No useful abstraction beyond separate geometry, rep and session types identified.

Dependency choice: use official immutable MediaPipe 1.1.1 XCFrameworks directly (same URLs/checksums as upstream revision d761bb9a3fdc2135ebf046a093a99b95484897dc). Both arm64 device and arm64 simulator slices verified. Fetch only Vision/Common/TaskGraphs; avoid cloning the full repository and bundling unrelated task SDKs. Real-model integration test will verify required registrations/linking.

Native milestone: MediaPipe human/blank smoke test, delayed camera-permission cancellation, video pause/resume, complete UI/session/persistence flow and unavailable-camera UI all pass (5 native tests, 24 October 14:59). Core suite: 16 tests pass. Existing Musalli-Test and TinyTaps-Watch launched successfully, Watch received a real session snapshot. No physical sensor/exercise verification yet. Watch simulator refuses sensor recording rather than publishing simulated physiology.

Video test is an added characterization of the real decoder/model pipeline before migrating deprecated AVFoundation calls; its fixture does not establish rep accuracy. Camera cancellation regression was observed failing before the intent cancellation fix. Camera fallback regression was observed failing before checking hardware availability ahead of permission.

## Team delivery milestone

The native app now includes the 19-entry equipment-free catalogue, Roman-numeral skill challenges, deterministic earned attributes, manual logging, active-time hold timer, source-labelled history and actual session/week reports. Valid recorded rep durations are stored and averaged per observed rep. Watch BPM sits above the live timer; missing/stale readings remain unknown.

Gemini chat, session/week summaries, catalogue proposals, explicit checklist approval and manual logging are wired through a configurable gateway. Gateway access lives in this-device Keychain; provider credentials remain server-side. Optional Tiger upload is explicit and reports an immutable hash receipt. No provider or database success is inferred from fixture tests.

Independent native/core and gateway/setup reviews completed on immutable Git trees. Corrected findings with red-to-green regressions: history truncation erased XP after 100 sessions; changed support could approve stale proposals; provider/native response limits differed; retained Watch readings duplicated scalar observations; oversized conversation requests exceeded 64 KiB; trimmed/canceled conversations needed provider role normalization.

Verified locally on 24 October 2026:

- `scripts/bootstrap.sh`: Xcode/SDK/generator checks passed; existing SDKs reused. No simulator creation/erase or package installation.
- `scripts/check.sh`: 42 Swift Testing tests plus 15 XCTest package tests passed; 27 gateway tests passed after final history normalization. Tests use offline service/database fixtures.
- Final combined native run: 18 tests passed, 0 failures, 0 skipped; no warnings (133.3 seconds). Result bundle: `test_sim_2026-10-24T15-31-50-228Z_pid4129_700d3344.xcresult` under the local XcodeBuildMCP result-bundles directory.
- Unsigned `generic/platform=iOS` Debug build including embedded Watch: succeeded. This does not establish signing, physical install or exercise accuracy.
- Reused Musalli-Test phone and TinyTaps-Watch: both build/launch successfully. Earlier phone-to-Watch snapshot receipt was observed; latest manual command acceptance and physical sensors remain pending.

Local evidence: `/tmp/spottr-publish-checks.log`, `/tmp/spottr-publish-device-build.log`, XcodeBuildMCP result bundles referenced by the final delivery note. Provider keys have not been committed. At this stage no Gemini response, Tiger migration/persistence, Snowflake statement, Vultr deployment, Presage measurement or Arduino transport has been verified live. Delta is running in the desktop inventory; no actual Delta evaluation thread has been completed.

# Spottr native build progress

Plan: `docs/superpowers/plans/2026-10-24-spottr-native-implementation.md`.

Pre-flight: exercise/session types feed both UI and companion wire contract; shared Foundation-only sources compile in SwiftPM and both app targets. MediaPipe is iOS-only. No conflicting interfaces found.

Execution choice: user explicitly authorized building; native implementation proceeds inline. Ruby xcodeproj is already available, so no generator installation is needed. Fresh project starts on `feat/native-app`.

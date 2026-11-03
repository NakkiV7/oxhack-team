# Consolidated patient demo implementation plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task-by-task in the current session.

**Goal:** Deliver one runnable Spottr demo with the pushed paths, Insights, audio and web exercise tools.

**Architecture:** Keep SwiftUI and shared Swift domain logic. Merge existing contributions before adding changes. Essential practice, paths, audio and local reports work without provider services.

**Tech Stack:** SwiftUI, XCTest/Swift Testing, Node test runner, browser MediaPipe.

**Spec:** `docs/superpowers/specs/2026-11-03-consolidated-patient-demo-design.md`

## Global constraints

- Preserve local Full-model, camera lifecycle, preview isolation and physiology work.
- No paid provider activation, private-data migration, remote Git push or store submission.
- Patient outcomes and GP workflows remain proposed until implemented/evaluated.
- Use existing code and supplied recordings; keep raw video/replay separate from live achievements.

## Review focus

- Failed disk writes preserve the last saved path and surface an error.
- Ordinary history excludes sample days and sample streaks.
- Missing network does not block a catalogue path or exercise practice.
- Camera permission/loss and source switching preserve usable stop/manual controls.
- Muted, stopped or stale sessions cannot speak delayed count/encouragement audio.

### 1. Consolidate existing work

- [x] Save tracked local changes in a checkpoint commit and retain an ignored binary diff.
- [x] Merge `origin/main`, `origin/nakki/app-demo`, `origin/nakki-squat-model`; retain both contributors' changes in conflicts; regenerate project.
- [x] Run `swift test`, gateway tests and both web suites; diagnose observed failures before changing production code.

### 2. Reliable patient journey

Files: `Native/iOS/TrainingPathStore.swift`, `TrainingPathViews.swift`, `OnboardingView.swift`, `InsightsView.swift`, relevant `Tests/iOS` and `Tests/UI`.

- [x] Add failing tests for path-write rollback, actual-only calendar defaults and onboarding-to-first-practice navigation.
- [x] Persist candidates before publishing path state; surface save failure.
- [x] Make sample history explicit preview only; improve path entry/next action and onboarding with existing components.
- [x] Run focused tests, native build and rendered UI flows.

### 3. Working squat/push-up tools and native audio

Files: `prototype/pushup`, `prototype/squat`, native voice/store files and project generator.

- [x] Install existing locked web dependencies; run each test suite and load models locally.
- [x] Exercise actual browser model loading and video input. Add reproductions for broken routes, missing assets, camera/source lifecycle or feedback before fixes.
- [x] Verify merged offline rep audio and safety/cancellation tests; make coach choices understandable.
- [x] Build native simulator and signed device app; check connected phone and install when reachable.

### 4. Demo evidence and handoff

- [x] Export current native UI screenshots and bundle the existing prepared exercise movies; retain replay labels.
- [x] Write a OneMedicalGroup pitch storyboard with the £125k/30% ask as Omar's proposal, working features, proposed pilot and evidence still needed.
- [x] Record exact checks, launch commands, source revisions and remaining physical gates in `docs/demo-consolidation-2026-11-03.md`.
- [x] Review final diff and run relevant completion checks; leave all work locally reviewable.

## Acceptance boundary

Build 16 is installed and launched on the paired physical iPhone. The 243 native tests and four final UI flows pass. Real-person squat/push-up counting and audible output still require the requested physical rehearsal; no clinical or Watch acceptance is implied. Chrome testing and local web test servers were stopped at Omar’s request. The temporary simulator was deleted and final UI testing used the existing shared iPhone.

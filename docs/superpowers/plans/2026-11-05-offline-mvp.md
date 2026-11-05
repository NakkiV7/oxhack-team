# Spottr Offline MVP Implementation Plan

> Native execution in this chat. Each behavior change starts with a failing behavioral test.

**Goal:** A coherent offline testing build with resilient exercise tracking, local coaching and onboarding placement.
**Architecture:** Shared pure Swift policies and counters drive SwiftUI phone and Watch screens. Bundled audio and on-device speech are adapters, never provider calls in a workout.
**Tech Stack:** Swift, SwiftUI, MediaPipe, AVFoundation, Speech, HealthKit, WatchConnectivity.
**Spec:** docs/superpowers/specs/2026-11-05-offline-mvp-design.md

## Global constraints
- Reuse existing simulators. No Chrome. Preserve build 17 and archive evidence. SSD for new build scratch.
- No consumer provider requests or tokens. Preserve real history and old saved files.

## Review focus
- Occluded depth may continue a witnessed rep, never invent an unseen bottom.
- Input changes keep totals and exclude mixed/manual timing from CV claims.
- Self-reported placements never become recorded workouts or XP.
- Repeated speech hypotheses never double count; missing offline recognition falls back to manual.
- Watch disconnected/stale readings display as missing, never current.

## Tasks
- [x] Exercise variants: tests in Tests/Core/ExerciseVariationTests.swift, geometry in PoseGeometry.swift, thresholds in Exercise.swift and RepCounter.swift, catalogue mapping. Verify `swift test`.
- [x] Session continuity: tests in Tests/Core/InputContinuityTests.swift, `switchInput(source:at:)` in TrainingSession and ConfigurableSession, native capture methods and controls. Verify counters, timing, pause, stale generation and provenance.
- [x] Onboarding and vertical skills: profile schema with backward-compatible comfort placements, deterministic visible progression, weight-management goal. Onboarding revision and coach choice. Remove preview and AI path entry points.
- [x] Offline coach and insights: quantitative shared summaries, option-based coaching, replace summary network buttons, remove runtime gateway settings from consumer navigation. Test missing, replay and duplicate data.
- [ ] ElevenLabs recording authoring (blocked by expired credentials; offline system-voice fallback implemented): original coach styles, varied cue library, bundled generation manifest and offline playback fallback, persisted selection. Keep legacy optional recordings. No new celebrity generation.
- [x] Speech input: strictly on-device recognizer with permission and teardown, monotonic number parser, camera exclusion and manual-labelled records. Test repeated and stale transcripts.
- [x] Watch and performance: distinct vitals page and freshness checks; reuse pose processor across camera resumes with monotonically increasing detector timestamps. Compile both native targets.
- [x] Artwork and validation: generate exercise artwork, check assets, run core/native/Watch checks, document actual results and ordered feature backlog. No claims of physical accuracy from synthetic checks.

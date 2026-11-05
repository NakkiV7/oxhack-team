# UI and Watch polish implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make Spottr consistent and finished, with workout-style artwork and truthful guided Watch setup.
**Architecture:** Shared native SwiftUI style primitives, existing bundled artwork and local optional Watch setup state; keep one CompanionLink owner and backward-compatible message contracts.
**Tech Stack:** SwiftUI, Foundation, HealthKit, CoreMotion, WatchConnectivity, XCTest/Swift Testing.
**Spec:** docs/superpowers/specs/2026-11-05-ui-watch-polish-design.md

## Global constraints

No faces, runtime AI, new simulators, Chrome, reset, paid dependencies or HPC jobs. Preserve build17/Vendor and original evidence. Build scratch on SSD. Reduce Motion and accessibility text sizes must work. Setup is optional and model answers do not attest hardware or permissions.

## Review focus

- Offline/unpaired/replaced Watch and stale replies must not show connected or synced completion.
- Model choices must not manufacture capabilities or erase historical readings from another source.
- Read denial and no available data are indistinguishable; copy must reflect this.
- Larger text/Reduce Motion must retain navigation and readable actions.
- New artwork and transitions must preserve session progress and avoid background animation work.

### Task 1 — consistent artwork and onboarding
- [x] Test the onboarding journey and skippable Watch entry; test new animation/state behavior where applicable before implementation.
- [x] Reuse workout imagery in `StickFigureArtwork.swift`, update `OnboardingView.swift`, and unify artwork choice in `SkillsViews.swift` only as required. Animation respects Reduce Motion and active visibility.
- [x] Root runs existing simulator UI checks and captures.

### Task 2 — guided Watch setup
- [x] Write failing pure tests for model choices, milestone/status projection, freshness and capability limitations.
- [x] Implement local model selection, honest pairing/install/connection/sync milestones and concise instructions in `WatchSetupView.swift`; add backward-compatible connection status messaging only if required. Reuse CompanionLink delegate.
- [x] Test Watch SDK boundary/replay and compatibility. Document unavailable and historical-vs-live distinctions.

### Task 3 — shared layout and consumer copy
- [x] Add UI journey checks for core actions, headers and expandable explanations before modifying behavior.
- [x] Unify button press feedback and content heading/surface primitives in `Components.swift`; improve Today, Insights, Coach and Skills hierarchy. Remove prototype narration from primary flows while retaining measurement provenance and relevant errors.
- [x] Keep report methodology in optional disclosure where appropriate. Preserve measurement math and identifiers.

### Task 4 — integration and release
- [x] Register new sources semantically and increment next build. Run core/native/Watch checks using SSD and existing iPhone.
- [x] Review default and accessibility-size screenshots and Reduce Motion behavior; independent scoped review.
- [x] Compare protected artifact manifests. Archive/export/audit/upload and verify TestFlight state. Update evidence/priorities and push branch.

## Builder decisions and verification

The builder check found nothing important unanswered. Model selection is a local guidance preference; historical readings from another device are retained. One shared CompanionLink owns WCSession and the setup handshake. Image reuse preserves the workout style, with an added rail for supported squats. Source review found and resolved the missing rail and cached-receipt issues. Visual review removed duplicate optional-setup copy. Profile tests use a stable note identifier and now exercise an explicit keyboard Done/drag bar.

393 core checks, 224 selected native checks and 23 selected UI journeys passed across integration/correction runs. Watch SDK checks and actual transport replay passed. Four StoreKit cases remain setup-blocked; physical Watch acceptance remains separate. Signed delivery is complete: build21 is VALID and IN_BETA_TESTING internally and externally, with APPROVED beta review. Implementation c582616 is pushed; private release receipts are hash-verified on SSD.

# Spottr progression and reports

**Goal:** Add equipment-free exercise levels, explicit manual/timed logging, deterministic skill progress and meaningful local weekly/session reports; prepare bounded Google integration without spending API credits.
**Architecture:** Keep the existing two-exercise MediaPipe engine intact. Add a catalogue with optional tracked-exercise mappings, logged-set history and a pure evidence/report projection. Native views consume those projections. Google uses a separately validated proposal/report contract.
**Stack:** Existing SwiftUI iOS/watchOS project, Foundation core, Swift Charts and generated PNG art.
**Spec:** `docs/superpowers/specs/2026-10-24-spottr-training-platform-design.md`.

## Constraints and review focus

No paid provider calls. No training/inference claims for unvalidated variations. Both manual and camera sets count with source labels; video history remains visible but contributes no skill points until replay deduplication is implemented. No preparation time awards hold progress. History decoding remains compatible with existing sessions. Empty weeks and absent Watch samples stay explicit. Scores are game points. No new simulators or SVG artwork.

## Tasks

1. **Catalogue and history:** test a manually logged set through saved history before implementation; reject unknown exercise IDs, zero/negative quantities and unit mismatch. Add versioned movement definitions, Roman levels and tracked mappings. Preserve existing MediaPipe types and flow. `swift test` must pass.
2. **Progress and reports:** write failing tests for multi-day unlocks, duplicate session/set IDs, discomfort, daily cap, mixed manual/camera sources, video exclusion, week boundaries, category derivation and distinct/fresh HR readings. Implement pure evidence and report projections. `swift test` must pass.
3. **Native screens/art:** add failing UI flow for library → manual set → report/skills before implementation. Add Skills tab, exercise details/logging, weekly overview and report charts. Use generated individual pose assets. Keep live BPM above timer. Run native tests and inspect actual simulator-size screens.
4. **Google contract:** failing parser/validator tests for unknown exercises, invalid targets and unknown evidence IDs; implement strict catalogue-only proposal/report schemas and approval state. No live API or pretend AI output. Preserve a clear adapter boundary for the later Vultr gateway.
5. **Acceptance:** full core/native checks, unsigned device builds, existing paired simulators, one independent final review. Update README, integration status and evidence. Cloud/Arduino/Delta work remains explicitly staged in the design rather than claimed live.

Review the app as a person training: can they understand the level and exercise, log honestly, stop quickly and inspect what actually happened? Inspect hold-vs-rep units, metric provenance, duplicate awards, stale callbacks and source switching. No merge, deployment or provider invocation is required.

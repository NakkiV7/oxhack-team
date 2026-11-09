# Spottr Account Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Make normal setup retries, expiry and membership operation feedback reliable.

**Architecture:** Keep server auth stages and Apple verification unchanged. Add narrowly scoped native transient state and explicit operation feedback, covered through real store boundaries and rendered SwiftUI actions.

**Tech Stack:** SwiftUI, AuthenticationServices, StoreKit, XCTest and existing Core Swift package.

**Spec:** docs/superpowers/specs/2026-11-09-account-recovery-design.md

## Global Constraints

The Binding constraints section of the spec applies verbatim. Reuse codex/spottr-demo-consolidation and existing checkout. The controller owns shared-device leases, builds for release, API operations, installation and publication. No other product writer runs alongside the implementer. No subagents from implementers.

## Review Focus

- Cancelled system authorization versus lost verification response must not replay the wrong server stage.
- Cached registration options must never cross flow, account, purpose or expiry boundaries.
- A retained SwiftUI view must not carry hidden backup selection into a different factor flow.
- Expiry while backgrounded must discard only temporary setup data, preserving local workouts and recovery credentials.
- Pending or cancelled upgrades and restore outcomes must stay visible without changing entitlement state.

### Task 1: Repair native account retries and membership feedback

**Files:** Native/iOS/AccountStore.swift, Native/iOS/AccountViews.swift, Native/iOS/MembershipView.swift, Shared/Core/MembershipCoordinator.swift and focused existing/new Tests/iOS, Tests/Core and Tests/UI files as needed. Do not edit Worker code unless a concrete required interface defect is demonstrated and ruled on by the controller.

**Interfaces:** Consume the existing AccountClient one-time flow endpoints and NativeAccountAuthorization register API unchanged. Add only narrow testable native transient state/clock or membership-result presentation interfaces required by the spec. Preserve all existing public clients and default initializers.

- [ ] Read the source diagnosis at .superpowers/sdd/2026-11-09-landing-refinement/account-membership-diagnosis.md and inspect actual current code. It is evidence of defects, not a product specification overriding this plan.
- [ ] Write stateful behaviour tests for cancelled enrollment and recovery registration, fresh-flow cache isolation, expiry, and an ambiguous verification response. The fake transport must enforce identity to registration to enrollment stages and reject impossible repeated options. Record the failing run before implementation.
- [ ] Write rendered regressions retaining one AccountSetupView across backup selection, cancel and new/recovery enrollment. Assert final request uses the new TOTP and reaches backup codes. Add expiry coverage that hides the old key, prevents completion and makes Start again usable, preserving existing credentials/data. Use existing hosting helpers instead of a second app or debug-auth bypass.
- [ ] Write membership behaviour and rendered tests for an active monthly member attempting a pending or cancelled lifetime purchase. Assert a visible operation outcome and unchanged monthly-only access. Keep signed-out restore reachable and correct the existing stale Account setup navigation-title expectation in Tests/UI/MembershipFlowTests.swift when covering that journey.
- [ ] Implement the narrow state fixes and concise consistently styled setup actions. Keep incomplete-flow secrets private, existing five-minute server expiry intact and normal security/guardian checks unchanged. Avoid changes to unrelated onboarding, exercise counting, audio or Watch behaviour.
- [ ] Run focused red-green tests on the existing shared simulator only when the controller grants its lease. Use serial jobs=2 and scrubbed build environment. Run the relevant Core account/membership checks, affected native suites and compile phone plus Watch. Broaden tests only for new failures or actual concerns. Preserve logs and xcresults on SSD.
- [ ] Self-review, commit only task files and write the task report with exact tests/failures/results, commits and limits. No release upload, deployment, purchases or installation by the implementation agent.

### Task 2: Review and deliver the updated candidate

**Files:** Controller evidence and release version metadata after final functional source is accepted.

**Interfaces:** Consume reviewed native source, accepted build-24 signing/audit patterns and the canonical private phone binding. Produce a new signed candidate and real installation/readback when the phone is reachable.

- [ ] Fresh scoped task review and one final continuation review, resolve actionable findings through the implementation agent.
- [ ] Check current Apple build numbers, use the next unused candidate number and retain existing signatures/capabilities. Freeze inputs, build from scrubbed environment, verify model/audio/resources, phone and Watch signing/profile/entitlement continuity and protected build 17/Vendor hashes.
- [ ] Preserve build 24 and all old artifacts. Perform a bounded data-preserving install only after all new app changes are accepted and phone reachability is confirmed. Report actual version readback separately from TestFlight availability.
- [ ] Refresh accurate reviewer instructions against the final source and actual access constraints. Do not submit public release, create a fake reviewer bypass or claim real membership purchase/MFA acceptance from local tests.

# App Store Membership Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development task-by-task. Steps use checkbox syntax.

**Goal:** Make paid options immediately discoverable and prepare a compatible first App Store submission.

**Architecture:** Reorder the existing account entry rather than adding another paywall. Continue to derive catalogue and access from StoreKit. Controller handles App Store operations independently of the bounded source change.

**Tech Stack:** SwiftUI, XCTest, existing Xcode project and Apple APIs.

**Spec:** docs/superpowers/specs/2026-11-10-app-store-membership-design.md

## Global Constraints

All Binding constraints from the spec apply verbatim. No new worktree. One product writer. No provider writes by source or metadata preparers. Existing completed build25 delivery remains done.

## Review Focus

Signed-out first-launch discoverability without scrolling. A single membership entry with unchanged restoration and support. No account/guardian/entitlement bypass. No fake prices when StoreKit is unavailable. All phone/Watch/test configurations agree with generator1.0(26).

### Task1: Promote membership and prepare version1.0(26)

**Files:** Native/iOS/AccountViews.swift, Tests/UI/MembershipFlowTests.swift and existing hosted account tests only if needed, scripts/generate-project.rb, Spottr.xcodeproj/project.pbxproj.

**Interfaces:** Consume existing AccountWorkspaceCoordinator.membership and MembershipView(store:). Preserve account-membership identifier, normal protected actions and all public store APIs. Produce one visible first-section membership entry and consistent1.0(26)metadata.

- [ ] Change the existing first-launch UI regression to require account-membership exists and isHittable without swiping; retain navigation to Membership, Restore/help visibility, no guest entitlement and no workout access. Run and record RED on the existing simulator after controller lease.
- [ ] Move the existing Membership and help section to the first Form section and use its existing gem/icon pattern. No duplicate entry, hardcoded catalogue, new auth route or public-preview mode.
- [ ] Run the focused UI journey GREEN and any actually affected hosted tests. No broad full-suite repeat without a new failure. Scrub env, jobs2, Swift driver2, backend<=2, serial tests/no clones, SSD artefacts.
- [ ] Update generator plus all eight project configurations to marketing1.0/build26 with a narrow literal edit; preserve UUIDs and every other setting. Self-review, commit only task paths, write report with exact commands/results/limits.

### Task2: Prepare source-backed review metadata

**Files:** This plan workspace only, metadata-readiness-report.md and proposed-store-copy.md. No product/provider files.

**Interfaces:** Consume actual current source and the controller's fresh read-only App Store receipts. Produce draft fields and navigation instructions, privacy/age-rating matrix with source references, screenshot list and explicit unknowns. Current source has mandatory passkey/TOTP, local Health/video/body data, voluntary adult aggregate statistics and protected local guardian profiles.

- [ ] Inspect relevant source/public policy, audio transcripts/manifests and current official Apple guidance. Do not infer clean audio, verified age/guardianship or approved reviewer access without evidence.
- [ ] Draft concise consumer copy with monthlyGBP10, lifetimeGBP200, eligible14daytrial, actual Apple confirmation, renewal and lifetime non-cancellation caveats. No medical efficacy or generative-AI claim. No human portraits.
- [ ] Map collected-versus-on-device data accurately and list proposed age answers with evidence/uncertainty. Explain legitimate reviewer access with required MFA; do not invent credentials or a bypass. Prepare four-to-six real-UI screenshot concepts and exact titles.
- [ ] Write reports for controller inspection. No builds, UI/provider operations, credentials or helpers. Controller will apply only supported facts and resolve actual remaining owner-only facts.

### Task3: Controller delivery and submission

- [ ] Fresh task/source review and one final source review for this small continuation; resolve actionable findings through implementer. Retain all workspaces and evidence.
- [ ] Capture actual updated UI using existing device only when leased; prepare valid, truthful App Store images and review notes. A local rendered catalogue is not proof of live StoreKit retrieval.
- [ ] Build/sign/audit1.0(26) with existing profiles, canonical model/243exactaudio, source freeze, protected-product checks and actual compiler thread limits on SSD. Preserve25andallolderartefacts.
- [ ] Prepare all required editable App Store metadata and matching build. Inspect actual final review validation, including monthly pricing, and repair only evidenced omissions while preserving UK10/month,200lifetime,14dayeligibletrial.
- [ ] Submit the compatible app/purchases/group for review once complete access and required fields are workable, using owner's explicit send instruction. Leave any actual new agreement/security credential/required legal certification for appropriate action-time approval. Hold Apple Support until a corrected review attempt is rejected. Record actual state and blockers honestly; no real charged purchase or automatic public release.


### Task4: Focused account welcome and secure sign-in steps

**Spec:** docs/superpowers/specs/2026-11-10-onboarding-redesign-design.md, Account welcome and shared constraints.
**Files:** Native/iOS/AccountViews.swift and Tests/iOS/AccountRevisionTests.swift (or one focused new hosted test file included in generator/project only if actually needed); Tests/UI/MembershipFlowTests.swift only if direct UI regression needs extension.
**Interfaces:** Consume unchanged NativeAccountStore step/checkpoint/startApple/startEmail/login, coordinator membership and actual AppleAccountButton. Produce a local presentation journey without altering trust, protected actions, expiry or backend request meaning. AccountSetupView initializer remains unchanged. Task1 route/identifier remains stable.

- [ ] Write and run actual RED hosted rendered tests showing first signed-out welcome has Apple/email/passkey/recovery choices but no age/email input, membership is directly reachable, selecting email presents explicit age/role then only email identity input, and Back retains choices. Cover recovery without new checkpoint and no identity network call before enrolment checkpoint.
- [ ] Implement small local presentation state/subviews using existing components. Keep active MFA and trusted creation paths, visible expiry/errors, real cancellation and busy fencing. Preserve account-step/generation/purpose sensitive-input clearing. No new trust gate or auth bypass.
- [ ] Run focused new tests plus affected AccountRevisionTests/AccountFlowTests and MembershipFlowTests under root lease. Inspect ordinary/accessibility screenshots, improve only evidenced clipping. Record commands, actual results and limits; self-review and commit only task paths. Write task-4-report.md.

### Task5: Short visual training setup and compact permissions

**Spec:** docs/superpowers/specs/2026-11-10-onboarding-redesign-design.md, Training setup and shared constraints.
**Files:** Native/iOS/OnboardingView.swift, Native/iOS/PhonePermissionsView.swift, Native/iOS/AnalyticsSettingsView.swift only for compact optional explanatory disclosure, Tests/iOS/SetupRenderedAcceptanceTests.swift or focused new rendered tests and directly affected permission tests. Generator/project only if adding a test file, preserving Task1 version1.0(26) and UUIDs.
**Interfaces:** Preserve OnboardingView initializer, TrainingSetup.Stage/revision3, ProgrammePreferences, candidate/save, age/guardian and existing VoicePreviewCoordinator. Local presentation steps split goals/schedule/support and starting-point/family/review; never alter existing domain validation. Keep setup-health/setup-watch, analytics-usage/analytics-workout, comfortable-* and onboarding-continue identifiers.

- [ ] Write and run actual RED rendered tests for separated goals/schedule/support, Back-retained selections, one comfort family at a time, explicit unsure advancing/review/edit, required completion preventing early save, accessibility layout, and collapsed optional permissions without requesting access. Use real profile/session state and deterministic existing collaborators.
- [ ] Implement visual local steps, compact body/privacy/coach sections and permission rows/disclosures as spec. Main category progress remains six, no profile migration/reset. New visible copy has no colons/semicolons/em dashes. Preserve validation and all junior policy/guardian gates.
- [ ] Run focused new and affected hosted setup/permissions/account tests under root lease; capture actual ordinary/accessibility screenshots of representative pages. No obsolete guest-flow tests or broad repeats without failures. Self-review, commit task paths, write task-5-report.md with commands/results/limits.

**Execution order update:** Task1 and Task2 preparation, task-scoped reviews, Task4, Task5, one final review of all new source, then Task3 build26/provider submission. Do not archive a candidate before the owner's new onboarding changes are incorporated and reviewed.

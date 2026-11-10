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

### Task 1: Promote membership and prepare version1.0(26)

**Files:** Native/iOS/AccountViews.swift, Tests/UI/MembershipFlowTests.swift and existing hosted account tests only if needed, scripts/generate-project.rb, Spottr.xcodeproj/project.pbxproj.

**Interfaces:** Consume existing AccountWorkspaceCoordinator.membership and MembershipView(store:). Preserve account-membership identifier, normal protected actions and all public store APIs. Produce one visible first-section membership entry and consistent1.0(26)metadata.

- [ ] Change the existing first-launch UI regression to require account-membership exists and isHittable without swiping; retain navigation to Membership, Restore/help visibility, no guest entitlement and no workout access. Run and record RED on the existing simulator after controller lease.
- [ ] Move the existing Membership and help section to the first Form section and use its existing gem/icon pattern. No duplicate entry, hardcoded catalogue, new auth route or public-preview mode.
- [ ] Run the focused UI journey GREEN and any actually affected hosted tests. No broad full-suite repeat without a new failure. Scrub env, jobs2, Swift driver2, backend<=2, serial tests/no clones, SSD artefacts.
- [ ] Update generator plus all eight project configurations to marketing1.0/build26 with a narrow literal edit; preserve UUIDs and every other setting. Self-review, commit only task paths, write report with exact commands/results/limits.

### Task 2: Prepare source-backed review metadata

**Files:** This plan workspace only, metadata-readiness-report.md and proposed-store-copy.md. No product/provider files.

**Interfaces:** Consume actual current source and the controller's fresh read-only App Store receipts. Produce draft fields and navigation instructions, privacy/age-rating matrix with source references, screenshot list and explicit unknowns. Current source has mandatory passkey/TOTP, local Health/video/body data, voluntary adult aggregate statistics and protected local guardian profiles.

- [ ] Inspect relevant source/public policy, audio transcripts/manifests and current official Apple guidance. Do not infer clean audio, verified age/guardianship or approved reviewer access without evidence.
- [ ] Draft concise consumer copy with monthlyGBP10, lifetimeGBP200, eligible14daytrial, actual Apple confirmation, renewal and lifetime non-cancellation caveats. No medical efficacy or generative-AI claim. No human portraits.
- [ ] Map collected-versus-on-device data accurately and list proposed age answers with evidence/uncertainty. Explain legitimate reviewer access with required MFA; do not invent credentials or a bypass. Prepare four-to-six real-UI screenshot concepts and exact titles.
- [ ] Write reports for controller inspection. No builds, UI/provider operations, credentials or helpers. Controller will apply only supported facts and resolve actual remaining owner-only facts.

### Task 3: Controller delivery and submission

- [ ] Fresh task/source review and one final source review for this small continuation; resolve actionable findings through implementer. Retain all workspaces and evidence.
- [ ] Capture actual updated UI using existing device only when leased; prepare valid, truthful App Store images and review notes. A local rendered catalogue is not proof of live StoreKit retrieval.
- [ ] Build/sign/audit1.0(26) with existing profiles, canonical model/243exactaudio, source freeze, protected-product checks and actual compiler thread limits on SSD. Preserve25andallolderartefacts.
- [ ] Prepare all required editable App Store metadata and matching build. Inspect actual final review validation, including monthly pricing, and repair only evidenced omissions while preserving UK10/month,200lifetime,14dayeligibletrial.
- [ ] Submit the compatible app/purchases/group for review once complete access and required fields are workable, using owner's explicit send instruction. Leave any actual new agreement/security credential/required legal certification for appropriate action-time approval. Hold Apple Support until a corrected review attempt is rejected. Record actual state and blockers honestly; no real charged purchase or automatic public release.


### Task 4: Focused account welcome and secure sign-in steps

**Spec:** docs/superpowers/specs/2026-11-10-onboarding-redesign-design.md, Account welcome and shared constraints.
**Files:** Native/iOS/AccountViews.swift and Tests/iOS/AccountRevisionTests.swift (or one focused new hosted test file included in generator/project only if actually needed); Tests/UI/MembershipFlowTests.swift only if direct UI regression needs extension.
**Interfaces:** Consume unchanged NativeAccountStore step/checkpoint/startApple/startEmail/login, coordinator membership and actual AppleAccountButton. Produce a local presentation journey without altering trust, protected actions, expiry or backend request meaning. AccountSetupView initializer remains unchanged. Task1 route/identifier remains stable.

- [ ] Write and run actual RED hosted rendered tests showing first signed-out welcome has Apple/email/passkey/recovery choices but no age/email input, membership is directly reachable, selecting email presents explicit age/role then only email identity input, and Back retains choices. Cover recovery without new checkpoint and no identity network call before enrolment checkpoint.
- [ ] Implement small local presentation state/subviews using existing components. Keep active MFA and trusted creation paths, visible expiry/errors, real cancellation and busy fencing. Preserve account-step/generation/purpose sensitive-input clearing. No new trust gate or auth bypass.
- [ ] Run focused new tests plus affected AccountRevisionTests/AccountFlowTests and MembershipFlowTests under root lease. Inspect ordinary/accessibility screenshots, improve only evidenced clipping. Record commands, actual results and limits; self-review and commit only task paths. Write task-4-report.md.

### Task 5: Short visual training setup and compact permissions

**Spec:** docs/superpowers/specs/2026-11-10-onboarding-redesign-design.md, Training setup and shared constraints.
**Files:** Native/iOS/OnboardingView.swift, Native/iOS/PhonePermissionsView.swift, Native/iOS/AnalyticsSettingsView.swift only for compact optional explanatory disclosure, Tests/iOS/SetupRenderedAcceptanceTests.swift or focused new rendered tests and directly affected permission tests. Generator/project only if adding a test file, preserving Task1 version1.0(26) and UUIDs.
**Interfaces:** Preserve OnboardingView initializer, TrainingSetup.Stage/revision3, ProgrammePreferences, candidate/save, age/guardian and existing VoicePreviewCoordinator. Local presentation steps split goals/schedule/support and starting-point/family/review; never alter existing domain validation. Keep setup-health/setup-watch, analytics-usage/analytics-workout, comfortable-* and onboarding-continue identifiers.

- [ ] Write and run actual RED tests for separated goals/schedule/support, Back-retained selections, one comfort family at a time, explicit unsure advancing/review/edit, and required completion preventing early save. Prefer a small production-used presentation value model within OnboardingView.swift for deterministic navigation tests if hosted private SwiftUI AX interaction is brittle, with real rendered stage/accessibility captures for layout. Add collapsed-permissions/no-request behavior tests using real profile/session state and deterministic existing collaborators. No duplicated test-only navigation implementation, shipping test launch branch or account bypass.
- [ ] Implement visual local steps, the normal-size four-column starting-point choices with accessible fallback, compact body/privacy/coach sections and permission rows/disclosures as spec. Main category progress remains six, no profile migration/reset. New visible copy has no colons/semicolons/em dashes. Preserve validation and all junior policy/guardian gates.
- [ ] Run focused new and affected hosted setup/permissions/account tests under root lease; capture actual ordinary/accessibility screenshots of representative pages. No obsolete guest-flow tests or broad repeats without failures. Self-review, commit task paths, write task-5-report.md with commands/results/limits.

**Execution order update:** Task1 and Task2 preparation, task-scoped reviews, Task4, Task5, one final review of all new source, then Task3 build26/provider submission. Do not archive a candidate before the owner's new onboarding changes are incorporated and reviewed.

### Task 6: Align source and packaged privacy declarations

**Spec:** docs/superpowers/specs/2026-11-10-privacy-alignment-design.md, backed by workspace privacy-final-answers-addendum.md.
**Files:** Native/iOS/PrivacyInfo.xcprivacy, landing/tests-public/native-service-contract.test.mjs, Tests/iOS/ReleasePackagingTests.swift only.
**Interfaces:** Apple's real plist data-type/purpose constants; source and actual packaged manifest parser. Preserve existing entitlement/scheme contracts and Watch API reason checks. No data-path or UI behavior changes.

- [ ] Update existing Node native-service contract tests first to parse actual plist and assert the exact six types, linked/no-tracking flags and per-type purpose sets. Run actual RED against current five-type/two-Fitness-purpose manifest; record missing CustomerSupport and Fitness Personalization failures independently.
- [ ] Make the two narrow manifest additions from spec, preserving other purposes/API reasons. Correct the stale hosted helper and host test to validate API reasons plus real collection declarations rather than forbidding them; retain Watch expectations and no unsupported broad skips.
- [ ] Run focused Node contract GREEN and plutil lint. Run only affected hosted packaging-resource test under controller native lease if needed to verify actual bundled plist, not all native suites; jobs1/driver1/backend1/serial/exactBF27/SSD/scrubbed environment. Record actual counts/limits, self-review, commit exactly task paths and write task-6-report.md.

**Final order:** Complete/reviewTask5, then Task6/review, then one final review of all new source since8b48ea7, then Task3 freeze/sign/audit/upload/install and supported App Store UI submission. Keep1.0(26), preserve all old products, hold Support until corrected review rejection.

### Task 7: Repair captured-view evidence for App Store screenshots

**Spec:** docs/superpowers/specs/2026-11-10-app-store-screenshot-evidence.md
**Files:** existing CoachPolishRenderedTests.swift, ProgrammeRenderedTests.swift and QuestRenderedTests.swift only.

- [ ] Inspect retained actual failed phone capture run and attached pixels, identify why AX assertions disagree with production view rendering. No assumed lifecycle fix before evidence.
- [ ] Correct only meaningful view-evidence checks using existing actual pixel/OCR or properly owned host boundaries. Preserve assertion semantics, isolated profiles and ordinary production UI. No shipping source or bypass changes.
- [ ] Under controller lease, focused phone and required existing iPad capture runs, then fresh review. Document sample-data and hardware limits, retain original images and all failed evidence. Confirm functional26sources/inputsunchanged before provider use. Controller owns Watch captures and App Store work.

### Task 8: Retire celebrity coach packs for the App Store build

**Spec:** Owner's 10 November answer to the content-rights question, "remove goggins and arnold for now". This supersedes previous preservation of these voices in the shipping app. Historical evidence and old builds remain preserved.
**Files:** Native/iOS voice selection/playback/preview and TrainingStore consumers, Shared/Core voice selection/rep model if necessary, directly affected Tests/iOS and Tests/Core voice tests, Native/Resources/DemoVoice/{arnold,arnold-reps,goggins-reps}, scripts/generate-project.rb and Spottr.xcodeproj/project.pbxproj for matching1.0(27). Current landing/public only if it actually exposes these coaches. No unrelated product or service changes.
**Interfaces:** Preserve ordinary VoicePlayback/VoiceCue lifecycle and the session coordinator's priority/finish/cancellation behavior, all completed workout state, Maya/Leo MP3 bytes, optional voice feedback and clear form/stop guidance. Public selectable coaching voices are Maya, Leo and Local voice only. Legacy persisted trainer.voice values arnold/david/goggins must safely resolve to Maya and be normalised when preferences load. No legacy value may access a removed recording or remote imitation. Preserve explicit off choices. Rep counting remains optional; if natural count recordings are unavailable, explicitly label any opt-in device-voice counting and do not silently enable it on migration.

- [ ] Write meaningful failing tests for the selectable catalogue, legacy voice load/reload migration without resetting programme/history, explicit voice-off state, preview/workout playback and actual package exclusion. Record RED before product changes. Keep tests of supported line finish, tracking gaps, priority, expiry and safety behavior; migrate tests for deliberately removed features to remaining supported behavior instead of preserving a hidden celebrity runtime. Do not add test skips or fake entitlements.
- [ ] Before removing resource files, copy precisely the three retired folders to a dedicated SSD preservation directory, write relative-path/size/SHA256 manifest, independently verify every copied file and record the receipt. Git history/old signed products/evidence remain untouched. Do not delete any unrelated files or worktrees.
- [ ] Remove celebrity choices, user-visible celebrity copy, playable audio and production resource references. Prefer removing obsolete paths/cases, retaining only raw persisted-string migration where needed. Keep non-celebrity coaching/tone previews and their natural offline audio. Optional rep counts may use clearly labelled device voice with default off for new/legacy celebrity counter choices; no paid generation, runtime provider or robot-voice substitution for Maya/Leo coaching. Preserve existing voice interruption/finish arbitration.
- [ ] Run focused Core and native voice suites, affected existing setup/packaging tests under controller-granted native lease. Actual jobs1/driver1/backend1, both parallel WMO flagsNO, serial exact existing BF27, no clones/new devices/reset/erase/uninstall. SSD all outputs. No native command until root grants slot. Use approved existing SSD DerivedData if compatible. Report exact RED/GREEN commands, captures and bounded acceptance. Only broaden tests for amended-code failures or identified concerns.
- [ ] Narrowly bump generator and all eight target configurations to1.0(27), preserving UUIDs, identifiers, profiles/entitlements, canonical model and all other settings. Self-review and commit only owned paths. Full report in this plan workspace task-8-report.md; controller performs independent fresh task/final review and delivery.

### Task 9: Controller replacement delivery and review submission

- [ ] Review Task8 spec and quality, then final release delta against accepted26. Do not reuse build26's all243-audio assertion for the intentionally reduced new bundle. Verify every Maya/Leo clip exactly, no retired voice folders/assets, canonical model and privacy manifests, account/StoreKit and Watch entitlements unchanged, old17/26/dependencies preserved.
- [ ] Archive/export/validate/install/upload1.0(27) on SSD under shared leases and serial compiler caps. Snapshot source/hash before signed build; preserve old products and reconcile uncertain upload outcomes rather than duplicate reservations. Verify exact physical version if reachable and Apple processing. Assign matching27 to draft, preserve manual public release and current privacy/age answers unless content changes require a truthful update.
- [ ] Recheck real App Store screenshots against unchanged view content, update reviewer instructions if needed, finish actual supported first-app plus monthly/lifetime selection. Use Safari after Musalli releases. Resolve evidence-backed metadata omissions; preserve £10 monthly, eligible14daytrial and £200 lifetime. Explicit owner submission instruction remains valid. Declare content rights only against remaining source-backed artwork/audio licenses, no automatic certification from deletion alone. Keep MediaPipe distribution concern explicit; hold Support until corrected rejection.

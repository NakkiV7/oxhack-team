# Calmer native onboarding

The owner wants less text, clearer choices and a polished welcome rather than long forms. This extends the authorised build26 before archiving/submitting it. Existing sign-in, account policy, billing and stored profile semantics remain authoritative.

## Reference and design choices

Research checked10November2026. Nike Training Club's UK App Store listing shows4.8from56k ratings. Fitbod's US listing shows4.8from289k ratings. Their listings support visual exercise guidance and a clear training plan; Fitbod's own getting-started guide describes focused experience, goal and equipment questions. These are product principles, not evidence of their current installed authentication/onboarding screens. Do not copy faces, branding, AI services or a long sales quiz.

Sources
- https://apps.apple.com/gb/app/nike-training-club/id301521403
- https://apps.apple.com/us/app/fitbod-gym-fitness-planner/id1041517543?ls=1
- https://help.fitbod.me/hc/en-us/articles/30721771750039-Getting-Started-with-Fitbod-A-New-User-s-Guide
- https://developer.apple.com/design/human-interface-guidelines/onboarding
- https://developer.apple.com/design/human-interface-guidelines/sign-in-with-apple

Controller choices delegated by owner: keep native SwiftUI and current design components, split long stages into local presentation steps instead of changing persisted profile schema, and show secondary information through disclosures. No new service or dependency.

## Account welcome

On first signed-out identity stage show a faceless MovementDemonstration, heading `Move at your own pace`, one supporting sentence, the native Apple button as primary action, a clearly styled secondary `Continue with email` button and a compact outlined `Sign in with passkey` returning-user action. Email fields, create/recover picker, age fields and retained-data explanations must not all appear on this first welcome.

The compact real `Membership & Apple purchases` route remains visible without scrolling at ordinary Dynamic Type and keeps `account-membership`. It can occupy the first section as specified by Task1. Keep Restore/help reachable and purchases protected. Support and retained local records belong in an `Account help and saved data` disclosure, except the membership route remains directly visible.

Selecting Apple or email begins a focused age/role checkpoint for NEW enrolment before any remote identity request. This uses existing `setCheckpoint(ageYears:role:)`, retains explicit guardian choice and validation, and only then shows the selected Apple or email identity action. The Apple button still uses the real AppleAccountButton and native Apple authorisation. Existing checkpoint may be reused if valid in this same attempt; do not erase an in-flight setup or a paused workout by navigating presentation pages. Returning-user passkey sign-in and account recovery must remain separately discoverable without needing new enrolment age first; recovery still requires existing linked identity, backup and real MFA. A visible `Recover account` action reveals purpose and chosen identity route. Back returns to presentation choices without calling cancellation or mutating auth state; actual Cancel setup keeps its existing cancellation meaning.

When account.step is emailCode, passkey, recoveryBackup, authenticatorSetup, secondFactor or restart, show only that existing active task, concise step-specific heading, required inputs and relevant help. Never display welcome over active setup. Keep expiry/retry/error feedback visible, and clear sensitive fields on the existing step/generation/purpose changes. Busy states prevent duplicate actions. Trusted profile creation and backup-code handling remain functionally unchanged. Security details can collapse, but authenticator seed and backup instructions must appear when needed. No fake account, guest access or hidden reviewer bypass.

## Training setup

Keep TrainingSetup.Stage and revision3 unchanged. The main six-step progress is an honest category indicator; short local steps may additionally name their context. The sticky Continue and Back remain accessible. Preserve edits across Back, all current validation and candidate/save semantics. Optional permissions/coach Skip must retain current meaning.

Privacy shows independent optional choices off by default, each with one-line context. Put detailed sharing explanations in a disclosure. Privacy policy remains directly available. Junior collection policy unchanged.

Body shows the shared faceless MovementDemonstration and compact name/measurement card. Adult measurements required; junior optional guardian-protected measurements and no adult BMI/weight-loss policy unchanged. Move nonessential age/policy paragraphs to a `Profile details` disclosure, keeping required errors immediate.

Replace the long Goals and rhythm page with three local steps: `What would you like to work on?`, `When would you like to practise?`, `What support is available?`. Goals use consistent icon cards with a two-column layout at ordinary sizes and single-column at accessibility sizes. Schedule shows selectable weekdays and compact duration/time controls. Support/floor choice lives on its own page. Continue validates goals before schedule and at least one day before support. Back retraces these pages without losing selections.

Comfort begins with the four-position starting-point control and matching faceless artwork. Use a four-column choice row at ordinary sizes, as the owner requested, with a vertical accessible fallback rather than truncating large text. After Continue, show only one exercise family with its first three permitted variations, proper `Not sure yet` ChoiceCard and `More variations`. Selecting an answer advances to the next unanswered family, preserving all selections. Show family progress and a review/change control for already answered families, so an accidental selection is reversible. After the last answer show a compact answered summary with change controls and Continue. Never award reps or XP for these choices. Under-five supervised play route remains intact. Continue validates each required answer before saving; no hidden family can make completion impossible.

Permissions show compact icon rows for camera, Health and Watch with accurate status and actions. Additional microphone, on-device speech and reminder options go in a labelled `Voice logging and reminders` disclosure, initially closed. Their denied/restricted/granted status and action remain reachable. No permission request on mere render/expand and no blanket consent. Junior Health/guardian website rules unchanged. Manual logging is always described concisely as available if access is declined.

Coach keeps abstract colour/waveform cards, existing previews/tone selection and audio toggle. Show next practice and a compact seven-day visual summary; place the full exercise list/week details in `View my week`. Preserve accessible text alternatives and no autoplay outside user selection. Audio selection lifecycle remains existing coordinator-owned.

## Visual and accessibility rules

Reuse Palette, ChoiceCard, SpottrPressStyle, PrimaryButton and MovementDemonstration. No human-style faces or bitmap portraits. Min44pt controls, responsive spacing, semantic headings/labels, focus after errors/family advance, no fixed-height containers that clip accessibility text. Subtle transitions and selection haptics; Reduce Motion turns transitions off. No colons, semicolons or em dashes in new visible descriptive copy. Secondary actions remain recognisable controls, not plain unstyled text.

## Verification and boundaries

Write and observe meaningful failing tests before product edits per /Users/scsoc/.claude/TDD.md. Rendered hosted tests may mount real views with deterministic existing collaborators; no shipping fixture/bypass. Test first welcome separation, chosen route and checkpoint, recovery/passkey availability, active MFA continuity, local step Back retention, single-family answer/review and completion, junior policy and accessibility-size visibility. Run focused affected account/setup/permission tests once green and inspect real screenshots on the existing shared simulator under controller lease. Update obsolete assumptions only when directly affected, never activate known obsolete guest tests. Keep the Task1 no-scroll Membership regression passing.

No new simulator/runtime, resets, erases or uninstall. SSD build/log artifacts only. One product writer at a time. Scrubbed build environment, jobs2, Swift driver2/backend<=2, serial no clones. Preserve all evidence, old builds, exact243MP3s, canonical model and dependencies. No provider writes or build26 archiving until these tasks are reviewed. The App Store metadata/reviewer navigation must describe the final screens.

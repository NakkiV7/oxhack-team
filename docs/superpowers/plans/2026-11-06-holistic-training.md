# Holistic training implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task by task. Steps use checkbox syntax. Continue the already-authorised execution workflow without routine confirmation pauses.

**Goal:** Turn Spottr into a useful account-backed personal training programme with coherent phone/Watch execution, membership, progression and evidence-based reports.

**Architecture:** Keep movement/counter/audio engines intact and build a shared deterministic programme, curriculum and set-effort domain around configured workouts. Extend the existing Cloudflare identity service for native Apple/email MFA and persistent device sessions. Route every workout launch through one account/setup/membership coordinator, and use an account-scoped durable Watch journal for offline sessions.

**Tech stack:** Existing SwiftUI/Observation, AuthenticationServices, Security/Keychain, StoreKit 2, HealthKit, WatchConnectivity, UserNotifications, Swift Testing/XCTest, Cloudflare Workers/D1, TypeScript/Zod/SimpleWebAuthn and the existing native pose SDK/model.

**Spec:** `docs/superpowers/specs/2026-11-06-holistic-training-design.md`.

## Global constraints

- Baseline `a115f05476e0b04093af098806948b7e729f28f2`, existing `codex/spottr-demo-consolidation` checkout, preserve original untracked evidence. No new worktree.
- All bulk outputs on Extreme SSD-backed development storage. Inspect available capacity before implementation builds; add capacity without deleting evidence. Preserve build17/Vendor metadata and all older releases.
- Existing simulator `BF27AFBA-FF1E-4484-A3BD-42916CEB1170` only, no clones/erase/create. NAKU currently has priority for its release; coordinate before testing. No Chrome. Two build/test jobs, native operations serial.
- TDD `/Users/scsoc/.claude/TDD.md`. Do not modify pose thresholds/models or speech-completion semantics to accommodate a UI test. No runtime generative AI or paid service upgrade.
- Faceless stickman/joints and abstract coach art. Consistent icons, proper choice controls, blue underlined external links and complete natural descriptive copy without colon/semicolon/em-dash/centred-dot prose.
- Native account/setup and verified membership required for new workouts; no old full-beta-access bypass. Restore/history/export/help/privacy/deletion remain accessible. No fabricated purchases, data, consent, permission or sensor status.
- Confirmed user steering supports all ages and a separate opt-in for adult aggregate workout statistics. Under-18s use local guardian-managed profiles; unknown age is not adult. Required adult height/weight and applicable BMI, optional junior measurements without adult bands. OS permissions and analytics consent remain voluntary.
- Watch starts may use a cached trusted grant up to 30 days and never beyond verified subscription/trial/grace expiry. Expiry never deletes/stops already-earned ongoing work.
- Lost-passkey recovery requires linked verified Apple/email plus unused backup code, then replacement passkey/TOTP/backup enrolment; no single-factor/support bypass.
- Preserve old JSON and earned progress. New results retain actual camera/manual/mixed origin, real observed time and account ownership. No cloud upload of workout logs, effort, body measurements or Health readings in this plan.
- Serial implementers and fresh per-task reviews. Root coordinates and prepares operational evidence, not product fixes. Never cleanup the ignored evidence workspace at the end.

## Review focus

1. Interrupted/expired/concurrent authentication, provider linking and lost-passkey recovery must never establish a partial session or invalidate usable old credentials prematurely; tests in Tasks 2 and 3.
2. A delayed purchase/auth response, Watch command or alternate Start button must not launch a stale/different workout, bypass membership, or reset active work; tests in Tasks 4, 6 and 8.
3. Account changes, offline Watch journals and repeated sync must not leak, lose, duplicate history/XP or mislabel manual work as camera observation; tests in Tasks 3, 7 and 8.
4. Unknown ability, unavailable support, rest days, DST/leap/week53 and existing earned evidence must produce reachable plans/progression/reminders rather than hard exercise bottlenecks or invented observations; tests in Tasks 1 and 7.
5. Denied permissions, stale Health/HR, unavailable StoreKit/mail/network and app restarts must preserve usable manual training or a truthful recoverable gate, never a fake success; tests in Tasks 3–6 and 8–10.

---

### Task 1: Shared personal programme, profile and effort domain

**Files:** create `Shared/Core/TrainingProgramme.swift`, `Shared/Core/SkillCurriculum.swift`, `Shared/Core/SetEffort.swift`; modify `Shared/Core/LocalProfile.swift`, `Shared/Core/LoggedWorkout.swift`, the `SessionRecord` definition, and only necessary legacy adapters; tests `Tests/Core/TrainingProgrammeTests.swift`, `SkillCurriculumTests.swift`, `ProfileBehaviorTests.swift`, `ConfigurableSessionTests.swift`.

**Interfaces:** Produce `TrainingGoal` with strength/stamina/mobility/balance/weightManagement and `TrainingStartingPoint` with startingOut/somePractice/regularPractice/experienced. `ProgrammePreferences` is Codable/Equatable/Sendable with goals, ISO weekdays (Monday=1 through Sunday=7), duration choice 10/20/30/45 minutes, preferred local hour 0...23, available catalogue support strings, floor-work choice, excluded exercise IDs, starting point and optional `TrainingAgeContext` (0...120 years, guardian-managed required under18). Missing legacy age decodes as unknown and requires setup before a new personal programme. Add an optional preferences field to `LocalProfile`, retaining legacy goals/baseline/weight flag decoding and projections without changing `TrainingAttribute` semantics. Expose age-aware BMI assessment instead of applying old adult categories to minors. `ProgrammePlanner.makeWeek(profile:history:start:calendar:) throws -> TrainingProgramme`; days include workout/rest/recovery/familyMovement, stable local day/plan IDs and existing `CoachSavedPlan` items. Under5 familyMovement has no formal plan. Junior default restrictions follow the updated spec and Task1 brief. `SetEffort` raw values 2/4/6/8/10; optional `LoggedSet.effort` and `SessionRecord.plannedWorkoutID`.

- [ ] Write public behaviour tests for all five goals including weight-only/balance, legacy profiles/records, four starting states, required valid measurements/applicable BMI band boundaries and unclipped marker positions for extremes.
- [ ] Write planner tests for 1/3/7 chosen days, recovery within seven-day activity schedules, equipment/exclusions/unknown ability, varied families, no BMI-only hard progression, stable IDs, actual effort adaptation, timezones/DST and no mutation of an active/completed plan.
- [ ] Write curriculum tests for exact 53-ID coverage/order from the spec, existing levels/earned evidence, own-family alternative unlocking, unsupported nodes not blocking other families, placement without XP and manual/camera distinctions.
- [ ] Write age-boundary tests 0/4/5/12/13/17/18/120, unknown legacy age, guardian requirement, family-play versus structured plans, no junior overload/weight-loss logic, no adult BMI/analytics/Health/cloud/timed-XP flags for children, and no BMI under2.
- [ ] Run focused tests red; implement the smallest shared domain and adapters; run focused/full Core and commit. New domain types stay independent of UI/auth services and contain no network or AI calls.

### Task 2: Native identity, recovery and persistent-session backend

**Files:** create focused `web/src/native-auth.ts`, `identity.ts`, `native-sessions.ts`, `mail.ts`, `account-plans.ts`; additive `web/migrations/0002_native_accounts.sql`; modify shared auth helpers/index routing only as needed; `web/test/native-auth.test.ts`, `native-sessions.test.ts`, `account-plans.test.ts` and legacy auth tests.

**Interfaces:** Strict versioned `/api/native/v1` contracts for Apple/email bootstrap, passkey enrol/assertion, TOTP/backup completion, explicit recovery, access/refresh rotation, revoke/sign-out/delete, and account-scoped plan preferences. Document exact request/response schemas in `web/docs/native-auth-contract.md` for Task 3. Apple/email proof is bound to one-time challenge and account/provider subject. Return a fully MFA-complete account/device session only at final completion. Access lifetime 15 minutes; rotating device-bound refresh lease 180 days with rolling renewal. Device proof uses standard P-256 signatures; never invent crypto or accept a user ID supplied as authority. Cloud plan sync includes preferences/programmes only, under explicit consent and revision checks. Legacy website passkey/TOTP routes remain compatible.

- [ ] Add failing actual WebAuthn/D1 tests for origin/RP/UV/signature/nonce/audience/expiry, provider-email linking conflicts, enumeration resistance, unknown fields/body limits/rate limits, five-attempt bounded codes and one-time consumption.
- [ ] Add concurrent/restart/ambiguous retry tests for refresh rotation, old device revocation, deleted accounts, expired partial enrolment, abandoned recovery, atomic replacement and cross-account reads/writes.
- [ ] Add fake-mail tests for verified email ownership, delivery failure, quotas, no debug OTP leakage, no Health content, and no paid overflow. Resend uses a server-only configured key; missing live configuration fails closed.
- [ ] Implement additive schema/services and publish exact native contracts. Run web tests/typecheck and existing account-client tests; inspect SQL migration/rollback requirements and commit. Do not deploy or send real mail from test code. Root prepares owner-controlled provider/key configuration independently.

### Task 3: Native account/MFA and account-safe local persistence

**Files:** create `Native/iOS/AccountStore.swift`, `AccountClient.swift`, `AccountViews.swift`, `SecureAccountCredentials.swift`, `AccountDataScope.swift`; appropriate shared account/access value types; extend Profile/settings data actions and app wiring; tests `Tests/iOS/AccountFlowTests.swift`, `AccountPersistenceTests.swift`, Core account-policy tests.

**Interfaces:** Consume Task 2 exact schemas. `AccountStore` publishes signed-out/pending-MFA/trusted-online/trusted-offline/revoked/error states and a stable account ID only after full MFA. Keychain owns private device key/refresh credentials, with single-flight refresh and no destructive logout on network failure. Production uses native Apple and passkey request adapters; fake providers exist only by injected test dependencies, not a release launch-argument bypass. Introduce stable local training-profile IDs beneath account namespaces, including guardian-managed junior profiles; children do not need their own online email/account. Account/profile migration preserves guest/local data and requires explicit import choice; sign-out/switch/delete must not discard ongoing sets or another subject's pending journal. Produce reusable account setup view, protected guardian controls and profile completion state for later onboarding.

- [ ] Write red tests for actual callback/token/challenge mapping, UV/native credential failures, incomplete MFA, restart/offline token restoration, concurrent requests, revocation and source-account isolation.
- [ ] Write red migration tests preserving existing history/profile/rewards, alternate-account isolation and explicit old-device import without synthetic workouts/XP.
- [ ] Test adult/junior profile switching and parental gates, no silent assignment of old adult history to a child, no cross-profile Health cache or pending journal leakage, and no child provider/measurement data sent to account service.
- [ ] Implement native AuthenticationServices/Keychain/URLSession adapters, visible recovery/deletion/export and staged setup UI. Reuse platform secure input/autofill and never log codes/keys/tokens.
- [ ] Run covering Core/native checks and compile the phone target; commit. Live associated-domain/provider configuration is a separate acceptance step in Task 10, not a claimed result from mocks.

### Task 4: Verified membership paywall and one workout-launch gate

**Files:** `Shared/Core/MembershipCoordinator.swift`, new `WorkoutAccessPolicy.swift`, `Native/iOS/MembershipStore.swift`, `MembershipView.swift`, new `WorkoutLaunchCoordinator.swift`, app/TrainingStore command wiring and all launch-call sites; `Tests/Core/MembershipJourneyTests.swift`, new launch-policy tests, `Tests/iOS/MembershipStoreKitTests.swift`, relevant native/UI membership tests.

**Interfaces:** `WorkoutAccessPolicy` decides requiresAccount/requiresSetup/requiresMembership/resumeExisting/start from trusted identity, setup, current verified membership and active work. `WorkoutLaunchCoordinator.request(plan:origin:)` holds a cancellable pending intent and is the sole consumer UI/Watch/deep-link start route. Existing pure workout/counter models remain testable independently. Membership uses actual products/eligibility, verified transactions and updates; new purchases carry the account attribution token. Restore is always reachable. Preserve explicit verified legacy purchase restore and no access for pending/cancelled/unverified results.

- [ ] Add red tests enumerating Today/Skills/Coach/library/quest/Watch/URL starts, stale delayed purchase/auth callbacks, switching account and resuming active work without resetting quantities or re-paywalling a set.
- [ ] Add paywall UI states for actual monthly/lifetime products, eligible 14-day trial, expired/revoked/grace access, restore, failed product loading/retry and overlap. Remove the old optional/full-beta-access promise and bypass.
- [ ] Diagnose four existing StoreKit `notEntitled` tests using the existing simulator/scheme and supported signing/configuration. Retain explicit limits if the platform still refuses; do not weaken entitlement verification or present those tests as passing.
- [ ] Build a centred polished loading/error/selection surface, native offer-code redemption and consistent legal links. Run affected tests, build and commit. Never execute a real charged purchase for testing.

### Task 5: Coherent onboarding, measurements and permissions UI

**Files:** `Native/iOS/OnboardingView.swift`, `Components.swift`, `ProfileSettingsView.swift`, `MeasurementsSettingsView.swift`, `WatchSetupView.swift`, `AppleWatchSetupStore.swift`, `HealthDataStore.swift`, goal/profile helpers; new reusable goal-choice/external-link/haptic/permission components; relevant Profile/Health/Onboarding UI/native tests.

**Interfaces:** Consume account stage, `ProgrammePreferences`, membership routing and existing Health/Watch APIs. Setup revision advances while preserving all existing data. Six stages and Skip rules follow the spec. One goal picker includes all five goals; one four-stop starting selector controls the changing icon. All six exercise families get adaptive comfort choices, a proper unsure card and accessible auto-advance. Required measurements are confirmed values, not defaults; BMI is a band rail with circular marker and optional detail.

- [ ] Write red tests for header progress/Skip, missing adult account/height/weight, unit conversion, age-aware/non-applicable BMI, legacy profile migration, balanced goal icons, weight-only selection and correct unsure/auto-next behaviour. Junior setup uses guardian-only optional measurements, growth context/NHS child calculator and no adult BMI rail or guardian Health autofill.
- [ ] Write permission-state tests for request completion versus observed Health data, no-readings versus unavailable, actual Watch install/handshake, selected model versus real capabilities, denied camera/mic/notifications and phone-only completion.
- [ ] Implement visual stage/card components, move Watch/Health setup into Profile, remove guest/no-account/no-faces lines and old special toggle/plaintext actions. Request relevant permissions within onboarding, with explicit per-device Watch steps.
- [ ] Add restrained haptics and accessible complete copy/website-link styling. Run targeted native/UI checks and actual phone-sized renders on the coordinated existing simulator; inspect screenshots before accepting and commit.

### Task 6: Whole-workout Today, set effort and useful Insights

**Files:** new `Native/iOS/ProgrammeStore.swift`, programme/session overview views, `HomeViews.swift`, `TrainingStore.swift`, `ConfiguredSessionViews.swift`, session/report/Insights helpers, account programme client/store; new programme journey/effort/report tests and selected UI tests.

**Interfaces:** Persist Task 1 programmes by account, local date/timezone/revision; use Task 4 launch gate and existing `ConfigurableSession`. Record `plannedWorkoutID` and optional `SetEffort` through actual set saves. Expose today's workout/recovery, future safe edits and actual planned/completed/effort history to Coach and Watch. Cloud sync stores only consented plan/preferences and uses Task 2 account ownership/revision contracts; workout/Health records remain local.

- [ ] Write red tests for a multi-exercise day from onboarding, recovery day, repeated Today visits/stable plan, future-only edits, actual effort recording/unknown effort, no target-as-achieved and history-source fidelity.
- [ ] Write source/pause/input/coach/reconnect regressions preserving reps, observed seconds, set indexes and audio completion through the new views. Add perceived-effort trend and actual dated weight entry/report tests without invented values.
- [ ] Replace isolated squat/push-up home controls with a full session preview/week ribbon and coherent camera/manual workout screen with the stick figure always useful. Set saving starts rest; rest prepares the next set with haptics but does not silently award observation or force a camera start.
- [ ] Keep history/export/help available beyond entitlement expiry. Run covering Core/native/selected UI and inspect actual populated/empty/rest/manual/camera renders; commit.
- [ ] Keep profile/age context captured at workout start and preserved through completion/import. FamilyMovement days show guardian play ideas rather than fictional sets. Junior profiles do not receive adult weight-loss advice, Health-store values or adult age-estimated HR zones.

### Task 7: One combined skill map, rewards and a year of quests

**Files:** new `Shared/Core/QuestCalendar.swift`, `Resources/quest-calendar.json`, generator/validation script, `Native/iOS/TrainingPathViews.swift`, `SkillsViews.swift`, `GamificationViews.swift`, `NativeRewardsStore.swift`, new quest/reminder/widget views; shared gamification/curriculum integration; `Tests/Core/QuestCalendarTests.swift`, rewards/progression native/UI tests.

**Interfaces:** Task 1 exact 53-node chapter order and source-aware evidence, Task 6 actual records and launch route. Bundle 366 daily slots with three options and 53 weekly slots with two options; no runtime AI. `QuestProgress` consumes actual record/check-in evidence, produces stable idempotent reward claims. Shared notification schedule values provide absolute before/start dates for the chosen `DailyXPWindow`; native UserNotifications schedules a bounded rolling set under 64 pending requests.

- [ ] Add failing 53-ID/level/order/own-family unlock/old-earned migration and no arbitrary bottleneck tests. Check green completed connector presentation and jump-to-current/compact later chapters.
- [ ] Add year/leap/week53/DST/rest-day/unsuitable-quest tests, manual versus camera-only evidence, duplicate Watch import/claim, deletion/reward reconciliation and freeze/double-XP changes.
- [ ] Add actual one-hour-before/start scheduling tests, consent denied, changed schedule/timezone and stale-request replacement, without clearing unrelated reminders or claiming OS delivery.
- [ ] Junior rewards avoid time-pressure double-XP nudges, streak-loss pressure and adult exertion/weight targets. Switching to a junior profile suspends adult XP prompts; suitable family activity/check-ins remain positive without fabricated training evidence.
- [ ] Build compact combined map/node sheets, daily/weekly challenge cards and a real streak/XP/freeze/double-XP widget on Today/Skills. Preserve existing ledgers and no reward for merely visiting a screen. Run covering checks/render review and commit.

### Task 8: Autonomous Watch workouts and automatic real telemetry

**Files:** new `Shared/Core/WatchWorkoutJournal.swift` and programme transport values, `Shared/Apple/CompanionLink.swift`, Core Companion optional additions, `Native/Watch/WatchStore.swift`, `WorkoutRecorder.swift`, `SpottrWatchApp.swift`, phone import/data scope; Watch recorder/store/transport replay and Core journal tests.

**Interfaces:** Transport Task 6 upcoming programme and account-bound trusted offline grant over the paired link. Watch uses the shared configured workout/manual quantities and set-effort domain with unique local session IDs. Offline grants max30 days and earlier verified entitlement deadline. Durable per-account outbox is acknowledged only after phone history/rewards save; legacy snapshot/control decoding remains safe.

- [ ] Add red tests for automatic exactly-once recorder start, sensor warm-up/no fake BPM, denied permissions, pause/rest/resume, stable screen selection and finish exactly once.
- [ ] Add offline tests for choosing/starting a cached complete workout, Crown/manual reps and timer, actual effort, auto rests/haptics, restart/persistence, stale phone command conflicts and finishing after grant expiry.
- [ ] Add expiry/revocation/account-switch, repeated import/ack loss/queue overflow tests preserving quantities/XP and no cross-account leaks. All Watch results remain manual/timer, never camera-derived.
- [ ] Include training-profile identity in the trusted context and capture it for asynchronous recording/import callbacks. Junior sessions must not write into a guardian Health store; keep manual logging/timer/rest usable without HK collection. Suppress junior session/Health data to legacy Watch clients lacking profile-scope support rather than relying on an ignored optional field to stop old recording behaviour.
- [ ] Remove Record/layout-jump controls; use stable metrics/controls pages with true reading freshness and concise setup/error actions. Compile phone/Watch, run Watch harness/replay and targeted native checks; use an existing Watch simulator only if one is available/coordinated, never create one; commit.

### Task 9: Valuable Coach actions, voice previews and final copy consistency

**Files:** `Native/iOS/OfflineCoachView.swift`, `VoiceCoachSettingsView.swift`, new preview coordinator using existing bundled players, shared programme adjustment helpers and profile/copy components; audio/coach action/UI tests.

**Interfaces:** Coach modifies future programme via Task 6 methods and launches through Task 4. Voice previews use existing bundled Maya/Leo/Arnold/Goggins clips and the retained explicit local-voice option; selecting coach or tone is an explicit preview action, latest selection wins, no network generation.

- [ ] Write red tests that each Coach option actually edits/opens the intended plan, respects support/exclusions/rest/effort, never mutates active work or pretends to provide clinical/generative advice.
- [ ] Write red audio selection/tone-preview tests for natural bundled sample, rapid changes, missing asset, route/background/dismiss/new-workout cancellation and no overlap with live coaching. Preserve all build-23 ordinary-sentence and explicit cancellation regressions.
- [ ] Build concise useful Coach cards, responsive visual/haptic selections and auto-preview controls with a clear stop/mute option. Audit consumer copy and actions across the four tabs, setup/settings/paywall and Watch; remove forbidden demo/guest phrases and punctuation without blindly altering code/URLs/medical-source quotes.
- [ ] Run targeted audio/coach/native/UI checks and render review; commit. Do not regenerate audio or change the 243-file bank in this task.

### Task 10: Live services, privacy analytics and integrated acceptance

**Files:** new consented analytics server/client/tests, privacy/settings/notice/site account/AASA assets, server migrations/config docs, phone app entitlements/generator signing capabilities, integrated journey tests and evidence. Auth/services operational credentials stay outside Git.

**Interfaces:** Complete Task 2 provider/Apple identity configuration and actual native domain association. Two independent adult-only consent choices cover feature usage and aggregate workout statistics. The separate no-auth/no-cookie client sends only coarse weekly totals/distributions, not identifiable workout logs, raw Health/measurements, precise dates/times or stable account/profile identifiers. Unknown-age/junior data is excluded. Deduplication tags are weekly/ephemeral and described honestly; surface workout aggregates only after at least10 contributing installations, with expiry/quota/privacy controls.

- [ ] Write failing consent/revocation/offline/bounds/aggregation/data-exclusion tests and isolated mail/provider configuration checks. Verify native account endpoint and plan ownership against real crypto/D1, with no unsafe production bypass.
- [ ] Test separate usage/statistics consent, adult consent at completion, under18/unknown exclusion, consent changes while Watch is offline, minimum aggregate threshold and no cross-profile mixing. Disable/remove the legacy consumer full-workout upload route (`Shared/Core/WorkoutSync.swift`/old cloud views); adding effort/age/profile fields must never accidentally serialize them into the retired service. Preserve local export and explicit legacy codec compatibility as needed without an active consumer upload.
- [ ] Provision needed free mail service and Apple identity key/capabilities with existing owner access; preserve old credentials/profiles/DNS. Never print keys/codes/JWTs. If owner interaction is genuinely required, prepare the concrete action and continue all independent work while requesting it.
- [ ] Back up relevant D1/config state, apply only additive migrations, deploy reviewed Worker/assets/AASA/notices under the existing subdomain and verify actual HTTPS/status/contracts. No unsolicited real-user mail or new paid plan.
- [ ] Integrate current native Core/web/gateway/Watch checks and selected end-to-end account/setup/paywall/manual/camera/programme/quest/import flows on existing coordinated simulators. Inspect actual renders including Dynamic Type/Reduce Motion and verify loading/timer observation scope. Run affected native pose controls only if capture/counting semantics actually changed; do not relabel old video benchmark results.
- [ ] Record exact service/software/hardware acceptance limits, correct stale consumer notices, self-review and commit. Finish every functional fix/task review and one broad final review before release/install.

### Task 11: Finished build, source publication and iPhone installation

**Files:** generator/project version, release/evidence/priorities docs and private operational receipts/signed SSD artifacts.

- [ ] After all functional review gates, choose the next unused build number (expected24), update generator/all phone/Watch settings and freeze actual final inputs. No feature changes after this freeze.
- [ ] Produce distribution archive/export and a separate development Release phone/Watch build using new private profiles/configuration that include required Apple/associated-domain capabilities. Preserve build17, Vendor and old archives/configuration; audit signatures, entitlements, dSYM/model/audio, no credential/debug purchase/auth bypass and exact source lineage.
- [ ] Verify live provider/AASA and Apple product/trial/offer state, with no invented product availability or charges. Normal feature push and TestFlight are already authorised; verify actual processing/review/groups separately and preserve automated-review failures rather than claiming a pass.
- [ ] Root reviews concrete final signed artifact receipts. Only then install the finished app on Omar's actual iPhone, preserving data/no uninstall, and read back its version. No intermediate phone installation. Physical MFA/purchase/movement/audio/Watch acceptance must be reported separately from software checks.
- [ ] Complete a fresh read-only release evidence review and final factual documentation/push. Preserve this plan's evidence workspace and record decisions, outstanding external approvals and real-device limits honestly.

## Plan self-review and execution notes

This single integrated plan is deliberate: accounts, membership, programme launch and Watch ownership are coupled boundaries of the same user journey, rather than independently shipped products. Task interfaces are published by their producing task and consumed sequentially. Per-task owned tests must pass; any necessary intermediate downstream integration-red checkpoint must be explicitly documented and resolved before final acceptance, never hidden with exclusions or shipped.

The two builder-check questions were resolved in the spec: strong linked-identity-plus-backup recovery before replacement enrolment, and the exact 30-day/entitlement-limited Watch offline grant with uninterrupted active saving. Existing user authority covers the requested implementation and ordinary reversible design decisions; do not stop for a routine design/permission menu. Missing owner credentials, actual payment/approval gates or an irreversible unrelated operation are different and must be made concrete before asking.

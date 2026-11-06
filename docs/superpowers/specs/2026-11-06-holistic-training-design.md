# A complete personal training journey

## Intent and authority

Omar wants Spottr to become a coherent consumer product built around a useful personal workout programme. The main journey is account setup, personalisation, permissions, a prepared daily workout, recording each set and how it felt, and progress that changes the next workout. Camera tracking remains the main differentiator and manual phone or Watch logging must use the same workout and history.

This follows his detailed 6 November request and standing authorisation to make sensible improvements autonomously, consolidate/push the feature branch and install the finished update on his iPhone after all changes. This is a new plan after the completed build-23 movement/audio plan. Do not restart that completed work. Current accepted baseline is `a115f05476e0b04093af098806948b7e729f28f2`, branch `codex/spottr-demo-consolidation`.

## Fixed boundaries

- Native SwiftUI iPhone and Watch apps, existing 53-entry catalogue and 52 available camera profiles. No new exercise classifier, model training, HPC job, runtime generative AI or paid tokens. Preserve build-23 geometry, counting, audio completion, timing provenance and source-generation protections.
- No human-style faces, portraits or facial emoji. Continue the faceless stick figures and highlighted joints; use abstract coach colours/waveforms. Remove explanatory product copy about this visual constraint.
- Existing simulators only, no creation, erasure, reset or clones. Shared iPhone `BF27AFBA-FF1E-4484-A3BD-42916CEB1170`. Coordinate with NAKU and Musalli before using it. No Chrome. Keep test/build concurrency bounded at two jobs.
- All bulk builds, logs, screenshots and receipts use the Extreme SSD-backed development storage. Preserve build 17, Vendor contents and metadata, all releases/evidence, `.playwright-mcp/` and `prototype/images/`. Do not move Spottr to Omar-PC.
- TDD follows `/Users/scsoc/.claude/TDD.md`. Keep existing saved IDs, units, history, XP and self-report/camera provenance. New optional record fields must decode old records.
- New mandatory account and workout paywall requirements supersede the previous guest/full-beta-access design. Restore, exports, privacy/account deletion, viewing existing records and help must remain accessible when a membership is unavailable or expired.
- Required native setup must not silently force consent to analytics, Health, microphone, camera or notifications. Camera-off/manual use is explicitly required by the same user request. Children's profiles are guardian-managed and private by default.

## Confirmed age and analytics steering

Omar answered that all ages should be supported with appropriate adjustments, and opted-in aggregate workout statistics should also be supported. These answers supersede the original adult-only/non-health-only provisional defaults. Bodyweight exercises still need age/ability-appropriate choices and supervision; do not apply an adult programme or BMI classification to a child merely because no weights are used.

Use a guardian-owned account with local managed training profiles for under-18s, rather than collecting a child's email or creating an unsupervised child account. Keep profile IDs separate from account IDs across local history, plans and Watch journals. The guardian controls sensitive settings, external links and purchases through a real parental/authentication gate. Do not claim self-declared guardianship is verified legal age. Younger users see an age-appropriate explanation of supervision.

Add explicit age context without guessing that legacy unknown age is adult. Under-5 profiles receive supervised family movement/play ideas and age-appropriate NHS resources, not formal rep targets, camera assessments or adult workout tests. Ages 5–12 start with short varied supervised beginner practice; initial defaults cap a practice at one set, six reps or ten seconds. Ages 13–17 default to at most two sets, ten reps or twenty seconds. These conservative product defaults are not claimed NHS clinical prescriptions or the person's full daily activity requirement. Under-18 automatic effort-based overload and adult weight-loss/assessment logic are disabled; guardian choices and comfort still matter. Advanced adult benchmarks are not automatically assigned to children.

Height and weight are required for an adult training profile and BMI is derived rather than entered as a third value. Junior measurements are optional, guardian-only and never a condition for joining suitable movement activities. Under-2 profiles receive no BMI calculation. For ages 2–17, optional numeric BMI must not use adult bands or pretend to have a validated growth centile. Use the NHS child-growth calculator as a clearly labelled parental external resource unless a properly licensed and independently verified age/sex reference is actually integrated. Do not copy adult thresholds or invent paediatric coefficients. For adults where BMI is inappropriate, preserve a clear non-applicable state rather than fabricating a category.

Under-18 profiles have analytics and cloud-plan sync disabled, use gentle age-appropriate voices, and do not receive time-pressure double-XP nudges or adult weight-management targets. Keep manual Watch logging available, but disable HealthKit integration for a junior profile in this release to avoid recording a child's activity into a guardian's Health store. No adult age-based HR-zone estimate is applied to children. Existing adult features remain unchanged. All younger data stays in the local profile/paired journal; no raw childhood measurements, dates of birth or activity logs go to the account or analytics service.

## Accounts, MFA and durable sign-in

Users can create an iOS account through native Sign in with Apple or verified email. Build on the existing Cloudflare Worker/D1 passkey, TOTP, replay protection and backup-code service rather than introducing a second unrelated identity database. Existing website accounts and credentials must keep working. Provider linking requires fresh authenticated proof, never matching an email string alone.

Use native AuthenticationServices passkeys with required user verification and an exact associated domain. Support iCloud Passwords and other platform passkey providers. Retain Authenticator/TOTP and single-use backup codes; iCloud Passwords can store verification codes. New ordinary sessions require complete MFA; a pending provider response or incomplete enrolment is not an authenticated account. In ordinary login, backup codes replace TOTP rather than the passkey. Explain this once during backup-code setup.

Lost-passkey recovery is a separate, explicit flow. Require a fresh verified proof from the account's already-linked Apple identity or verified email, plus one unused backup code, before enrolment of a replacement user-verified passkey, replacement Authenticator and new backup codes. Consume all challenges atomically, rotate the authentication version and revoke old keys/sessions/codes only after replacement succeeds. An email address, provider assertion or backup code alone never recovers or links an account. No support bypass. An abandoned recovery cannot lock out the old credentials. If all linked identity access and backup codes are lost, recovery is unavailable; an existing Apple purchase can still be restored explicitly into a new account without granting access to the old account's private data.

Use a short-lived access token and rotating, device-bound persistent refresh credentials stored in Keychain. Ordinary app launches, network failures and updates must not log someone out or discard their draft/workout. A rolling trusted-device session may last 180 days between uses and renew with use. Explicit sign-out, account deletion, revocation, detected reuse or invalid credentials may require authentication. Do not promise an irrevocable session or store a bearer token in UserDefaults.

Native Apple identity verification checks issuer, audience, signature, nonce, lifetime and one-time challenge use. Provision the correct Sign in with Apple key for token exchange/revocation; do not misuse an App Store Connect API key as an Apple identity key. Account deletion must revoke provider access where applicable and remove account/server records. Sensitive account changes require fresh MFA.

Email ownership must be verified with a bounded one-time challenge, not inferred from a typed email address. Cloudflare's free service does not send to arbitrary recipients. Prepare a free transactional-mail adapter, with Resend Free as the initial choice, a strict daily sending cap, no automatic paid upgrade and no health content in mail. Credentials/domain provisioning must be completed and verified before claiming live email sign-in. Do not ship an unverified-email workaround or a production OTP debug bypass. Keep email/provider secrets private and out of the app and logs.

Accounts provide actual adult user benefit through saved programme/preferences across devices, with an explicit cloud-plan-sync choice. This release does not upload identifiable full workout logs, per-set effort, body measurements, raw camera/audio or Health readings to cloud storage; phone/Watch result sync uses the paired local link. Separately consented adult aggregate workout statistics are described below. Junior profiles are local-only. Cloud workout-history backup is a future feature rather than an ambiguous optional deliverable here. Server account ownership always comes from the authenticated session, not an account ID accepted from a request body. Existing local data is preserved and explicitly linked/imported into the first account; account/profile switching must not expose another person's data or discard an unsynced Watch journal.

Deploy the exact AASA `webcredentials` entry for `952HTWFJX7.com.omarchoudhry.spottr`. If email callback links use associated links, match only their authentication callback path so privacy/support links still open the default browser. No broad application-link capture.

## Membership and starting a workout

All normal entry points share one launch coordinator: Today, Skills, Coach, library, quests, deep links and Watch commands. It verifies account/setup and a real StoreKit entitlement before starting a new workout. A selected pending workout survives sign-in or purchase, but cancellation, account changes or a new selection invalidate stale launch requests. Resuming an existing workout must not reset it or show a new paywall in the middle of its set.

The first workout start without access presents a polished selection page with monthly and lifetime cards. Requested products remain £10/month with an eligible 14-day free trial and £200 lifetime. Render actual localized StoreKit prices and actual introductory eligibility, not fabricated offers. Transactions must be verified; cancellation, pending approval, failed verification and unavailable products grant no access. A busy state uses a centred brand icon/progress treatment, with clear retry and restore actions.

Restore purchases is visible on the paywall and in Profile. Keep transaction updates, revocation, expiration/grace and duplicate/overlap handling. Add account attribution to new purchases where supported without making an existing verified Apple purchase inaccessible after an explicit restore. Remove the old unrestricted beta promise and membership bypass from production routes. Do not charge a real purchase during agent testing.

`SPOTTRTESTERS` remains the requested lifetime tester offer. Use Apple's offer-code system and verified redemption, not an unverified string unlocking membership. Apple's production custom codes require a ready-for-distribution app and approved IAP; prepare/test the supported sandbox flow and report any external approval gate honestly.

## Setup and shared design system

Keep six clear setup stages, with progress at top left and a styled Skip action/icon at top right when skipping an optional introduction/review is valid. Skip never bypasses required account/body setup or membership. Returning users can leave a review without losing their saved profile.

1. Account and privacy, with a local age/guardian-role checkpoint before any new-account provider/email request, followed by MFA and the separate adult analytics choices. Under-18 training uses an adult guardian’s account; do not ask a child to supply their own email. Keep this checkpoint inside stage 1 rather than adding a seventh stage. Reuse its local age answer in stage 2, and do not send raw age to the service.
2. Age and training-profile setup, required adult height/weight and applicable BMI visual/unit conversion, or a guardian-managed junior profile with appropriate growth information.
3. Goals and rhythm: same-size cards for strength, stamina, mobility, balance and weight management; chosen days, session duration, preferred training time and available support.
4. Starting point and comfortable movements: a four-stop snapping selector with changing faceless/icon illustration and proper selected states. Assess all six exercise families with compact adaptive cards and optional further variations. A styled Not sure yet card is a real answer. Selection advances/scrolls to the next unanswered family, while respecting Reduce Motion and accessibility focus.
5. Phone/Watch permissions and connection, with relevant actions and honest observed status.
6. Coach/style, automatic short audio previews and a concise prepared-week preview.

These stages can contain small substeps rather than giant forms. Reuse one choice-card, goal-icon, primary/secondary action, loading and external-link system. Add restrained selection/navigation/success haptics without frame-by-frame, duplicate or inaccessible feedback. Honour Reduce Motion and Dynamic Type. No plaintext action links masquerading as buttons.

Replace the special weight-management toggle with the same goal control as the other goals. Preserve the existing balance goal, all legacy raw values and prior settings. Keep fitness attributes used for XP distinct from the new five-goal selection semantics.

Required adult height and weight can be entered in metric/imperial units or explicitly confirmed from dated Health readings. Never prefill a junior profile from the guardian's Health store. No invented defaults. The adult BMI band rail is a visualisation, not a draggable way to alter BMI: show all adult bands from underweight through obesity classes, readable boundaries, a circular current-value marker, and honest edge treatment for out-of-range values. Support the existing standard/adjusted threshold choice and an understandable unsure state. Show applicable reference-weight ranges, not a prescribed target or diagnosis. Keep caution/details behind an accessible information action. Junior UI uses age-appropriate growth context without this adult classification rail.

All website links use the same blue underlined label plus external-link icon and open the default browser. Descriptive consumer copy uses natural complete sentences, not scattered fragments, colons, semicolons, em dashes or centred-dot separators. Technical source code, dates, URLs and historical evidence are outside this copy rule. Remove No account needed, guest promises and the No faces or avatars line throughout consumer surfaces.

## Permissions and Watch setup

Present a visual checklist in onboarding and Profile: camera for camera sessions, microphone/on-device speech for spoken logging, notifications for scheduled reminders, Health data for metrics, Watch installation/connection and Watch workout/motion access. Ask the OS only for relevant chosen features. Declining one must leave manual logging usable. A person can choose phone-only without a perpetual missing-Watch warning.

The phone cannot grant the Watch's permissions. Show the installation/open-on-Watch steps and the permission checklist there, then actual handshake and data-arrival milestones. HealthKit does not reveal read-denial status: distinguish sheet reviewed, readings received, no readings and unavailable, never a fake approved tick. Data capabilities depend on actual runtime support and readings; a selected Watch model is useful context, not evidence a sensor exists or has permission.

Move Apple Watch and Health setup from the Today feed into Profile/settings, opened through the top-right profile control. Keep actionable sync failures available through a clear status indicator rather than silently hiding lost data. Insights may still show real metrics and provenance.

## Personal programme and set recording

Generate a complete weekly programme deterministically from goals, starting ability/comfort, available days, duration, equipment/exclusions and actual recent set effort/completion. Keep workout and recovery/rest days explicit. Do not prescribe a medical rehabilitation plan or use BMI alone to choose difficult/intense exercise. Unknown ability starts gently. Seven chosen activity days must include easier recovery work rather than seven hard strength days.

A planned workout contains compatible multiple exercises, sets, reps/seconds and rest periods, using the existing `CoachSavedPlan`/`ConfigurableSession` execution rather than a competing counter implementation. Persist its plan/day ID, timezone and revision so viewing Today repeatedly does not invent a different session. Changes affect future/unstarted work; ongoing counts, sets and recorded history survive changes in camera, coaching, connection and layout.

The same workout screen shows the correct animated stick figure, relevant joints, live camera when enabled, and manual/timer controls when disabled. Each completed set can record actual quantity and a simple perceived-effort choice mapped to a stable 2/4/6/8/10 scale. Keep unknown/unrated as a proper control and discomfort/stop distinct from effort. Do not infer difficulty from video or reward higher pain/exertion. Legacy sets decode with no effort value.

Saving a set starts its rest countdown automatically. Rest completion provides haptics and prepares the next set/exercise without unexpectedly starting camera credit before the person is ready. Shorten redundant controls and explanations, preserve explicit stop/pause and the existing audio lifecycle. Manual confirmation must not silently fill the target as achieved work.

Today leads with the whole prepared workout or recovery day, a compact week ribbon, the next meaningful action and a proper reward widget. Remove the default isolated squat/push-up picker. Individual practice remains available through the same configured-workout pipeline. Insights adds exercise-specific effort over time, planned/completed work and actual weight trends without pretending manual results or proxies are camera-verified measurements.

Coach becomes an actionable programme assistant with clear options such as make today easier, shorten it, swap a movement, move a training day, take a recovery day and review progress. Each action visibly changes the future programme or opens its relevant view. No free-form chat, runtime AI, empty generic paragraphs or unrelated isolated exercise suggestions.

## One skill journey and a year of quests

Use one longitudinal map spanning all 53 catalogue entries, including existing entry levels. The following six chapter order is the chosen initial curriculum; chapter labels are navigation and narrative, not a requirement to perform every exercise to access another family.

- Foundations: seatedMarch, seatedKneeExtension, frontArmRaise, wallPushup, supportedSquat, standingKneeRaise, calfRaise, wallPlank, quarterSquat, sitToStand.
- Rhythm: halfSquat, gluteBridge, deadBug, birdDog, kneePlank, singleLegBalance, stepJack, standingBicepsCurl, catCow, wallSit.
- Control: inclinePushup, squat, tempoHalfSquat, pausedHalfSquat, supportedSplitSquat, standingHipAbduction, standingHipExtension, lateralArmRaise, wallSlide, tandemBalance, kneeSidePlank, hipFlexorStretch, plank, highKnees.
- Strength: kneePushup, wideSquat, narrowSquat, reverseLunge, forwardLunge, lateralLunge, highPlank, sidePlank, tempoSquat, pausedSquat, mountainClimber.
- Flow: pushup, widePushup, splitSquat.
- Challenge: closeGripPushup, tempoPushup, pausedPushup, diamondPushup, assistedSquat.

Interleave the families visually instead of separate squat/push-up pages. Show the current chapter and near-future nodes, with later chapters compact/locked, a clear jump-to-current action and green completed connectors. A node opens a compact useful workout sheet rather than a wall of capability text. All exercise-library practice remains available after account/membership checks even when an achievement is locked.

Keep existing earned practice evidence (three qualifying target sets over two training days) and verification distinctions. Self-reported comfort can establish placement/unlocks but must not add workouts, observed measurements or XP. Unlock a higher level through appropriate lower-level evidence in its own family or explicit starting placement; unavailable support/excluded exercises must not bottleneck unrelated families. The first usable level in a family can serve as its foundation when lower support-dependent entries are unavailable. Existing earned history is never relocked or reset by the new map.

Bundle a deterministic reusable calendar with 366 daily slots and 53 weekly slots, supporting leap days and ISO week 53. Provide three daily and two weekly quest choices using varied prewritten templates. Select suitable challenges from the person's actual plan/capabilities; reward actual recorded completion/check-in evidence with idempotent IDs, not opening a page or fictional steps/calories. Camera-only challenges require actual camera evidence. Rest days remain legitimate and do not encourage unsafe daily exertion.

Use a coherent widget for streak, XP, freeze inventory and the next double-XP window. Preserve earned ledger/reward history. Schedule opted-in local notification reminders one hour before and at each upcoming double-XP window, with timezone/DST-aware dates and a bounded rolling schedule under the OS pending limit. This meets the requested notification behaviour without a paid push backend. Delivery depends on OS permission/Focus; don't claim hardware delivery from scheduling tests.

## Watch autonomy and automatic metrics

Receiving/starting a valid workout automatically starts the existing workout recorder once. Remove the separate Record action and layout jump. Keep the same metrics/controls pages during requesting access, sensor warm-up and reconnects. Show true timestamps/loading state rather than inventing instant BPM; retaining an older clearly dated reading is acceptable. Stop recording exactly once when the workout finishes, retain telemetry queue handling and don't ask Health permission on every new set.

Persist the upcoming programme and an account-bound access grant on the Watch. After initial account/setup sync, the Watch can choose a cached workout and record manual sets, effort and timed rests without a reachable iPhone. It must not need a fresh phone snapshot merely to use its own local session. Digital Crown and buttons provide clear quantity entry, pause/resume, next set, finish and rest haptics.

An offline start grant lasts at most 30 days from its last trusted verification, and never beyond a verified monthly/trial entitlement expiry or verified grace deadline. Lifetime grants also renew their account check after 30 days. Refresh automatically whenever the paired phone can verify the account/membership, without asking for another login while its trusted session is valid. Known sign-out, deletion and revocation invalidate a grant. Expiry prevents a new start, not completion/saving of an already-running workout. Rest countdown, journals and pending imports remain safe. Explain reconnection only when actually required, not as a permanent banner during normal offline training.

Use unique local session IDs, explicit Watch/manual provenance, actual elapsed/manual-timer values and a durable account-scoped outbox. Sync to phone history/rewards/Insights idempotently when connected, acknowledging only after durable save. Account changes and stale phone commands cannot overwrite an active independent session or leak another account's journal. Keep a deliberate finish confirmation, error recovery and honest missing sensor data. No automatic target-as-achievement or fabricated camera/Health data.

## Analytics, notices and service boundaries

Provide two independent adult-only, opt-in and revocable choices: feature usage, and aggregate workout statistics. Feature payloads are coarse feature counts and app version/day. Workout statistics are on-device weekly totals/distributions such as sessions/sets, coarsely rounded reps/minutes, exercise-family counts, camera/manual contribution counts, tracking-recovery counts and effort-bin counts. They are not identifiable logs or per-set timelines. Exclude account/profile IDs, email, body measurements/BMI, birth date/age, Health samples/HR/energy, raw video/audio, exact session timestamps and free text. No analytics of either type is collected for under-18 or unknown-age profiles.

Use a separate unauthenticated bounded client without auth cookies/headers, server-side aggregation, no request logging and no public raw-event endpoint. If deduplication needs a rotating weekly installation tag, describe it accurately as transient pseudonymous processing before aggregation; never claim the transport is inherently anonymous. Expire tags and only surface workout aggregates once at least ten contributing installations are represented. No advertising/third-party analytics SDK or use for clinical scoring. Withdrawal clears unsent data and stops future collection; explain that already-anonymised aggregates cannot be attributed back to an account. Enforce free quotas, bounds and finite queues; analytics failure cannot block training or sign-in. Update privacy/account deletion/export disclosures to actual fields/processors.

Use Cloudflare Workers/D1 for the existing website/account service. Retain free service limits, existing unrelated DNS/routing/security rules, TOTP encryption/pepper secrets and legacy website account/session compatibility. All new migration/deployment steps must be additive, backed up/reviewed and tested. No paid plan upgrades without explicit user authority. Do not store personal health information in iCloud; passkey authentication is distinct from health storage.

## Verification and delivery

Use public-behaviour red/green tests per task, actual cryptographic/D1 tests for auth, fake-mail/real-schema tests without sending unsolicited mail, StoreKit contract/adapter tests, real native UI rendering, Watch recorder/session/outbox tests, and a final integrated journey on the existing shared simulator when available. Verify every workout entry point shares the account/membership gate and every offline import preserves quantity origin and account ownership. Explicitly diagnose the four old StoreKit simulator `notEntitled` exclusions now billing is changing; do not silently treat them as passing or grant an unverified entitlement as a workaround.

Do not replay all 41 public-video windows merely for UI/account work. If counting/capture generation or observed-time semantics materially change, rerun the affected native controls and preserve prior benchmark results. Use meaningful performance checks for startup/onboarding/render scope and Watch heartbeat freshness, with no claimed physical sensor latency from mocks.

Before delivery, perform task reviews and one broad final review, verify current service/DNS/AASA/auth/Apple product configuration, build and audit signed phone/Watch bundles, freeze actual source/config/resources and recheck build17/Vendor. Install only the finished new build, without uninstall/reset, after all functional changes. Normal feature push/TestFlight are already authorised; actual upload, processing, beta review and group membership are distinct verified states. Physical sign-in/MFA, purchases, exercise, audio and Watch sensor acceptance that cannot be automated remain explicit limits. Preserve all evidence and report any automated-review failure accurately.

## Primary implementation references

- Apple review/account/health rules https://developer.apple.com/app-store/review/guidelines/
- Native passkeys https://developer.apple.com/documentation/authenticationservices/supporting-passkeys/
- Apple identity/token deletion https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple
- Apple offer codes https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/create-offer-codes-for-in-app-purchases
- Health permissions https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data
- BMI bands https://www.nice.org.uk/guidance/ng246/chapter/Identifying-and-assessing-overweight-obesity-and-central-adiposity
- Junior activity https://www.nhs.uk/live-well/exercise/physical-activity-guidelines-children-and-young-people/
- Early years https://www.nhs.uk/live-well/exercise/physical-activity-guidelines-children-under-five-years/
- Child growth https://www.nhs.uk/health-assessment-tools/calculate-your-body-mass-index/calculate-bmi-for-children-teenagers
- Children's privacy https://ico.org.uk/for-organisations/uk-gdpr-guidance-and-resources/childrens-information/childrens-code-guidance-and-resources/age-appropriate-design-a-code-of-practice-for-online-services/code-standards/
- Cloudflare email constraints https://developers.cloudflare.com/email-service/platform/pricing/
- Free email quota https://resend.com/pricing

Builder choices include exact SwiftUI composition, animation curves, icon paths, server module decomposition and programme exercise matching within these boundaries. Do not drop an explicitly requested flow or replace live verification with a fake demo state to make implementation easier.

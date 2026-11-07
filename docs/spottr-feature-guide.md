# Spottr feature guide and next improvements

Prepared on 7 November 2026 from accepted functional source 93c0a92b and frozen candidate 3a0833d for version 0.1 build 24. The signed archive, IPA and separate development Release bundles have passed their artifact audits. TestFlight upload, phone installation and physical acceptance remain pending.

## What the app brings together

| Area | Implemented experience | Acceptance still needed |
| --- | --- | --- |
| Movement library | 53 exercises across pushing, lower body, core, conditioning, mobility and balance. 52 entries have configured camera tracking. Cat-cow remains manual. Variants include wall, incline, knee, regular, close-grip, wide, diamond, tempo and paused push-ups, plus quarter, half, supported, narrow, wide, tempo and paused squats. |Real camera trials across positions, clothing, lighting and short occlusions. Configured tracking is not a per-exercise accuracy guarantee. |
| Onboarding |Six stages, consistent goal choices, four starting levels, comfortable-movement placement, adult measurements and appropriate permissions. Abstract coach designs and faceless joint figures. |First-time setup on the final phone build, large text and VoiceOver. |
| Today and planning |Saved deterministic weekly workouts, suitable exercise choices, actual sets/reps/rest and recovery days. Camera/manual practice use the same launch and membership rules. |A complete planned workout on the final build. |
| Workout and coaching |Camera tracking with relevant joint guidance, manual alternatives and retained workout progress. Bundled voice choices/previews and rule-based actions. |Listen to full cues while tracking disappears, pause/resume and camera changes. |
| Skills and quests |One 53-exercise journey with compact chapters, green earned connectors and nearby nodes. Bundled 366 daily slots and 53 weekly slots, with suitable choices and actual evidence-backed progress. Adult reward/reminder controls. |Notification delivery and genuine earned progression after the final workout. |
| Reports and insights |Actual completed quantities, effort/rest and dated history. Camera, manual and timer sources remain distinct. Optional Health readings and zones display missing data honestly. |Real Watch/Health sensor collection and report readback. Motion samples do not by themselves prove repetition speed or symmetry. |
| Apple Watch |Cached manual workouts, set controls, timed rests, automatic eligible Health recording, durable pending journals and owner-scoped duplicate-safe phone sync. Startup entitlement recovery and measured rest retention are fixed. |Paired and phone-free trials, heart-rate startup, haptics, restart and reconnect with an actual Watch. |
| Accounts and privacy |Apple or email identity plus passkey and Authenticator, protected persistent sessions, recovery, export/deletion and separate adult usage/workout-statistics choices. Junior protections remain distinct. |Live native enrollment/recovery and website passkey use on the final device. The deployed AWS SES email path and native provider activation are complete. Human inbox delivery, native MFA and typed Apple private relay email remain separate acceptance checks. |
| Membership |Monthly/lifetime selection, eligible two-week trial presentation, verified Apple access and explicit restore into a new authenticated account. |Actual StoreKit product fetch, sandbox checkout/restore and Apple review. Configured £10 monthly and £200 lifetime is separate from availability. |

Camera support checks movement patterns, not every setup detail. Current instructions explicitly distinguish things such as hand placement, wall/chair contact and added load that the camera does not verify. The earlier public-video campaign is useful engineering evidence. It does not establish demographic coverage or clinical effectiveness.

## Quick wins to prioritise from tester feedback

| Priority | Improvement | Useful outcome to measure |
| --- | --- | --- |
| 1 |Refine the first-session camera-placement checklist and make the manual alternative obvious. |Users complete their first set without assistance. |
| 2 |Give exercise-specific framing guidance and actionable low-confidence states using the existing joint figure. |Fewer dropped-tracking corrections and abandoned sets. |
| 3 |Improve the resume card for genuinely unfinished work. |More interrupted sessions continue with quantities intact. |
| 4 |Add favourites/recent practice while retaining the same safety, account and membership checks. |Fewer taps to repeat a suitable exercise. |
| 5 |Offer direct calendar rescheduling with recovery-aware rules. |More completed planned days without pressure to exercise daily. |
| 6 |Offer local feedback-frequency and quiet-hours controls. |Fewer unwanted interruptions or muted coaches. |
| 7 |Make dated private report sharing easier, including source and missing-data explanations. |Useful progress conversations without misleading totals. |
| 8 |Test larger-control/high-contrast/reduced-motion presets with real accessibility users. |Successful completion of setup, practice and reports. |

## Larger work to keep separate

- Validate movement counting against independently counted trials before making broad reliability claims.
- Calibrate Watch-derived movement measures against reference measurements before calling them speed, symmetry or clinical consistency.
- Review age-specific exercise planning and any rehabilitation pathway with qualified professionals.
- Define target errors, lawful training data, held-out evaluation and device benefit before proposing AIRE training. Tell Omar before any training job.
- Plan passkey migration before changing the authentication domain. Preserve the existing relying party during transition.
- Treat GP workflow integration and clinical outcome validation as future pilot work.

SPOTTRTESTERS must not be advertised as active until Apple enables the actual offer. Preserve the distinction between implemented source, deployed services, Apple approval, installed build and human/device acceptance.

The final release evidence and controller decisions must accompany delivery. The source contains no raw workout, effort, body measurement or Health-reading uploads. Account services and separately consented adult aggregate statistics have different storage and disclosure requirements.

The retained private controller decision record accompanies delivery and records the operational rulings and remaining release gates.

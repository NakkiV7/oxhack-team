# Offline MVP verification, 5 November 2026

The current implementation is a local testing candidate. No TestFlight upload or App Store submission was performed.

## Checked behavior

- Shared core: **102 XCTest and 222 Swift Testing tests passed**. Includes variation-specific geometry/depth, bounded pose loss, preserved camera/manual counts/time, replay isolation, onboarding placement without invented history, deterministic insights, batched/cumulative speech parsing and monotonic pose timestamps with frame spacing.
- Native iPhone simulator: **210 tests passed**, including offline provider-call exclusion, profile migration, count source isolation, speech corrections and warm pose-processor reuse.
- After the final speech-result UI synchronization fix, all three focused offline MVP native tests and the end-to-end UI flow passed again.
- Focused UI: onboarding → comfort placement → abstract coach selection → vertical skill path → option-based coach passed on the existing shared **iPhone** simulator. Four main tabs; no Progress duplicate, free-text coach, generated summary button or TestFlight preview entry.
- Watch recorder **11 cases**, Watch store **6 cases**, and actual WatchConnectivity adapter/decoder transport replay to session/history/report passed using SDK doubles. No Watch simulator was created.
- Static project/JSON/shell checks and `git diff --check` passed.
- Independent code review found and led to fixes for batched recognition, a previous workout's count leaking into new speech input, manual correction during recognition, and final-result text-field synchronization.

## Signed build 18

A Release archive and App Store export were created on the Extreme SSD. Host and embedded Watch are both **0.1 (18)**. Existing distribution identities and profiles were reused; Watch HealthKit entitlement remains present.

Archive and independently unpacked exported app/Watch passed deep strict signature verification. Host and Watch binary UUIDs match their respective dSYMs. The bundle contains the **99 existing MP3 clips**, the unchanged Full pose model and no provider credential files. Celebrity portrait assets are absent from the compiled asset catalogue. Original coach recordings are retained; new ElevenLabs recordings are not claimed.

The generic simulator build initially attempted unsupported Intel MediaPipe linkage; validation was rerun successfully for the existing Apple Silicon simulator. Automatic archive signing initially selected an unsuitable wildcard Watch profile; explicitly selecting the existing matching distribution profiles resolved it. No SDK replacement or new signing identity was needed.

Build 17's 209 product files and 157 dependency files also match the saved preservation baseline, including original metadata, links, attributes and hashes.

## Review captures

- [Abstract trainer selection](../media/offline-mvp-2026-11-05/abstract-trainer-onboarding.png)
- [Vertical skill path](../media/offline-mvp-2026-11-05/vertical-skill-path.png)
- [Offline coach choices](../media/offline-mvp-2026-11-05/offline-coach-options.png)

## Limits before broader testing

Physical accuracy across the seven new variants, real microphone recognition quality, audible voice quality and real Watch pairing/HealthKit acceptance have not been established by these software checks. Test each variation against a human reference count. Selected close-grip/wide/support variations do not verify hand spacing, stance width or support stability. The on-device model recognises body joints; the app checks the chosen movement's geometry and phase rules.

Existing ElevenLabs authoring credentials are expired/rejected. Maya and Leo currently use iPhone speech with rotating phrases and three styles. They are not new ElevenLabs recordings. The consumer app makes no authoring/provider request.

Use the [phone/Watch testing checklist and prioritised feature list](../offline-mvp-testing-and-next-steps-2026-11-05.md) before opening this candidate to broader testers.

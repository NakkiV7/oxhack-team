# Spottr build 26 delivery

Spottr **1.0 (26)** is installed on the owner's existing iPhone and available to the original internal TestFlight group. App Store submission and public release are not complete.

## Accepted changes

Functional source is `aa1542a77b9ef5b70ca48d3c01b9bdf3176da2dc` on `codex/spottr-demo-consolidation`, pushed and independently read back from origin. The final source review found no Critical or Important findings.

- The welcome screen gives Apple sign-in priority and separates the age/role checkpoint from the chosen identity method. Existing passkey, Authenticator, recovery and device/guardian controls remain authoritative.
- Membership & Apple purchases is directly reachable before account setup. Prices and access still come from StoreKit. Restore remains available through the existing route.
- Training setup presents separate goals, schedule and support steps, four ordinary starting-point columns with an accessibility fallback, one comfort family at a time and an editable review. Values survive Back. Persisted setup revision remains 3.
- Body, privacy, coach and permission information use compact sections with expandable details and the shared faceless movement guides. Rendering permission rows does not request access.
- Returning from Watch setup reloads the saved Watch choice before computing the parent summary, including both Phone only and Watch transitions.
- The iOS manifest and real source/bundled tests agree on six exact data types and their purposes. Fitness includes personalization; Customer Support uses app functionality. Tracking remains false. The Watch API reasons are unchanged.

## Verification and packaging

Task-specific evidence is preserved in the plan workspace `.superpowers/sdd/2026-11-10-app-store-membership/` and the SSD evidence root `Audio/Account-Providers-20261110/` on the mounted Spottr Development volume.

| Check | Recorded result |
| --- | --- |
| Directly visible membership journey | Meaningful RED then 1/1 GREEN |
| Focused account welcome and feedback | Final 3 hosted plus 4 real XCUI cases passed; earlier affected account runs are separately recorded |
| Training presentation, permissions and rendered layouts | Final 26 hosted plus 1 existing membership journey passed |
| Shared Watch choice refresh | Actual RED followed by 8/8 focused Core checks |
| Parsed source privacy contract and plist lint | Actual two independent declaration failures then 4/4 passed; lint passed |
| Actual hosted bundle privacy assertion | 1/1 passed |
| Final combined source review | Approved for source freeze and archive work |
| Distribution archive, exported IPA and development app | Both phone/embedded Watch signatures, profiles, certificates and dSYMs verified |
| Resource continuity | Exact 243 audio paths/bytes and canonical Full pose model preserved; both privacy manifests match accepted source bytes |
| Apple package validation | VERIFY SUCCEEDED with no errors |
| Frozen build inputs | 1,636 entries matched through the final delivery check before this documentation update |
| Protected old products | Build 17's 209 files/231 entries and Vendor's 157 files/189 entries retain exact content and metadata |

All native bulk outputs, logs, DerivedData, archives and receipts were written to the mounted SSD volume. Actual archive/development Swift commands used driver jobs 1 and backend threads 1, with both parallel WMO settings disabled. No new simulator, reset, erase, app uninstall, model training, paid runtime provider or dependency replacement was performed. Existing simulator data and all previous evidence remain.

The tests do not establish physical camera accuracy, audible playback, VoiceOver focus, haptic feel, keyboard occlusion or real Watch sensing/pairing. Compiler and hosted-controller lifecycle diagnostics remain documented debt. The native plist Node check requires macOS `plutil`.

## Delivery and listing state

At **08:04:43 UTC**, the pinned physical iPhone returned `com.omarchoudhry.spottr`, version `1.0`, build `26` after successful installation. Existing app data was preserved. This is installation evidence, not owner interaction or physical Watch acceptance.

Apple build `648f7c8e-4e24-4e06-a5bc-3a9f915111df` became `VALID`, marketing version `1.0`, encryption false. At **08:12 UTC**, the existing Spottr Internal group contained build 26 and reported `IN_BETA_TESTING`. Its previous 12 build memberships were preserved; the external OxHack group's nine memberships were unchanged and do not include 26. Beta notes were saved and read back.

The original upload command timed out reading the existing upload reservation. Read-only reconciliation found an awaiting reservation with its analyzer and description files complete, but no IPA asset or processed build. The controller preserved that attempt and resumed the same reservation through Apple's documented API. Ten IPA parts completed, the exact IPA checksum was committed and processing reached VALID. No duplicate build-upload reservation or blind command retry was created.

The App Store 1.0 draft now references build 26 and remains `PREPARE_FOR_SUBMISSION` with `MANUAL` release. Consumer name, subtitle, description, keywords and Health & Fitness category are saved. The app download is £0 with UK base currency. All 175 availability entries were checked, with only GBR available, no pre-orders and no automatic addition of new territories. The initial incomplete availability request returned an atomic 409; a fresh read confirmed no created resource before the complete explicit matrix was accepted and verified.

The owner reported both £10 monthly and £200 lifetime prices visible on the real iPhone in build 25. This establishes catalogue rendering, not checkout. The monthly product still reports `MISSING_METADATA`; lifetime reports `READY_TO_SUBMIT`. Existing monthly price, 14 day eligible trial and lifetime price were preserved. No charged purchase or new production offer code was created.

## Remaining submission and acceptance work

- The six App Privacy categories and purposes are saved as drafts. Apple's final publication agreement is awaiting the owner's explicit confirmation. Nothing has been published through that step.
- Complete truthful phone/iPad/Watch App Store screenshots, the age-rating questionnaire and audible-content verification. Do not substitute generated or outdated screens for current app operation.
- Complete ordinary account/MFA acceptance and workable reviewer sign-in instructions. No fictitious credentials, reviewer bypass or false sign-in-free declaration has been added. Apple's private-email-relay sender registration remains unfinished in Safari; the previously prepared SES service is not proof of this registration or inbox acceptance.
- Check actual Apple submission validation with the matching binary and products, then send only when required access and fields are complete. The first subscription must accompany the app through the supported website flow.
- Keep Apple Support on hold until a corrected submission is rejected again, as the owner requested. No support case was sent.
- The existing [MediaPipe privacy/origin gate](../release-readiness.md#mediapipe-distribution-remains-unresolved) remains open. Successful first-party manifest checks, upload or Apple processing do not attest vendor SDK compliance or establish public readiness.

The next owner device check should cover completing normal account setup into a saved programme, Back/edit after changing available support and Watch → Phone only → Watch summaries. Broader camera, coach audio, real purchases and Watch sensors remain separate hardware acceptance.

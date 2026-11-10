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

All native bulk outputs, logs, DerivedData, archives and receipts were written to the mounted SSD volume. Actual archive/development Swift commands used driver jobs 1 and backend threads 1, with both parallel WMO settings disabled. The packaging and delivery phase created no simulator and performed no reset, erase, app uninstall, model training, paid runtime provider or dependency replacement. The later screenshot-only Watch exception is recorded below. Existing simulator data and all previous evidence remain.

The tests do not establish physical camera accuracy, audible playback, VoiceOver focus, haptic feel, keyboard occlusion or real Watch sensing/pairing. Compiler and hosted-controller lifecycle diagnostics remain documented debt. The native plist Node check requires macOS `plutil`.

## Delivery and listing state

At **08:04:43 UTC**, the pinned physical iPhone returned `com.omarchoudhry.spottr`, version `1.0`, build `26` after successful installation. Existing app data was preserved. This is installation evidence, not owner interaction or physical Watch acceptance.

Apple build `648f7c8e-4e24-4e06-a5bc-3a9f915111df` became `VALID`, marketing version `1.0`, encryption false. At **08:12 UTC**, the existing Spottr Internal group contained build 26 and reported `IN_BETA_TESTING`. Its previous 12 build memberships were preserved; the external OxHack group's nine memberships were unchanged and do not include 26. Beta notes were saved and read back.

The original upload command timed out reading the existing upload reservation. Read-only reconciliation found an awaiting reservation with its analyzer and description files complete, but no IPA asset or processed build. The controller preserved that attempt and resumed the same reservation through Apple's documented API. Ten IPA parts completed, the exact IPA checksum was committed and processing reached VALID. No duplicate build-upload reservation or blind command retry was created.

The App Store 1.0 draft now references build 26 and remains `PREPARE_FOR_SUBMISSION` with `MANUAL` release. Consumer name, subtitle, description, keywords and Health & Fitness category are saved. The app download is £0 with UK base currency. All 175 availability entries were checked, with only GBR available, no pre-orders and no automatic addition of new territories. The initial incomplete availability request returned an atomic 409; a fresh read confirmed no created resource before the complete explicit matrix was accepted and verified.

The owner reported both £10 monthly and £200 lifetime prices visible on the real iPhone in build 25. This establishes catalogue rendering, not checkout. The monthly product still reports `MISSING_METADATA`; lifetime reports `READY_TO_SUBMIT`. Existing monthly price, 14 day eligible trial and lifetime price were preserved. No charged purchase or new production offer code was created.

## Store preparation update — 10 November

The owner explicitly authorised publishing the privacy responses and submitting the completed app and purchases. Safari was used only after both Musallī and CV released it. Existing company and peer tabs were preserved.

- The six privacy categories and purposes were published. App Store Connect showed publication by the owner immediately afterward.
- The actual seven-step age questionnaire was saved. Apple calculated **13+**, with infrequent medical information for the current adult BMI/reference content and health/wellness present. No independent age-assurance claim, Kids Category or age override was selected. Current general-fitness functionality was declared not a regulated medical device.
- Four actual iPhone captures, **1206 × 2622**, and one actual Watch setup capture, **416 × 496**, were uploaded through Apple's documented reservation, byte upload and checksum-commit process. Every image returned `COMPLETE`, with empty delivery errors and the exact dimensions. The signed shipping device family is iPhone only, so the iPad compatibility-window captures were not submitted as native iPad artwork.
- A tests-only repair replaced brittle private accessibility-tree text checks with meaningful OCR and raster checks on the real rendered images. The four selected cases passed on each existing phone/iPad simulator. Fresh spec and quality review approved `a596367`; shipping Native/Shared/project/generator inputs remain unchanged from `aa1542a`.
- The Watch capture used an already installed runtime. There was no existing Watch simulator, so one screenshot-only Series 10 device was created under the owner's explicit exception, then shut down and deleted immediately. The saved before/after inventory verifies its removal. Existing devices were preserved. A subsequent optional capture on an existing large iPhone stalled before test execution and was stopped; it is retained as `TEST INTERRUPTED`, not passing evidence. That existing device returned to Shutdown. Current App Store validation accepts the completed medium iPhone images.
- Existing reviewer contact details and explicit passwordless enrollment instructions are saved. Sign-in required remains true. The username/password fields explicitly instruct the reviewer to use their own Apple/email identity and passkey plus Authenticator; these are instructions, not a claimed shared credential. The notes describe ordinary setup, optional permissions, sandbox purchase, restore and manual exercise input. Apple now clears the empty-field validation errors. This does not establish successful reviewer enrollment or acceptance of the access approach.
- A single ordinary production email challenge reached an owner-controlled Gmail plus alias in Inbox. Receiver headers report SPF, DKIM and DMARC pass. No account, passkey or Authenticator credential was created. This verifies live delivery, not complete device enrollment, private-relay delivery or purchases. The initial Python client was rejected at Cloudflare with error 1010; normal curl API requests worked without changing protection settings. No verification code is included in public evidence.

SSD evidence is under `Audio/AppStore-Submission-20261110/` on Spottr Development. It includes the image provenance, original and failed captures, focused test receipts, audio-content audit, temporary-device receipt, provider upload/readback records, reviewer notes and delivery receipt. All 243 bundled audio hashes were verified and the actual waveforms transcribed locally using an already cached model. No restricted language was found in this bounded automated audit; it does not establish licensing rights or substitute for human listening.

## Remaining submission and acceptance work

The latest actual website Add for Review validation reports only **Content Rights Information** as the app-level error. The owner has been asked to confirm distribution rights for bundled artwork and coach recordings, including the retained Arnold/Goggins-labelled packs. Neither rights declaration was guessed or selected.

The app remains `PREPARE_FOR_SUBMISSION`, manual release, with no App Review submission. The monthly product still reports `MISSING_METADATA`, so the first-subscription selection and actual app-plus-purchase submission remain to be completed through the supported website flow. Safari's subscription table requires a pointer click; macOS currently reports `noWindowsAvailable`. The owner has been asked to unlock the Mac; the Apple session is still signed in.

Ordinary full account/MFA device acceptance and Apple's private-email-relay sender registration remain unfinished. The successful SES-to-Gmail delivery does not prove either. Keep Apple Support on hold until a corrected submission is rejected again, as requested. No support case was sent.

The existing [MediaPipe privacy/origin gate](../release-readiness.md#mediapipe-distribution-remains-unresolved) remains open. Successful first-party manifest checks, upload or Apple processing do not attest vendor SDK compliance or establish public readiness.

The next owner device check should cover completing normal account setup into a saved programme, Back/edit after changing available support and Watch → Phone only → Watch summaries. Broader camera, coach audio, real purchases and Watch sensors remain separate hardware acceptance.

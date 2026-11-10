# Spottr 1.0 (27) delivery checkpoint

Checkpoint **10 November 2026, 11:45 UTC**. Build 27 removes the Arnold/Goggins packs and is `VALID` and `IN_BETA_TESTING` in the existing Spottr Internal group. The App Store 1.0 review draft uses build 27 with manual release. **It has not been submitted to App Review or installed on the pinned physical iPhone at this checkpoint.**

## Source and preservation

Accepted product commit `0b00c88e96eebb412ed35b675f0d7e43b9d40895`, followed by reviewed test-only fixes in `d7a222fb28f2d50faaf233f6f0641987a3e9c582`, pushed to `codex/spottr-demo-consolidation`. Maya, Leo and Local are the available choices. Unsupported saved voice choices migrate to Maya without resetting training data or re-enabling voice feedback. Optional rep counts use the explicitly labelled device voice and default off unless previously opted in.

The three retired resource directories were independently preserved on SSD before removal. All 102 files matched source paths, sizes and SHA-256 values. All 144 retained Maya/Leo MP3 files match the pre-removal manifest. Source inspection found no retired coach names in Native or Shared runtime code/resources. Old builds, evidence, branches and dependencies remain preserved.

Affected native verification passed 135 cases; Core verification passed 20 controller and three rep cases. Two focused cases passed after the final test-only fixes. Fresh task, whole-continuation and final scoped reviews approved the source, with no Critical or Important findings. Inherited toolchain/test harness warnings and the light-appearance limitation of the screenshot helper remain documented.

## Packaging and TestFlight

Archive, exported IPA and development app audits passed for both iPhone and embedded Watch bundles at 1.0 (27). They verified signatures, profiles, entitlements, matching dSYMs, exact retained audio/model/privacy resources and absence of retired packs, secrets and test fixtures. Signing inputs and entitlements match the corresponding build 26 stages. The build 17 and Vendor preservation checks passed. All bulk output stays on the Spottr SSD.

The IPA is 49,281,552 bytes with SHA-256 `f62715bc591e50bfa4afd6aae21a791fb69feaeb692248fa21c416c4a56a6e77`. Apple's explicit-app-ID validation passed after a separately preserved metadata-lookup timeout. One upload succeeded. Apple reported build `b76b4d85-ef54-4318-8301-a601c9b08fa2` as `VALID` at 11:32 UTC. Do not repeat that upload.

Internal TestFlight contains build 27 plus all 13 prior internal builds. External OxHack remains unchanged at nine builds and does not include build 27. No external beta review was requested.

## App Store preparation and remaining blocker

Privacy responses are published. The saved age rating is 13+, and the regulated-medical-device response is No for this general fitness version. Four actual phone screenshots and one actual Watch setup screenshot are uploaded and complete, with original captures and conversion provenance retained. They illustrate local profiles and manual inputs rather than measured exercise or live Health data.

The content declaration is `USES_THIRD_PARTY_CONTENT`, based on the remaining paid-generation/library provenance and existing artwork/third-party notices. The updated reviewer notes explain ordinary passwordless enrollment, passkey and Authenticator setup, the visible Membership screen, purchases/restore and optional hardware. These instructions are not a reusable demo credential or proof that Apple has accepted reviewer access.

The supported App Store Connect website flow created draft submission `7903e78a-1a46-4a2c-859f-ac2590b6e3e2` containing:

- iOS App 1.0 (27)
- Spottr Lifetime Membership
- Spottr Membership subscription group

Adding Spottr Monthly Membership to that same draft fails with **“You must add a subscription price.”** Apple's UI and public API both show the UK £10 price and two-week free trial. Re-saving the same starting price did not change the error. A combined group-list attempt and individual item attempt also failed to add monthly. The group consequently requires its subscription before the draft can be submitted. No incomplete app-only submission or API first-subscription bypass was attempted. UK-only availability and existing prices/trial remain unchanged.

Apple's current [subscription API guidance](https://developer.apple.com/documentation/appstoreconnectapi/submitting-subscriptions-and-subscription-groups-for-app-review) still requires the first subscription to accompany the app binary through the website. A technical support request is prepared on SSD but has not been sent. The owner previously asked to wait until another corrected rejection before contacting Support; this is a validation failure before App Review.

The pinned iPhone remains unreachable through CoreDevice at the latest 11:38 check. No build 27 install, uninstall, reset or erase was attempted. Build 26 was last verified installed earlier today. Build 27 is ready for installation when the owner connects and unlocks that phone.

Full physical Apple sign-in/passkey/MFA, purchase/restore, Watch sensors and exercise/audio acceptance remain separate. Normal email delivery to the owner's controlled inbox was verified with SPF, DKIM and DMARC passing. Private Relay sender registration remains incomplete. The existing MediaPipe privacy/origin audit in [release readiness](../release-readiness.md) remains open; successful packaging and Apple processing do not close it.

## Evidence locations

- `/Volumes/Spottr Development/Audio/Account-Providers-20261110/candidate27-preparation` contains frozen inputs, signed audits, validation/upload logs, private provider receipts, beta readbacks and device attempts.
- `/Volumes/Spottr Development/Audio/Celebrity-Retirement-20261110` contains preserved retired packs, manifests, test results and source receipts.
- `/Volumes/Spottr Development/Audio/AppStore-Submission-20261110` contains privacy, screenshot provenance and email delivery evidence.
- `.superpowers/sdd/2026-11-10-app-store-membership` retains the implementation reports and independent reviews.

Private credentials, account details and enrollment codes are excluded from this receipt.

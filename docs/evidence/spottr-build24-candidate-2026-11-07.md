# Spottr build 24 candidate evidence

This document records candidate preparation on 7 November 2026. The controller subsequently approved the exact artifact for internal beta delivery. At 19:00:31 UTC, version 0.1 build 24 was VALID and IN_BETA_TESTING in the existing internal group. See the [dated internal delivery receipt](testflight-build-24-2026-11-07.md). Final phone installation, external distribution and physical acceptance remain separate gates.

The accepted functional source is `93c0a92b6f78e26ea1423758998b5a7061e1525e`. Candidate commit `3a0833d3d8cbd767e292bccd8579b79d3f020cbd` changes only build numbers in the generator and all phone, Watch and test configurations. A private manifest freezes 1623 input entries, including actual resources, Vendor payloads and signing configuration. The candidate uses the existing checkout and Xcode toolchain.

## Signed artifacts

The distribution archive and IPA export succeeded under an explicit minimal environment. Both phone and Watch bundles contain version 0.1 build 24. The exported IPA is 49,602,054 bytes and has SHA-256 `228b75832afe14276889ff3ce5e3f9324bb3fcb8230353b38741cf5167c59d75`.

The artifact audit verifies strict code signatures, actual certificate membership in each embedded profile, certificate and profile expiry, team and bundle identity, HealthKit on both apps, Apple sign-in and the exact associated domain on the phone, and executable and dSYM UUID correspondence. It verifies the canonical full-pose model and all 243 audio files at their exact expected paths and bytes. Bounded scans find no known authoring credential, private key or AWS/OpenAI credential patterns, test bundles, local StoreKit configuration or experimental Presage payload.

The separate development Release phone and Watch bundle also passed its artifact audit, including membership of the existing target device in both profiles. It is ready for the final installation gate. Signing alone does not establish native sign-in, real movement or sensor acceptance.

## Current service and store state

The deployed AWS SES provider path and native source activation are accepted. Read-only AASA, privacy page and actual health endpoint checks pass. No additional email was sent during packaging. Human inbox delivery, native MFA and explicitly typed Apple private relay email have their own readiness and acceptance checks.

The worker snapshot at 18:23 UTC on 7 November 2026 showed configured prices of £10 monthly and £200 lifetime and one eligible two-week free trial period. Both products were `MISSING_METADATA` at that time. The later controller readback at 18:30 UTC showed lifetime `READY_TO_SUBMIT` and monthly `MISSING_METADATA`, with both review assets processed `COMPLETE` without errors or warnings. The controller saved and read back ordinary draft review notes for both products at 18:38 UTC. Monthly still required metadata and lifetime remained ready to submit. The tester lifetime offer definition was active with zero production and sandbox codes in the worker snapshot. This is configuration evidence, not a claim of StoreKit fetching, purchase success or a usable SPOTTRTESTERS code. Public submission and App Privacy publication are separate actions.

## Preserved attempts and limits

The first archive succeeded but inherited a Cloudflare token variable. Its completed log contains no exact token value. That archive is preserved as a pre-scrub attempt and is not an accepted distribution or installation artifact. One replacement archive uses a minimal environment and a separate artifact path while reusing the owned compiler cache.

The fetch command mistakenly included `--prune`. An exact comparison with the controller's prior snapshot proves all 99 remote refs unchanged, with no missing, new or changed refs. The deviation and original evidence are preserved.

The private profile checker initially expected an array for Apple's associated-domain wildcard. Apple's actual profile encodes that permission as a wildcard string. The corrected helper validates that permission and separately requires the exact signed domain. A certificate-extraction helper argument was also corrected. Neither correction changed product source or signed bundle contents. The initial wrong health route returned 404 and Python's client returned 403. The correct Node GET to `/api/health` returned 200. All attempts remain in the private evidence folder.

There was no TestFlight upload, group or review change, device installation, uninstall, simulator operation, purchase or public privacy attestation during candidate preparation. Protected build 17 and Vendor files pass exact content and metadata comparisons before and after packaging. Older releases are preserved. All 1,623 frozen entries still match after the final artifact audits. Archive and exported machine-code sections match exactly. All owned build processes have exited. The final physical checklist covers accounts and recovery, real StoreKit offers and restore, movement counting, audible cues, Health readings and paired and phone-free Watch use.

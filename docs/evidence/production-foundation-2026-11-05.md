# Spottr production foundation and TestFlight 19

Verified on 5 November 2026. This records implemented behavior and observed distribution, not public App Store approval, clinical validation or physical exercise accuracy.

## Delivered

The library now has 32 distinct entries and 13 camera-supported styles. Tempo squats/push-ups require at least three observed seconds lowering; paused styles require a two-second observed hold at depth. New manual/timed alternatives include wide and diamond push-ups, wall sit, supported calf raises, bird dog and seated knee extensions. Timed styles reset incomplete movement after uncertain observations without erasing completed reps. Existing bounded continuity for ordinary styles remains covered by regression tests. Skill-path identities and historical progression are preserved.

The app adds a labelled membership/settings route, abstract generated gem and legal/account/support links. Beta training is unrestricted. Native paid access derives only from verified StoreKit transactions; no local code grants a paid flag. Faceless guides highlight relevant joints. The original 99 bundled MP3 files and canonical Full pose model are unchanged.

[The live Cloudflare site](https://spottr.omarchoudhry.co.uk/) includes the landing page, real candidate screenshots, privacy, support, terms, deletion guidance and optional account controls. Accounts require a passkey plus Authenticator for every new sign-in; a backup code replaces only the second factor once. Recovery, export and deletion are implemented. Training, videos and Health data are not uploaded to the website.

## Verification

| Check | Observed result |
| --- | --- |
| Full integrated Swift package | 115 XCTest plus 234 Swift Testing checks passed, 349 total |
| Native app and UI | 213 passed, including 210 app checks and three UI journeys |
| Native StoreKit framework | Four failed during test-session setup with `Code=3` / `notEntitled`; purchase behavior remains unverified |
| Watch boundary tests | 11 recorder and six store cases passed; transport-to-history/report replay passed |
| Account/crypto/Worker behavior | 21 passed; TypeScript strict check passed |
| Public-site checks | 14 passed |
| Production dependency audit | Zero reported production vulnerabilities at this checkpoint |
| WebKit layout | Eight live desktop/mobile states, no missing images, runtime error events or horizontal overflow |
| Synthetic account client | Eight stages, including QR rendering under CSP, recovery-code save gate and deletion confirmation; no real credentials |
| Live account server | Real software-authenticator registration, MFA, backup recovery, code rotation, Authenticator replacement, export and deletion passed |
| Cleanup of live smoke account | Independent D1 query found zero users, credentials, sessions, backup codes and pending records |
| Live public routes | Nine expected route statuses and security headers verified |
| Existing build 17 | All 209 product files and original metadata matched the protected baseline |
| Existing vendor dependencies | All 157 files and original metadata matched the protected baseline |

The account review identified and repaired stale-session deletion, backup rotation and Authenticator replacement races. Tests include concurrent use of one recovery code, TOTP/challenge replay, expired proofs, attempt exhaustion, request bounds and CSRF. An independent source review found no remaining concrete blocker in the exercise/membership changes. These checks are not a penetration-test certification or real Touch ID/passkey-provider acceptance.

No Chrome or new simulator was used. Native testing reused `iPhone` `BF27AFBA-FF1E-4484-A3BD-42916CEB1170`, preserving its data. Build, dependencies and new bulk evidence reside on the Extreme SSD. An Xcode tool's intermediate test export was moved intact to the SSD with a compatibility symlink; no existing release was removed.

## Signed release and Apple distribution

Phone and Watch are **0.1 (19)**. Strict archive/export signatures and dSYM UUIDs matched. Both model files have plaintext `TFL3` headers. Experimental SmartSpectra and local StoreKit testing configuration are absent from the shipping app.

- IPA bytes: **40,714,630**.
- IPA SHA-256: `86eb08edcf9b10408197e2e49a4d3db9ee6708eb12527c5e17698e7e931e92fa`.
- Archive: `/Volumes/Spottr Development/Releases/Spottr-19-Distribution.xcarchive`.
- Export: `/Volumes/Spottr Development/Releases/Spottr-19-Export/Spottr.ipa`.
- Apple delivery/build ID: `c9c46e91-b586-43da-91dd-7e659e49710e`.

Apple validation and upload succeeded. Independent API readback confirmed `VALID`, encryption declaration `false`, `IN_BETA_TESTING` internally and externally, and beta review `APPROVED`. The build is assigned to the existing Spottr Internal and OxHack groups. [The existing TestFlight invitation](https://testflight.apple.com/join/f3MhePbf) remains the installation route. No invitation acceptance, installation or physical set in build 19 is claimed.

Editable App Store and TestFlight marketing/privacy/support URL fields now point to the deployed Spottr site, with GET readback. Public App Store review was not submitted.

## Pricing and tester offer

Apple GET readback verified the exact GBP10 monthly product, eligible two-week free introductory offer, GBP200 non-consumable lifetime product, en-GB localizations and GBR-only availability. Both products remain `MISSING_METADATA`; saved metadata is not proof of StoreKit availability or purchase success.

The free lifetime offer definition exists, but **no `SPOTTRTESTERS` code exists**. Apple returned `NON_APPROVED_IAP` and `NON_ACTIVE_APP`. Production code creation requires the app and IAP to satisfy Apple's approval states. [Full saved metadata and denial](../membership-apple-readback-2026-11-05.json).

## Operations and remaining acceptance

Worker `spottr-site` uses its own `spottr-accounts` D1 database, an exact custom domain, two Worker secrets and hourly expiry cleanup. Original DNS and existing response rules were preserved before mutation. Only the old Spottr A record was replaced; an exact-host HSTS rule preserves existing unrelated rules. No Cloudflare plan upgrade was purchased. The deployment is compatible with Free-tier limits, not a promise of unlimited free traffic. Existing browser-integrity protection rejects Python's default user agent with Cloudflare1010; Node and native WebKit live checks passed without altering zone-wide protection.

Private source manifests, sanitized live receipts, Apple receipts, logs and rollback records are under `.local/production-foundation/` and mirrored to SSD release evidence. Website artwork/export/UI evidence is separately preserved at `/Volumes/Extreme SSD/Codex Evidence/Spottr/2026-11-05-public-website` with 96 verified manifest entries. Current screenshots and the native result receipt are in [review media](../media/production-foundation-2026-11-05/membership-and-guide-review.md).

Remaining gates include real iPhone/Watch counting and audio acceptance, real passkeys/Authenticator setup and recovery, Apple sandbox/device purchase/restore/redemption, product metadata/review completion, public App Store submission, and clinical/governance work before GP recovery claims. No HPC training or new paid voice synthesis was performed. See [feature priorities](../production-next-steps-2026-11-05.md) and [App Store preparation](../app-store-launch-2026-11-05.md).

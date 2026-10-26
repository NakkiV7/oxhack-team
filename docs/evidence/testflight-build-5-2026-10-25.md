# TestFlight build 5

The reported physical onboarding crash remains unresolved. See the [crash investigation and evidence gates](build5-onboarding-crash-2026-10-25.md); successful delivery and simulator checks do not establish a physical fix.

Frozen source **`f3eae89ced8547e283bd93abe6c560c9e1ce8e2c`**, iPhone and embedded Watch **0.1 (5)**. This release includes weekly Coach planning, local profile/skills polish, explicit skip/one-rep check-ins, report polish, Coach keyboard/loading presentation and the compact Watch pager.

[PR #114](https://github.com/NakkiV7/oxhack-team/pull/114) closed simulator navigation #110 after repeated compact page/large-text/recording-status/skipped-Cancel/finished checks; [physical Watch #7](https://github.com/NakkiV7/oxhack-team/issues/7) remains open. [PR #115](https://github.com/NakkiV7/oxhack-team/pull/115) records one synthetic chat’s visible loading spinner/text/Cancel with zero external providers. Explicit UI cancellation, late-output suppression and loading with the weekly panel fully offscreen were not exercised by that run. [Watch receipt](watch-compact-navigation-2026-10-25.md), [Coach receipt](coach-loading-ui-2026-10-25.md).

## Archive/export and independent audit

The private independent audit passed at **04:56:27.978 UTC on 25 October 2026**:

- **135** tracked Native/Shared source files match the frozen commit; **127** vendor files remain unchanged from build 4.
- Archive and exported host/Watch versions are **0.1 (5)** with matching companion identities, existing unexpired distribution profiles and unchanged entitlements. Strict/deep signatures pass; `get-task-allow` is false and only Watch has HealthKit.
- All **11** checked archive/export resources match, including both first-party privacy manifests and the newly bundled `coach-guidance.json` (`72347cb0b1e2edcefc2fc386e7531c4a23c079d9048fac69808f5910ff2589b8`). No other checked resource changed from build 4. The Lite task remains `59929e1d1ee95287735ddd833b19cf4ac46d29bc7afddbbf6753c459690d574a`; its two nested models remain plaintext `TFL3`.
- Archive/export per-slice UUIDs and code-section hashes agree; dSYM UUIDs match for iPhone arm64 and Watch arm64/arm64_32.
- **Four known archive warnings** remain: two missing AccentColor assets and two skipped AppIntents metadata extractions. Export has **zero warnings**.

IPA: **25,527,303 bytes**, SHA-256 **`28479acea759e3d856715943dfd07cff61863deed7d6e04aea4575b63ae672cd`**. The ZIP contains 33 entries. Private artifacts and the independent audit are retained under ignored `.local/release/mvp-build-5/`; no signing material is published.

The app’s successful signing and unchanged vendor hashes do not resolve SDK privacy/origin-signature [#52](https://github.com/NakkiV7/oxhack-team/issues/52). The source-SDK experiment has not replaced the downloaded SDK, and this audit is not a vendor/legal or runtime attestation.

## Apple delivery and availability

Apple validation returned exit **0 / VERIFY SUCCEEDED** at **04:58:19 UTC**. Upload returned exit **0 / UPLOAD SUCCEEDED** at **05:01:13.857 UTC**, delivery UUID **`630356cb-9c2b-45f5-92c2-227a18270f1a`**.

Independent App Store Connect read-back at **05:05:16.755 UTC** confirmed the matching build ID, build **5**, `VALID`, encryption **false**, internal and external **`IN_BETA_TESTING`**, and beta review **`APPROVED`** with `submittedDate: null`. The null date does not establish a precise review timeline.

Existing **Spottr Internal** contains **5/4/3/2/1**; external **OxHack** contains **5/4/3/1**. Build 2 remains internal only. The existing 25-person [public invitation](https://testflight.apple.com/join/f3MhePbf) is unchanged. Earlier builds remain available as fallbacks; their dated receipts retain historical states.

No new public-page check, invitation acceptance, deep-link launch, actual installation, physical Watch/camera/speech acceptance or public App Store release occurred in this release check. [Installation guide](../testflight.md).

## Excluded work

Active-energy source under #102 merged later in PR #117 and is **not in build 5**, despite separate shared/recorder/store/Watch SDK checks. Running, optional anthropometrics/Health onboarding and account management remain pending; no new physiological or account-management capability is implied. The separate Gemini server, standalone Python/browser demos and source-SDK experiment are outside this binary.

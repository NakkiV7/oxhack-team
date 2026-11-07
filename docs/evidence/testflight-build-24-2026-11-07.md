# Spottr build 24 internal TestFlight delivery

At 19:00:31 UTC on 7 November 2026, App Store Connect reported Spottr **0.1 (24)** as `VALID`, with encryption classification `false` and internal state `IN_BETA_TESTING`. The exact audited IPA was assigned additively to the existing Spottr Internal group. This is internal beta delivery. Physical installation, human account and sensor acceptance, external distribution and public release have their own remaining gates.

## Source and artifact identity

Accepted functional source is `93c0a92b6f78e26ea1423758998b5a7061e1525e`. Frozen binary inputs are `3a0833d3d8cbd767e292bccd8579b79d3f020cbd`. Later changes are documentation only. The IPA remains **49,602,054 bytes**, SHA-256 `228b75832afe14276889ff3ce5e3f9324bb3fcb8230353b38741cf5167c59d75`. The signed archive, IPA and separate development Release phone and Watch bundles retain their passing audits, matching dSYMs, canonical model and 243 exact-path audio files. See the [candidate evidence](spottr-build24-candidate-2026-11-07.md).

Apple validate-only passed at 18:44:12 UTC with no errors. One guarded upload returned exit 0 and `UPLOAD SUCCEEDED with no errors` at 18:56:50 UTC. Delivery and build ID is `eff44af0-1b8c-4f53-83d7-6ef02363a65a`. The upload log also records a preceding missing uploader resume-state file error. That line is preserved with the success result and was not used to justify a retry. A persistent mode-0600 attempt intent prevents duplicate uploads even while Apple's build listing is delayed.

The bounded processing reads initially found no listed build. At 18:59:06 UTC, the actual build was `VALID`, marketing version 0.1 and encryption false. Upload success and processing acceptance are separate receipts.

## Actual beta notes and memberships

The en-GB build notes were saved with HTTP 200 and read back exactly. They describe the 53-exercise catalogue, configured camera tracking, normal account and membership requirements, optional adult analytics and real-device checks. They do not promise free beta access, active tester codes or unverified purchases.

| State at 19:00:31 UTC | Actual readback |
| --- | --- |
| Processing | `VALID` |
| Internal beta | `IN_BETA_TESTING` |
| External beta | `READY_FOR_BETA_SUBMISSION` |
| Beta review submission resource | `data: null` |
| Spottr Internal | 24, 23, 22, 21, 20, 19, 5, 4, 3, 2, 1 |
| External OxHack | 23, 22, 21, 20, 19, 5, 4, 3, 1 |

One HTTP 204 relationship request added build 24 to the original internal group. All ten previous internal builds remain. The external group retains exactly its nine previous builds and does not contain build 24. No external assignment or beta review submission was performed. No group, tester or invitation was created or removed.

## Remaining acceptance

No direct phone installation or installed-version readback has been performed for this delivery. The intended device was not reachable at this stage. Automatic TestFlight installation was not observed. The final data-preserving installation remains controller-owned and requires its own bounded device lease.

Primary provider configuration and native activation have reviewed operational evidence. Human inbox delivery, native Apple or email sign-in, passkey and Authenticator setup, recovery, explicitly typed Apple private relay email and real StoreKit offers, trial, purchase and restore remain separate acceptance checks. Monthly IAP metadata remains unresolved. Lifetime is ready to submit in the controller's latest metadata readback. Configured £10 monthly and £200 lifetime prices and an eligible two-week trial do not establish product availability or transaction success. SPOTTRTESTERS has no generated production or sandbox codes.

Real movement counting, audible cue behaviour, Health readings and paired and phone-free Watch use require the [physical acceptance and pitch checklist](../spottr-pitch-recording-checklist.md). There was no charged purchase, public App Store submission, new agreement acceptance or App Privacy publication. No external reviewer MFA access is claimed.

The source branch has not been pushed during this delivery. The controller will reconcile the final facts and read-only review addendum before source publication. Protected build 17, Vendor files, old releases, original evidence and simulator data remain preserved.

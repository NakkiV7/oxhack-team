# TestFlight build 4

Frozen source **`7f4b5ba5f5478b0efa2c18605eb0252c6f9cb3ec`**, host and Watch **0.1 (4)**. This build adds confirmed saved-workout removal and correct final-set review guidance. Relative to build 3, four Native files changed (23 insertions / 5 deletions): the three small Coach/recovery changes and corrected THIRD-PARTY source-tag attribution. The downloaded SDK, model, crypto/network behavior and shared workout rules are unchanged. The separately integrated Python contributor demo is not in this binary.

The [native acceptance receipt](saved-workout-polish-2026-10-25.md) records 16 focused passing tests, independent code review and simulator Cancel/removal/final-set checks, with synthetic data recovered privately and original preferences restored. This is separate from actual TestFlight installation and physical behavior.

## Archive, export and independent inspection

Clean committed source verified against all **130** tracked Native/Shared files; all **127** vendor files match build 3. Archive and export succeeded using the existing distribution identity/profiles, isolated caches/source and release-only build-number overrides. Team-neutral repository defaults remain unchanged.

Independent inspection of the final IPA and archive confirmed:

- Host/embedded Watch **0.1 (4)**, correct bundle/companion IDs and encryption declaration `false`.
- All four strict/deep signature checks pass. Profiles are unexpired and byte-equal to build 3; entitlements match, `get-task-allow` is false and only Watch has HealthKit.
- All **10** checked resources match archive/export/build 3, including both first-party privacy manifests and the unchanged Lite task (`59929e1d1ee95287735ddd833b19cf4ac46d29bc7afddbbf6753c459690d574a`). Its two nested models remain plaintext `TFL3`.
- Archive records **four warnings**: two missing AccentColor assets and two skipped AppIntents metadata extractions. Export records **zero warnings**.
- Per-slice archive/IPA UUIDs and code-section hashes agree; dSYM UUIDs match. Both Watch code slices independently equal build 3.

| Slice | UUID | `__TEXT,__text` SHA-256 |
| --- | --- | --- |
| iPhone arm64 | `69F5CE17-7ACB-3971-9840-F081C2B20B5E` | `ae7691ac12507d48125b5a40f27b59d34dbfc394b1fb3b71efd4088b3d9f109d` |
| Watch arm64 | `6CFC9A27-B135-3813-B258-1329C8078455` | `4124f04e300fba23016d018966616fca88ce187d6575b12571c74460bf2bdbc9` |
| Watch arm64_32 | `D73370C5-3306-384E-8A8E-0F0964596DF7` | `ae0ebfa9b1ad3751e8198c5e5601e8d4b8b66f60289382da54ebcac64df52af9` |

IPA: **24,778,314 bytes**, SHA-256 **`c05416d11395e3fe77430eaa0ae337ae5c147ca1d49bf15caf370bd66219c9f5`**. Private command/artifact/independent receipts remain under ignored `.local/release/mvp-build-4/`; signing material is not published.

The bounded crypto continuity scan found the same 14 decrypt-symbol names, no new names in the scanned cipher families and only Apple/system host dynamic dependencies. Inputs and relevant source remain unchanged from the [earlier technical classification](../release-encryption-audit.md). No full registry/call-graph audit or runtime/formal/legal attestation follows. Apple validation does not resolve the open SDK privacy/origin [issue #52](https://github.com/NakkiV7/oxhack-team/issues/52); the source experiment has not replaced this SDK.

## Apple delivery

Validation returned exit **0** / **VERIFY SUCCEEDED** at **01:23:07 UTC on 25 October 2026**. One upload returned exit **0** / **UPLOAD SUCCEEDED** at **01:26:47 UTC**, delivery UUID **`abf567ad-e275-45cf-b547-f37bc587ac44`**. No duplicate upload was attempted.

At **01:30 UTC**, the filtered App Store Connect build listing had not yet returned build 4. Upload success does not establish processing, internal/external availability, beta review or installation. Build 3 remained the accepted public TestFlight baseline at that checkpoint; the later read-back below supersedes it. No public App Store release or physical install was submitted/performed in this check.


### Processing and beta groups — 01:32 UTC

The later unfiltered app build listing returned build **4**, ID matching delivery **`abf567ad-e275-45cf-b547-f37bc587ac44`**, as `VALID`, encryption `false`, initially ready for beta assignment. The en-GB “What’s New” text was updated, then build 4 was appended to the existing internal and external groups and submitted for beta review. An initial localization PATCH including immutable `locale` was rejected before any assignment; the corrected PATCH changed only `whatsNew`.

At **01:32:12.905 UTC**, assignment read-back showed both beta states `IN_BETA_TESTING`, but the submission resource was still `WAITING_FOR_REVIEW` with `submittedDate: null`. A separate read-back at **01:32:51.286 UTC** confirmed **`VALID`**, encryption **`false`**, internal and external **`IN_BETA_TESTING`**, and submission **`APPROVED`**, still with null submitted date. The absent date does not establish a precise review timeline.

Existing **Spottr Internal** contains builds **4, 3, 2 and 1**; external **OxHack** contains **4, 3 and 1**. Earlier availability is preserved as fallback, and build 2 remains internal only. The existing enabled 25-person [public invitation](https://testflight.apple.com/join/f3MhePbf) is unchanged. The earlier public-page check was not repeated and did not select/install build 4. No public App Store release, invitation acceptance or physical phone/Watch installation occurred here. [Installation guide](../testflight.md).

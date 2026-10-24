# TestFlight build 2

Source: `b7bf563dc8c2e93a0f4e72d84de1cf7837a26749`. Version **0.1 (2)** contains the post-build-1 manual-set copy correction, audited encryption metadata and configured manual/hold discomfort-cue correction. The gateway and standalone push-up prototype run separately from this app binary.

## Archive and export

The isolated release snapshot was generated from the exact Git commit. Release-only overrides selected build 2 and the existing distribution identity/profiles; the repository retains team-neutral defaults. Archive and export both exited successfully. No new certificate, key or signing-access change was needed.

Independent final-artifact inspection established:

- iPhone `com.omarchoudhry.spottr` and embedded Watch `com.omarchoudhry.spottr.watchkitapp` both contain **0.1 (2)**, matching companion identity and `ITSAppUsesNonExemptEncryption: false`.
- Strict deep signature verification passed for both apps. Exported entitlements and embedded provisioning profiles equal the archive; profiles/entitlements also match build 1. `get-task-allow` is false.
- All ten other resource paths/hashes, including both privacy manifests and the pose task, match the archive. The model task SHA-256 is `59929e1d1ee95287735ddd833b19cf4ac46d29bc7afddbbf6753c459690d574a`.
- UUIDs and `__TEXT,__text` hashes match between archive and exported IPA for every executable slice. Export signing may change whole-executable bytes.

| Slice | UUID | Code-section SHA-256 |
| --- | --- | --- |
| iPhone arm64 | `09BE8D4F-3F7D-3CF3-807A-9AE472D20AB4` | `9edc148aac2405ceaba20996beb341e1ec8f1282e555499bd04714d6a6d3d7d2` |
| Watch arm64 | `F122FBE1-8EF7-303C-93AF-F42C1C4EF978` | `59179e8d20861cdc971b670dfc86f8753281d6c70b9219678c79343d452aa9cb` |
| Watch arm64_32 | `C42A5364-D5FC-30A1-A0B5-CACC979BF88D` | `919857c951f0c35613491b6fdc8a6ae33774bf757796bdc8df931f9cf3bcc08a` |

IPA: **24,774,269 bytes**, SHA-256 `61779379fac39bd1c459f95e01883e956f1eeefbcf45f869ae90bf9268379fe0`. Private artifacts and logs remain ignored under `.local/release/mvp-build-2/`.

## Encryption input continuity

All 130 tracked Native/Shared files match each isolated snapshot's stated source. Compared with build 1, only the two encryption metadata declarations, manual-set copy and discomfort-cue code changed (five files, 17 insertions/four deletions). All 127 vendored SDK files, model inputs, cryptographic/network source, privacy manifests, entitlements and relevant link settings are unchanged. Both nested model files remain plaintext `TFL3`. The bounded build-2 dSYM scan had the same 14 relevant symbol names as build 1, with no matches for the scanned cipher/RNG families. Independently resolved build-2 registry (`0x101ad3720`, 32 bytes) and guard (`0x101ad3740`, 8 bytes) storage is initially zero. The full build-1 initializer/reference audit was not repeated; neither this scan nor initial zero storage establishes the complete runtime call graph.

This continuity and the matching final artifacts support the existing [technical classification](../release-encryption-audit.md). Metadata or symbol absence alone is not proof; this remains an operator decision rather than vendor/legal attestation. The [SDK packaging concern](../release-readiness.md#mediapipe-distribution-remains-unresolved) remains separate.

## Apple distribution

Apple validation returned exit 0 and `VERIFY SUCCEEDED with no errors` at **24 October 2026 23:06:21 UTC**. Upload returned exit 0 and `UPLOAD SUCCEEDED with no errors` at **23:08:00 UTC**, delivery UUID `ba329de6-2a44-4c8b-b2d5-31841fad0f05`. At **23:10:33 UTC**, App Store Connect confirmed build ID `ba329de6-2a44-4c8b-b2d5-31841fad0f05` (matching the delivery UUID), `processingState: VALID` and `usesNonExemptEncryption: false`. The existing **Spottr Internal** group was explicitly assigned build 2; its state is `IN_BETA_TESTING`. Read-back confirmed both builds 1 and 2 remain internal. The external **OxHack** group still contains only build 1, which remains `WAITING_FOR_BETA_REVIEW`; build 2 is `READY_FOR_BETA_SUBMISSION` and was not submitted externally. No public App Store submission or physical installation is established by these checks.

# Release packaging

Status checked on 24 October 2026. Source checks and simulator tests do not establish archive validation, App Store processing or TestFlight availability.

## First-party privacy manifests

The generator bundles a separate `PrivacyInfo.xcprivacy` at the root of each app bundle:

| App | Required API category | Reason | Actual use |
| --- | --- | --- | --- |
| iOS | UserDefaults | `CA92.1` | App-owned Coach settings, approved plan, installation ID and skill layout. |
| iOS | SystemBootTime | `35F9.1` | Session and hold timers, elapsed intervals and secondary-camera freshness. |
| Watch | SystemBootTime | `8FFB.1` | Convert Core Motion event timestamps to absolute dates in `WorkoutRecorder`, then send recorded events to the paired iPhone. |

These declarations describe first-party API use under [Apple’s approved reasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype). They make no collected-data or tracking attestations. In particular, opt-in gateway/Gemini requests and cloud workout uploads require their own evidence-grounded privacy disclosures; these manifests do not assert that no data is collected.

`ReleasePackagingTests` inspects the actual host app’s bundled manifest, SDK metadata and identity, plus the embedded Watch app’s companion identity and manifest when present. An existing simulator build failed the initial artifact check because both manifests were absent. Regenerate the project and run these tests before relying on the resource wiring. Archive validation remains a separate check.

## MediaPipe distribution remains unresolved

The pinned MediaPipe 1.1.1 distributions are documented in [THIRD-PARTY.md](../Native/Resources/THIRD-PARTY.md). Read-only inspection found no privacy manifests in the three local XCFrameworks; `codesign -d` reported each XCFramework unsigned. All three device payloads are static archives. Their XCFramework origin signatures are separate from the app’s eventual distribution signature. The device `MediaPipeTaskGraphs_library.a` contains Abseil and Protobuf definitions and imports `_stat`, `_fstat`, `_lstat` and `_mach_absolute_time`; those imports also appear in the existing device Debug app’s `Spottr.debug.dylib`. Release archive contents have not been inspected.

The [upstream release page](https://github.com/google-ai-edge/mediapipe/releases/tag/v1.1.1) marks 1.1.1 as latest at this check. Its [official Swift package](https://github.com/google-ai-edge/mediapipe/blob/v1.1.1/Package.swift) selects the exact same three archive URLs and checksums as `scripts/fetch-mediapipe.sh`, without additional privacy-resource wiring. Switching dependency managers alone is not evidence of corrected SDK packaging.

[Apple’s SDK requirements](https://developer.apple.com/support/third-party-SDK-requirements/) include Abseil, Protobuf and SDKs that repackage listed dependencies, with manifests and signatures required for applicable binary distributions. This is a concrete packaging gap against the documented requirements; no Apple upload validator has yet confirmed how it classifies this statically linked distribution. Symbol presence does not establish every SDK call’s purpose or data practices.

Obtain a verifiable upstream distribution with the applicable manifests/signatures, or establish a documented source-build distribution path and audit the relevant call sites. Do not invent vendor declarations, replace upstream signatures with claims of Google provenance, or describe the SDK’s practices as first-party app practices. [Apple’s missing-manifest guidance](https://developer.apple.com/forums/thread/774960) distinguishes these responsibilities. The first-party manifests above do not resolve this SDK question.

For SDK authors, [Apple documents wrapping static libraries in static frameworks](https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk) to carry manifests; a bare `.a` cannot carry resources. Any such repackaging here needs explicit provenance and real declarations, rather than an unverified manifest placed beside the vendor archive.

## Signing and upload state

The generator preserves team-neutral automatic signing and existing bundle IDs: `com.omarchoudhry.spottr` and `com.omarchoudhry.spottr.watchkitapp`. Supply the approved development team as an archive/signing override; do not commit a personal team selection. The Watch target requests HealthKit and declares heart-rate/workout/motion usage descriptions. Both app icons are opaque 1024 × 1024 PNGs.

The owner verified App Store Connect record `6826666965`, with listing name **Spottr: AI Workout Coach**. Record creation is separate from an accepted build. Distribution signing, the final archive’s resources/entitlements, SDK validation and App Store processing still need verification before claiming TestFlight readiness.

## Read-only follow-up — 24 October 2026

The three device binaries were checked with `file` and bounded `nm -u` inspection. Common and Vision contain none of the scanned direct C required-reason imports. Graphs imports `stat`, `fstat`, `lstat`, `fstatat` and `mach_absolute_time`; archive members include model/resource memory mapping, general filesystem helpers, Perfetto tracing/timing, UUID, Rust and miniaudio code. The existing simulator Debug binary at `/private/tmp/spottr-profile-native/Build/Products/Debug-iphonesimulator/Spottr.app/Spottr.debug.dylib` also retains those five imports. The generator uses `-all_load`. These observations justify auditing the retained Release call sites, not declaring that every archived function runs during pose inference. Objective-C selector calls and runtime behavior are not exhausted by this scan.

`C617.1` is a possible SDK FileTimestamp reason for audited metadata access confined to app-owned model files; `35F9.1` is a possible SDK SystemBootTime reason for audited elapsed timing. Neither is a complete declaration for this distribution until the remaining bundled uses and data destinations are established. The app's first-party UserDefaults/BootTime manifest does not establish the SDK's FileTimestamp practices. [Apple's reason definitions](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons) and [Apple DTS guidance](https://developer.apple.com/forums/thread/774960) keep those responsibilities distinct.

For a documented source-build or upstream correction, [Apple's static framework recipe](https://developer.apple.com/documentation/xcode/creating-a-static-framework) supports a static archive with resources. Add the genuine SDK manifest at each supported framework bundle root and link/embed the static framework. Xcode preserves the resource framework while omitting its already-linked static binary from the embedded copy. The bare Graphs archive needs such resource-capable packaging; Common/Vision already have framework bundles but currently lack manifests. An archive must verify those resources actually survive and distinguish SDK origin signatures from final app signing. No repackaging or validation was performed by this follow-up.

[Google's current MediaPipe terms](https://developers.google.com/edge/mediapipe/legal/tos) say input processing occurs on-device while describing possible server contacts and usage/performance metadata collection, with applicable consent responsibilities. That general notice does not demonstrate the exact pinned iOS binary's behavior, but on-device inference alone cannot substantiate a vendor "no collection" declaration. Obtain build-specific upstream information or audit the relevant implementation and network behavior before making that claim.

The read-only local signing inventory found an Apple Distribution identity and 74 cached provisioning profiles, with none explicitly identifying either Spottr bundle ID. This is a local snapshot, not an account-wide profile inventory or a certificate/team compatibility check. Distribution needs an explicit App Store profile for each of `com.omarchoudhry.spottr` and `com.omarchoudhry.spottr.watchkitapp`, using the approved team's distribution certificate; the Watch profile must authorize HealthKit. The present Watch target has no separate extension target requiring a third profile. [Apple's App Store provisioning instructions](https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile/) cover watchOS as well as iOS. Profile creation/download and archive validation remain owned by the release operator. No signing keys, profile device lists or authentication values were printed.

## Packaging checkpoint, 24 October 2026 20:34 UTC

The exact staged project passed all three native release-packaging checks without warnings, including the embedded Watch manifest and companion identity (`test_sim_2026-10-24T20-34-11-129Z_pid4129_fd84a039.xcresult`). A temporary local Mach-O probe signed and verified using the existing Omar Apple Distribution identity without a password or Keychain access change. This establishes unattended access to that signing identity; it does not establish archive/export/upload acceptance. Both explicit App Store profiles are installed and documented in [provisioning](testflight-provisioning.md). No Spottr build has been uploaded to TestFlight at this checkpoint.

## Version metadata follow-up, 24 October 2026

The release operator reported an Apple validator `MissingBundleVersion` failure, captured a failing built-bundle regression, then passed all four `ReleasePackagingTests` after the fix. Both app plists now resolve `CFBundleShortVersionString` from `MARKETING_VERSION` and `CFBundleVersion` from `CURRENT_PROJECT_VERSION`. The generator supplies defaults of `0.1` and `1` for every target in Debug and Release. Update those generator defaults for later releases/builds, regenerate the project, and keep the iPhone and embedded Watch values equal. The new regression checks the actual bundled values and their equality.

Independent staged-source review confirmed those settings, valid shared-scheme target references, unchanged build phases/dependencies, and no committed signing team, identity or profile. No archive or upload was performed by that review. Rebuild and validate the corrected release archive before treating the original validator failure as resolved for distribution.

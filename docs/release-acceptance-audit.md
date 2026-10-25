# Release acceptance handoff · 25 October 2026

The next TestFlight upload remains held until root finishes integration and every applicable gate below is ready. This audit lane ran no native compiler, simulator, device, provider request, account change, Apple validation or upload. It did not touch the primary checkout.

## Evidence boundary

- Audit implementation/tests start from `origin/main` `39e112223da77a96de97701bf8ad2eea4f3f18d2` in an isolated worktree. Native source reviewed read-only in the primary checkout was **uncommitted and evolving**; this is not acceptance of a final native commit.
- Build **0.1 (5)** is frozen at `f3eae89ced8547e283bd93abe6c560c9e1ce8e2c`. Its reported physical onboarding crash remains **unresolved**. The private expanded probe reports all 135 Native/Shared inputs matched that commit, an original optimized simulator case passed, and final expanded run `06:47:32_41567da4` passed **2/2 in 138.7 s**. Earlier harness failures are retained in `.local/build5-onboarding-probe-20261025/diagnostic-report.md`. None supplies the missing device/iOS/exception/symbolicated stack or establishes a device fix.
- The primary's voice notes report **37/37** injected/silent native tests at `test_sim_2026-10-25T07-35-57-251Z_pid19864_ac46d6c7.xcresult`, including pose fixtures. The same notes report **four duplicate Objective-C classes** from SmartSpectra/MediaPipe. Passing fixtures do not resolve that SDK collision risk. This lane did not rerun that result.
- Offline audit fixtures are synthetic temporary bundles, Mach-O payloads, profiles, certificates, ZIPs and a temporary Git repository. They test rejection behavior without signing or SDK execution. Read-only inspection confirmed the actual SmartSpectra device binary parses as an arm64 iOS dynamic library with UUID/code sections, with eight runtime resource files including vendor privacy and seven model/graph files. The runtime payload pattern scan passed; development `Modules` contains example API-key assignments which the scanner deliberately rejects if shipped.
- At this review checkpoint, the primary's Presage controller/driver and preview tests existed, but no Presage/rest action was found in `TrainingStore.swift`, `SessionViews.swift` or `ConfiguredSessionViews.swift`. Root must verify its completed UI/camera integration rather than treating the standalone adapter tests as an end-to-end feature.
- The reviewed primary `TrainingStore.swift` SHA-256 was `b3d4fea1018af543dab45cc5a319eed27e022f47609f4a0b82bf14049e3dee80`; the reviewed SmartSpectra driver was `b74a0928c760ecd4e2b8c89ab531fee16f3c8b943b97caced52f3f468d290e06`. Later edits require fresh native evidence.

## Deterministic packaging audit

Run the behavior suite without a compiler or network:

```sh
python3 -m unittest discover -s scripts -p 'test_release_package_audit.py' -v
```

After root freezes the approved source commit, creates a source snapshot, copies the inspected vendor inputs, and completes archive/export, run:

```sh
python3 scripts/release_package_audit.py \
  --repo /path/to/repository \
  --source-commit FULL_APPROVED_COMMIT \
  --source-root /private/release/source \
  --archive /private/release/Spottr.xcarchive \
  --ipa /private/release/export/Spottr.ipa \
  --version 0.1 --build APPROVED_BUILD \
  --team-id APPROVED_TEAM \
  --previous-vendor-root /private/build5/source/Native/Vendor \
  --approved-vendor-manifest /private/release/approved-vendor-sha256.json \
  --secret-file /private/keys/presage-key.txt
```

All paths/build/team above are placeholders. `--secret-file` is repeatable and optional; each supplied file must be mode `0600`, contain **one raw private value**, and is read only for exact-byte scanning. Pass existing relevant gateway/provider private values this way without printing them or adding them to shell arguments. A `.env`/JSON file is not a raw-value file. Never create embedded production keys to make this audit pass. Pattern checks cover common private filenames/key assignments and private-key blocks; only supplied exact values cover opaque secrets reliably. A pass is not a proof that every possible secret format is absent.

The approved vendor manifest is a JSON object of every vendor-relative filename to SHA-256. Root must approve it from the inspected inputs **before packaging**, not derive it from the resulting app. The audit requires all frozen vendor bytes to match that inventory and preserves the previous build's complete `MediaPipe*` inventory. Record the pinned SmartSpectra 3.4.0 download SHA-256 `eb99a609fc8069de020e0cf4328fb4a81a48b0aff7499348c6aa23e6fcb09947` and vendor-origin signature receipt separately; app re-signing cannot establish vendor provenance.

The CLI emits one sanitized JSON result and exits nonzero on failure. It verifies:

- Exact tracked Native/Shared file set and bytes against the approved commit. Vendor inputs have a separate approved manifest; this does not certify compiler inputs outside those paths.
- Safe bounded IPA extraction in a private temporary directory; no duplicate/escaping/symlink ZIP entries or unexpected Payload apps. The receipt includes the IPA hash.
- Matching host/Watch identity, executable, release/build versions and encryption declarations; Watch companion linkage; frozen camera/HealthKit/motion purpose strings and both first-party privacy manifests.
- Canonical guidance, MediaPipe model/license, host-only resources, and no SmartSpectra/MediaPipe/model/graph leakage into Watch.
- Actual host dynamic dependency and embedded-framework runpath, SmartSpectra `MH_DYLIB`/iOS platform, exact vendor runtime resource hashes/privacy, and SDK UUID/code-section/dependency continuity despite re-signing. Static MediaPipe frameworks must not be dynamically embedded.
- Matching archive/export app and SDK UUID/code metadata, Info metadata and resource hashes, without assuming build 5's eleven-resource count is still correct.
- Strict deep app signatures, explicit SDK signature, same SDK/host signer, non-debug App Store profiles, matching team/application entitlements, approved entitlement scope, signer membership/expiry, and host/Watch dSYM UUIDs. An entitlement change such as App Attest fails closed and needs an intentional audited policy update.

The stale ignored `.local/release/audit-build-6.py` must not be used unchanged: it requires the entire vendor/resources/privacy set to equal build 5. This script replaces those packaging assumptions with frozen approved inputs and explicit SDK checks, preserving MediaPipe continuity. Root must also retain archive/export warning review, bounded encryption/crypto review (new SDK scope requires reassessment), vendor privacy/origin issue [#52](https://github.com/NakkiV7/oxhack-team/issues/52), Apple validation and final metadata gates. A green packaging JSON does not close them.

## Root's final native checklist

Run against the **final integrated commit** on the existing serialized compiler/simulators. Retain exact source SHA, test selectors, result bundles, warnings and failures. This lane has not executed these checks:

| Gate | Exact selector or action | Required result |
| --- | --- | --- |
| Bundle metadata | `SpottrTests/ReleasePackagingTests` | Real host/embedded Watch privacy, identity, release/build/encryption values match. Run packaging CLI again on archive and IPA; simulator output is insufficient. |
| Measurements | `SpottrTests/ProfileDataControlsTests`; `SpottrUITests/ProfileFlowTests/testMeasurementsAutosavePreserveProfileAndSurviveRestartedIntroduction`; `SpottrUITests/ProfileFlowTests/testProfileBackgroundAndDownwardDragDismissKeyboardWithoutBlockingControls` | Valid optional edits persist/clear independently; failures block losing a pending save; introduction remains a draft until completion; keyboard controls work; no measurements in Coach/cloud grounding. Run the final Core suite too. |
| Remote/local voice | `SpottrTests/RemoteVoicePlaybackTests`; `SpottrTests/VoiceFeedbackTests` | Defaults/opt-in, identity/expiry, mute/pause/background/change/stop and late completion reject correctly; immediate local stop remains available. Injected tests do not prove synthesis or audibility. |
| Presage lifecycle | `SpottrTests/PresageCaptureTests` | Consent/stationary check before SDK creation; pending-start/deadline/late callbacks rejected; current qualified samples only; no automatic retry. Core `CameraVitalsTests.swift` covers supported ranges/windows, sample times and Watch preference. |
| Front/side capture | `SpottrTests/VisionPreviewTests`; existing `SpottrTests/PoseDetectorTests`, `SpottrTests/VisionLifecycleTests`, `SpottrTests/SecondaryCameraVisionWorkerTests` | One camera owner, front preview/custom-input delivery, independent side pose, permission/cancel/background teardown and no old-frame publication. Exercise the actual completed UI wiring too. |
| Build-5 regression | `SpottrUITests/ProfileFlowTests/testLocalOnboardingRequiresAGoalAndCanBeRestartedWithoutErasingProfile`; private `SpottrUITests/Build5OnboardingVariantTests` on the preserved probe | Expanded private methods: `testAllGoalsRegularPracticeAndSevenDaysMountEveryTabAndPersistBlankName`, `testMobilityStartingOutAndUnicodeNameCompleteWithKeyboardOpenAndMountEveryTab`. Preserve the frozen probe; repeat the scenarios on integrated source separately. A pass still cannot explain the physical build-5 crash. |
| SDK collision | Final optimized pose fixture and launch log review with both SDKs linked; actual device path below | Identify/resolve or explicitly gate duplicate Objective-C classes. Never drop the duplicate-class warning because fixture tests pass. |

## Physical/provider and distribution gates

1. Obtain the affected build-5 device/iOS and actual crash or jetsam report, match build-5 dSYM, distinguish trap/exception/watchdog/memory termination, and validate a supported fix on the affected path. Keep unresolved status explicit until then.
2. Root coordinates existing physical phone/Watch only: onboarding completion/cold launch/all tabs, keyboard/measurements persistence, camera permissions and foreground/background lifecycle, front/side orientation, actual Watch pairing/permissions/fresh original timestamps/report source labels. Software replays do not establish sensors or actual pairing.
3. Voice setup/discovery is configuration evidence only. Audible route, interruptions, timing, local stop and selected provider voice require root's explicitly authorized acceptance; no automatic paid retries or inferred voice identity.
4. Before any Presage authentication/capture, finish the accurate numeric-sharing disclosure and explicit opt-in, private configuration/authentication choice, camera-ownership/UI integration and quota decision. Keep unavailable states honest. Only root may perform the separately authorized single bounded physical attempt, retaining actual duration/quality/cancellation/usage without frames or keys. Fixture values are never real vitals.
5. Only when everything is ready: root freezes the source, records archive/IPA hashes and audit output, resolves remaining SDK/crypto/privacy gates, validates with Apple, verifies final test instructions/metadata, and controls upload and build processing/group readback. Packaging, Apple processing, TestFlight availability and physical acceptance remain separate claims. No upload was performed here.

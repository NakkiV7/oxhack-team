# Reduced Pose SDK compile attempt — 25 October 2026

**The one authorized compile failed; no complete SDK was produced or integrated.** Configured [analysis and dependency query](sdk-pose-analysis-2026-10-25.md) had passed for the reduced Pose variant. Actual compilation now exposes an Abseil module-export error in the iOS arm64 simulator slice. This is progress beyond the [stock target analysis failure](sdk-source-build-attempt-2026-10-25.md), not resolution of SDK privacy/origin-signature issue #52.

## Frozen inputs and execution

The attempt used exact MediaPipe source `50505c8312c7eacb1bd411cecdc4cc9fd08d53cb`, the reviewed additive `SpottrPoseCommon_framework`, `SpottrPoseTaskGraphs_library` and `SpottrPoseVision_framework` targets, and the retained nested OpenCV jobs-two patch. Original stock targets remained intact. The source patch SHA-256 is `d4fac4e2dd35e60bfc62dbb34621167b43ed1ffac818027c1e72a28f615f416e`; top-level working iOS BUILD SHA-256 is `07bba5b04e8992f7ace10503628e48b4a1341459db6de483d7c317fe3a287cb6`. No dependency versions, missing-feature stubs or later upstream source were added.

The private command reused the successful analysis argv, removing **only `--nobuild`**. It used Bazel 7.7.0, existing Xcode 27.0 (27A266a), the `ios_sim_device_fat` configuration, existing Temurin 21, a 1 GiB JVM heap, jobs two and private caches/output directories. The actual resolved OpenCV build-command behavior was checked before launch: device and simulator nested `xcodebuild` invocations both use two jobs even with a synthetic 64-CPU input.

Root released the native compiler lane. Bazel PID/process group `26393`, primary monitor `26326`, and independent fast monitor completed; tool sessions `81560` and `95549` ended. An exact post-run PID check found Bazel and the primary monitor absent. No retry followed the error.

| Actual result | Evidence |
| --- | --- |
| Exit 1, compiler failure | Bazel elapsed **315.082 s**, critical path **35.26 s**; guarded run **327.42 s**, `stopReason: null` |
| Work performed | **6,799 processes**: 5,802 internal and 997 Darwin sandbox actions; partial objects are not a completed SDK |
| Sampled resource bounds | Peak task storage **5,932,380,160 bytes**; minimum free **55,287,418,880 bytes**; peak aggregate descendant RSS **1,042,415,616 bytes**; sampled pressure levels 1/2 |
| Enforced limits | 1,160-second guard within a 1,200-second execution/cleanup allowance; task storage 21 GiB maximum, free reserve 33 GiB minimum, aggregate RSS 3 GiB maximum, stop on critical pressure |

The primary monitor recorded 19 samples and the independent fast monitor 153. These are sampled observations, not a continuous peak measurement. No resource or time guard fired. Existing libc++ deployment-platform and Bazel configuration warnings remain in the log; this was not a warning-free build.

## First concrete blocker

Target `@@abseil-cpp~//absl/log/internal:log_message` failed at `external/abseil-cpp~/absl/log/internal/log_message.h:43:10`:

```text
error: module abseil-cpp~//absl/log/internal:log_message does not depend on
 a module exporting 'absl/base/internal/errno_saver.h'
```

The fresh simulator `.d` file identifies `iPhoneSimulator27.0.sdk` and an expected simulator `log_message.o` that is absent. Host and iOS device object files exist with earlier timestamps. The host-configured `wrapped_clang_pp` executable path in the diagnostic does **not** identify the compiled slice.

Read-only inspection found that the resolved Abseil BUILD already declares `//absl/base:errno_saver`. Generated module maps for all three configurations also contain its `use`/`extern module` edge; `errno_saver.cppmap` names the expected textual header. The root cause is therefore unresolved. A next bounded investigation should inspect the failing simulator compile arguments and header/module ownership before proposing a change. No redundant dependency line, disabled layering check, toolchain compatibility change or rebuild was attempted.

## Partial outputs and retained evidence

A **41,086-byte** `SpottrPoseVision_framework.xcframework.zip` was emitted, containing the upstream macro's public headers and dummy static archive component for device/simulator. SHA-256: `35e9b8ab3d58fb89ecc0673d34151009328e7ace08aae813b056fddd8297adb1`. This is not a usable three-component SDK: Common/Graphs did not complete, and the Vision component alone establishes neither successful linking nor inference.

Private evidence remains under ignored `.local/sdk-source-build-20261025/`:

- `pose-compile-receipt.json` — command, budgets, result, source hashes, output inventory and per-file evidence hashes. SHA-256: `e7c52e1fa6f04308ecc6ac5ad736cbc35177cf624ebd9d3ae8976a5622108fa3`.
- `logs/pose-compile.log` — complete compile log. SHA-256: `1aea07373a593a5004233f6514bede6a4dd5c374f0d416261f976bc5a22a5288`.
- `logs/pose-compile-resources.jsonl` and `logs/pose-compile-fast-resources.jsonl` — resource observations; `logs/pose-compile-opencv-cap.log` — resolved nested jobs check.
- `pose-compile-slice-evidence.json`, `pose-compile-failure-inputs/` and `pose-compile-partial-outputs.json` — object/dependency-file existence, source/module-map copies and partial artifact hashes.

The frozen analysis receipt remains `a75c95717704152eadd972977d40e11172d8eb848c902773c1ba0b15ccb13a7e`; the earlier stock-attempt receipt remains `2c6c42c183c5a5055478a3b83548c355c1265f7a3b248c0d56b4aef52ac2a823`.

The remaining gates are a reviewed explanation/fix for this compiler failure, complete device/simulator components, component layout/link and duplicate-symbol checks against Spottr's actual Swift API usage, real inference, resource/privacy inspection, and an accepted publisher-signature/provenance path. No app SDK switch, signing/trust change, privacy declaration or runtime acceptance follows from this attempt.


## Follow-up hypothesis, not a confirmed repair

Independent read-only diagnosis found that the observed failure is consistent with LLVM’s [relative extern-module path-growth bug](https://github.com/llvm/llvm-project/commit/1e10f9a8222227ad665a1b9cd73ed27f5bc21845). That upstream fix describes a misleading strict module-dependency diagnostic when a recursive path exceeds the platform limit. Our constructed sandbox-sized module-header spelling exceeded macOS’s 1,024-byte path limit and a read-only stat reproduced `ENAMETOOLONG`; the original compiler’s failing syscall was not captured. Correct BUILD/module-map edges and successful host/device objects support investigating this mechanism, rather than adding a redundant dependency.

The concrete next experiment changes only to a shorter task-owned sandbox base, with the same source/pins/module checks and explicit combined disk/RAM/time limits. It is not yet evidence of a compiler repair. Do not disable layering checks or adopt an unpinned dependency/toolchain on the strength of this hypothesis.

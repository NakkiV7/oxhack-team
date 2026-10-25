# Reduced Pose SDK analysis — 25 October 2026

**Configured analysis and dependency query passed; no SDK compilation occurred.** A private, additive Pose API variant at exact MediaPipe source `50505c8312c7eacb1bd411cecdc4cc9fd08d53cb` bypassed the stock target graph's absent packages. This changes the public API scope: it is **not** an equivalent stock Google distribution, an integrated Spottr dependency or a resolution of SDK privacy/origin-signature issue #52.

## Original RED and reviewed variant

The [original attempt](sdk-source-build-attempt-2026-10-25.md) failed with missing `tasks/ios/text/text_summarizer` during Common analysis. Its source, log, receipt and original jobs-two patch remain unchanged. Further static inspection found four missing package families directly referenced by the tagged top-level iOS BUILD: iOS text summarizer, iOS text proofreader, new iOS interactive segmenter and new C++ interactive segmenter. Existing legacy interactive-segmenter sources are separate.

Only the private working checkout under ignored `.local/sdk-source-build-20261025/` changed. All original BUILD content remains byte-for-byte as a prefix; three new target labels and their graph helper were appended. The existing WORKSPACE/OpenCV jobs-two patch was retained, without dependency-version changes, missing-feature stubs or later-source borrowing.

| Additive target | Scope | Component bundle name |
| --- | --- | --- |
| `//mediapipe/tasks/ios:SpottrPoseCommon_framework` | Eight upstream LiteRT C dependencies, OpenCV, Metal shared resources and actual Pose Objective-C implementation closure; graph separation retained with `avoid_deps` | `MediaPipeTasksCommon` |
| `//mediapipe/tasks/ios:SpottrPoseTaskGraphs_library` | Flow limiter, Pose graph and LiteRT inference roots; graph helper retains `alwayslink=1` | `MediaPipeTaskGraphs_library` |
| `//mediapipe/tasks/ios:SpottrPoseVision_framework` | Thirteen existing public header outputs forming the project-quoted import closure of Pose headers plus MPPCommon | `MediaPipeTasksVision` |

The Graphs bundle name deliberately matches the stock name for later layout inspection. Familiar component names do not establish Google publisher provenance or binary/API equivalence. The variant removes public audio/text/retrieval and other Vision task entry APIs; it targets Spottr's existing `PoseDetector.swift` video/image/options/landmark surface. That Swift surface has not yet been compiled against these outputs.

The exact [reproducible source patch](../../integrations/mediapipe-source/README.md) is included for contributors. Patch SHA-256: `d4fac4e2dd35e60bfc62dbb34621167b43ed1ffac818027c1e72a28f615f416e`. Working top-level iOS BUILD SHA-256: `07bba5b04e8992f7ace10503628e48b4a1341459db6de483d7c317fe3a287cb6`. The pristine source and previous attempt's manifest/history were preserved.

## Executed checks

Root released the native compiler lane before execution. Both commands reused private Bazel **7.7.0**, existing Xcode **27.0 / 27A266a**, JVM heap **1 GiB**, Bazel **jobs 2**, the exact pinned dependencies and the prior private tool/cache configuration. `build --nobuild` explicitly disabled compilation; `cquery` inspected configured dependencies. No native app build or SDK integration was performed.

| Command | Actual result | Guarded wall time |
| --- | --- | --- |
| `build --nobuild` on all three additive targets | Exit **0**; **424 packages / 24,605 targets configured**, **0 total actions**. Bazel elapsed **50.955 s**. | **58.76 s**, within 300-second budget |
| `cquery 'deps(set(...three additive targets...))' --output=label` with identical configuration | Exit **0**, **0 total actions**. Bazel elapsed **11.014 s**. | **17.53 s**, within 120-second budget |

Exact arguments, expected-versus-observed state and prior RED hash are retained privately in `pose-analysis-preparation.json` and `pose-analysis-receipt.json`. This is a stock-graph failure followed by a **reduced-scope** analysis pass, not a same-API build fix or a compiled SDK regression pass.

The actual cquery returned **20,587 configured label lines**, or **17,994 distinct labels ignoring configuration**, including source files, toolchains and external repositories. Those counts are not compiled object counts. Inspection confirmed:

- None of the four absent package families or their subpackages appear.
- Pose graph, actual Pose Objective-C implementation, flow limiter and explicit LiteRT inference roots appear.
- The existing `interactive_segmenter_legacy/proto:region_of_interest_cc_proto` remains, required by shared `MPPVisionPacketCreator`; removing every interactive-segmenter path would be incorrect.
- The queried closure contains no iOS audio/text/retrieval or other Vision task API labels from the checked feature families, and no iOS core Text-labelled target. It still contains **1,804 distinct LiteRT labels**. This is not proof of minimal code size, absent data collection or removal of every non-Pose implementation path.

The cquery labels and checked predicates are retained as `pose-cquery-labels.txt` and `pose-cquery-closure.json`. No complete compile/link/runtime closure has been accepted.

## Bounds, warnings and retained evidence

The repaired watcher retained fail-closed cleanup and descendant-RSS sampling. A separate fast watcher enforced wall-clock/free-space/memory/critical-pressure limits independently of potentially slow `du` scans. Protective thresholds were **21 GiB task allocation / 33 GiB free**, inside the authorized **22 GiB / minimum-32-GiB** boundaries; internal deadlines were 285/105 seconds to leave cleanup headroom within 300/120 seconds. JVM/task-RSS limits remained 1/3 GiB.

Observed task allocation reached **5.43 GiB**, minimum sampled/final free space **51.48 GiB**, and peak sampled aggregate descendant RSS **0.62 GiB**. System pressure was warning/normal (`2`/`1`), never critical. These are samples, not instantaneous guarantees or performance benchmarks. Bazel PIDs **22261** and **23646** exited; both watchers ended and the compiler lane was released. No task build/query process remains.

Warnings remain: output path contains a space; upstream resolution selects `bazel_skylib` 1.9.0 over the root's 1.8.2 request; Python-toolchain precedence; duplicate repository imports; deprecated local-resource flag names. None caused failure here, and no dependency or trust override was added to suppress them. No signing, Native/project files, privacy manifest, trust store, global Xcode selection, existing cache cleanup, simulator or provider configuration changed.

| Private artifact | SHA-256 |
| --- | --- |
| `pose-analysis-receipt.json` | `a75c95717704152eadd972977d40e11172d8eb848c902773c1ba0b15ccb13a7e` |
| `logs/pose-analysis.log` | `6d805109e41739b1a32599f6adc2b5eabfe1a65397bc5ae00c737029e9aa009f` |
| `logs/pose-cquery.log` | `37be19138ed9f2b157d8aa14efe6743752d09899384f867e95e395e9d24c4734` |

## Remaining gate

A separately budgeted compilation must establish actual device/simulator outputs, valid archive formats/platform metadata, module/header imports, Common/Graphs symbol ownership, duplicate-definition behavior and Pose graph registration. Then test the existing Swift detector API and blank/known-pose inference fixtures. Analysis did not run those checks or prove Xcode compilation compatibility.

The existing packaging macro still discards framework metadata/resource arguments; this analysis does not produce resource-capable privacy bundles. Retained-dependency/API-purpose/data-practice audit, genuine manifest rationale, local publisher/origin signing review, Release app/archive validation and physical camera acceptance remain separate work. No privacy declaration, Google binary provenance or distribution readiness follows from this pass. Keep the current app dependency and issue #52 unchanged.

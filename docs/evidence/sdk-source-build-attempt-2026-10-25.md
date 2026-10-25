# MediaPipe source-build attempt — 25 October 2026

**Stopped at a concrete source-graph failure; no SDK binary was compiled or integrated.** The prepared three-target build of release commit `50505c8312c7eacb1bd411cecdc4cc9fd08d53cb` reached Bazel analysis, then failed because the release references an absent iOS text-summarizer package. This advances the [source-build plan](../sdk-source-build-plan.md) from research to an actual failed attempt; it does not resolve [SDK issue #52](https://github.com/NakkiV7/oxhack-team/issues/52), privacy declarations or origin signing.

## Inputs and boundaries

All task files remain in ignored `.local/sdk-source-build-20261025/`. A fresh shallow upstream checkout resolves to the exact release commit, and its tracked source remains pristine. All five file hashes recorded in the plan matched. A separate working checkout contains only the build-parallelism patch below. No Native/project/vendor distribution, signing, trust store, global Xcode selection, credentials or simulator was changed; no existing cache was cleared or repurposed. No app build, provider/physiology request, installation or UI action was performed in this attempt.

| Input | Selected and verified |
| --- | --- |
| Xcode | Existing `/Applications/Xcode.app`, **27.0 / 27A266a**; per-command `DEVELOPER_DIR` and `--xcode_version=27.0`. iOS/device/simulator SDK 27.0. No older Xcode was installed. |
| Bazel | Private **7.7.0** arm64 executable, 52,899,858 bytes; SHA-256 `2533ddc8628a96d1da3c5e99f45442d30fec93ee724316fd9687c78e56a84049`, matched [upstream checksum](https://releases.bazel.build/7.7.0/release/bazel-7.7.0-darwin-arm64.sha256). Version command passed. |
| CMake | Installed 4.4.3 exceeds the tagged OpenCV rule's stated M1 limit. Private portable **3.24.0** was extracted and version-checked; its 72,801,419-byte archive matched [Kitware's checksum list](https://github.com/Kitware/CMake/releases/download/v3.24.0/cmake-3.24.0-SHA-256.txt): `3e0cca74a56d9027dabb845a5a26e42ef8e8b33beb1655d6a724187a345145e4`. No installer or global replacement. |
| Java / Python | Existing Temurin **21.0.10** selected for the Bazel server, JVM heap capped at 1 GiB. Upstream remote-JDK-21 settings retained; hermetic repository Python selection **3.11**. Existing system Python **3.9.6** selected for legacy OpenCV scripts. No package installation. |
| OpenCV | Exact **4.5.3** ZIP matched the release WORKSPACE hash `a61e7a4618d353140c857f25843f39b2abe5f451b018aab1604ef0bc34cd23d5`. No dependency-version upgrade or replacement. |

The command used the plan's Common, Graphs and Vision targets with `-c opt`, `--config=ios_sim_device_fat`, `--apple_generate_dsym=false`, `OPENCV=source`, disabled LiteRT FST constraints/HuggingFace tokenizer, and explicit `--jobs=2`. System/home rc files were disabled; only the recorded upstream workspace rc was loaded. The clean working checkout had no imported `.configure.bazelrc` or `.user.bazelrc`. Repository/output/temp/pip caches were task-owned. Exact arguments and nonsecret environment overrides are retained in `build-config.json`.

Bazel warned that the output path contains a space and that upstream resolution selects `bazel_skylib` 1.9.0 instead of the root module's 1.8.2 requirement. These warnings were retained; neither was the reported failure. No no-space alias or module-version override was applied.

## Nested parallelism, checked before the build

OpenCV's pinned `platforms/ios/build_framework.py` constructs `xcodebuild -jobs multiprocessing.cpu_count()`; environment variables alone do not cap it. The private working patch registers `third_party/opencv_ios_jobs2.diff` in WORKSPACE and changes only that argument to two. The pristine checkout is unchanged, and dependency URLs/hashes remain pinned.

An isolated behavior check of the exact ZIP's `getBuildCommand` with a synthetic 64-CPU host failed before the change (64 jobs), then passed after applying the patch for both device and simulator (two jobs). It launches no OpenCV compilation. `CMAKE_BUILD_PARALLEL_LEVEL=2`, `MAKEFLAGS=-j2` and `OMP_NUM_THREADS=2` were also set. Bazel never reached the OpenCV action, so this is patch/preflight acceptance, not an observed nested build result.

Full private source patch SHA-256: `904e08f4203c75f30c340082d8c5e5fb2dbf5ea163e8d56b8f8ed36f65fb8c53`. No packaging/API-removal patch was applied.

## Execution and first concrete failure

The first guarded invocation began at **01:07:40 UTC** and was terminated at approximately **01:09:35 UTC** after the private watchdog encountered a transient `du` error while LLVM's temporary directory disappeared. The monitor incorrectly raised on a nonzero `du` status despite a returned total. The owning Bazel process group was explicitly terminated; this interruption is not an SDK result.

The watchdog was repaired to accept a returned total with the transient warning, fail closed if no usable measurement exists, reap its owned process on monitoring errors/timeouts, and aggregate descendant RSS even across process groups. Three private behavior checks passed: transient-directory handling, missing-measurement cleanup and timeout cleanup. The defect and original monitor/log are preserved.

The same target command resumed once from its private caches at **01:10:36 UTC**, with a remaining **1,350-second** guard budget. It ended at **01:10:56 UTC**, exit **1**, after **17.386 seconds** reported by Bazel / **20.36 seconds** including monitor overhead. The combined interrupted/resumed build-command span was about 135 seconds, below the 25-minute limit. No dependency/source-functionality retry followed this failure:

```text
ERROR: no such package 'mediapipe/tasks/ios/text/text_summarizer': BUILD file not found
ERROR: .../mediapipe/tasks/ios/BUILD:442:29: ... referenced by
'//mediapipe/tasks/ios:MediaPipeTasksCommon_framework'
ERROR: Analysis of target ... failed; build aborted: Analysis failed
ERROR: Build did NOT complete successfully
```

The [pinned BUILD](https://github.com/google-ai-edge/mediapipe/blob/50505c8312c7eacb1bd411cecdc4cc9fd08d53cb/mediapipe/tasks/ios/BUILD#L171) includes `MPPTextSummarizer` in `MEDIAPIPE_TASKS_COMMON_DEPS`; lines 442–455 use that list for Common. The pristine commit's tracked text-package listing contains no `text_summarizer` directory/BUILD. This confirms a mismatch inside the chosen source release rather than an incomplete working checkout. Source BUILD SHA-256 remains `0dfd73f0f4777fbbddcabc58e0eeded700fa8e6ddc1ff3774d40220c25133b0d`.

## Resource and provenance receipt

Preflight found approximately **59 GiB free**, 16 GiB physical RAM and warning-level memory pressure (`2`, not critical). Guards enforced a 3 GiB aggregate resident-memory ceiling, a 25-minute combined build budget, and protective stops at 22 GiB task allocation / 32 GiB free, inside the authorized 24 GiB / minimum-30-GiB limits. Observed pressure remained `2`. The retained task tree is **4.18 GiB**, the minimum sampled/final free space was **54.67 GiB**, and peak sampled descendant RSS was **0.44 GiB**. These are sampled resource observations, not performance benchmarks or guaranteed instantaneous peaks.

Initial Bazel PID/PGID **6962** and resumed **8982** are gone; the monitors ended. No task build process remains, and the native build lane was released. Private command/resource logs, input hashes, patch, missing-package tree listing and final receipt remain under the ignored task directory:

- `attempt-receipt.json`: SHA-256 `2c6c42c183c5a5055478a3b83548c355c1265f7a3b248c0d56b4aef52ac2a823`.
- `logs/build-resume.log`: SHA-256 `28c1c343a916529defc624a871e285f167dd0f476522de6e7998689087f54e6d`.
- `build-resume-result.json`: SHA-256 `23eb8bff7a815b9a740b5d53831e7e933509f08f33b55ad6c9599f2251c7e266`.

## Next reversible step

Before another build, review the Common/umbrella-header dependency closure at this exact pin. Prepare a separately reviewed local target variant that excludes unavailable text APIs **only if** the complete Vision/Common/Graphs closure required by Pose Landmarker remains intact. Capture a failing/passing analysis regression before compilation. Do not add empty placeholder targets, borrow unpinned source files, silently upgrade dependencies or describe a reduced API surface as an equivalent stock Google distribution. No such functional patch was made here.

A successful later build would still require platform/output inspection, graph-registration and known-pose inference checks, a complete retained-dependency/API-purpose/data-practice audit, resource-capable manifests with genuine rationale, publisher/origin signing review and app/archive acceptance. Xcode 27 compatibility, SDK compilation, binary equivalence, privacy declarations and physical camera behavior remain unestablished. Keep the current app dependency and issue #52 status unchanged.

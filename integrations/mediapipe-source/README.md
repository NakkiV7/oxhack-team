# Experimental Pose-only source build

This optional source experiment is separate from Spottr’s working downloaded SDK. It adds three reduced Pose API targets to the exact MediaPipe release source, preserving original targets. **Do not substitute its outputs into the app.** Analysis passed; compilation, Swift imports, graph registration, resource packaging, privacy declarations and publisher/origin review remain separate gates. [Analysis receipt](../../docs/evidence/sdk-pose-analysis-2026-10-25.md), [build/packaging plan](../../docs/sdk-source-build-plan.md).

## Reproduce the source patch

Use an isolated checkout with sufficient task-owned disk/RAM/time limits. Never run in the app’s vendor directory or change global Xcode/caches.

```sh
git clone --depth 1 --branch v1.1.1 https://github.com/google-ai-edge/mediapipe.git mediapipe-pose
cd mediapipe-pose
git rev-parse HEAD
# Must equal 50505c8312c7eacb1bd411cecdc4cc9fd08d53cb.
git apply --check /absolute/path/to/oxhack-team/integrations/mediapipe-source/pose-only.patch
git apply /absolute/path/to/oxhack-team/integrations/mediapipe-source/pose-only.patch
```

Patch SHA-256: `d4fac4e2dd35e60bfc62dbb34621167b43ed1ffac818027c1e72a28f615f416e`. It changes only the OpenCV nested-job cap and adds named Pose targets/header selection; it contains no missing-package stubs, borrowed later sources or dependency upgrades. The original stock graph fails on absent upstream packages. This reduced public API is not equivalent to Google’s stock distribution.

Use the plan’s exact Bazel 7.7.0/Xcode/private-cache configuration and the same explicit jobs-two limits. Replace its three stock labels with:

```text
//mediapipe/tasks/ios:SpottrPoseCommon_framework
//mediapipe/tasks/ios:SpottrPoseTaskGraphs_library
//mediapipe/tasks/ios:SpottrPoseVision_framework
```

First run `build --nobuild` with the plan’s flags, then configured `cquery` for the three targets. Repository rules can still download/execute during analysis. Record the toolchain, resolved inputs, full local diff, command/result and resource bounds. Set a process-tree deadline and fail closed on unavailable disk/RAM monitoring. Compilation requires a separate resource budget. The historical independent analysis receipt is not a guarantee on another toolchain.

The source context is from Google AI Edge MediaPipe at the pin above, under [Apache 2.0](../../Native/Resources/MediaPipe-LICENSE.txt). The dated additions/job-cap patch are local Spottr modifications. Preserve upstream notices and audit transitive licenses before distribution. A successful build alone establishes neither Google provenance nor a privacy declaration; [issue #52](https://github.com/NakkiV7/oxhack-team/issues/52) remains open.

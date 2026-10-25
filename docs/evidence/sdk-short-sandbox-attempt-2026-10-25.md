# Short-sandbox SDK attempt — 25 October 2026

**Timed out; the path-length hypothesis remains inconclusive.** One bounded incremental compile used the same reduced Pose targets, sources, pins and compiler checks as the [first actual compile](sdk-pose-compile-attempt-2026-10-25.md). The time guard stopped it before the previously failing simulator object was produced. No complete SDK, app integration or privacy/signature resolution resulted.

## Hypothesis and unchanged inputs

The first compile reported an Abseil `errno_saver.h` module-export error despite the dependency being declared in BUILD and generated module maps. Read-only follow-up found recursive module-map header spellings close to macOS's 1,024-byte path limit; adding the retained sandbox prefix produced a 1,039-byte spelling and `ENAMETOOLONG`. That reconstructed filesystem check did not retain the original compiler's exact sandbox or system call.

An [official LLVM fix](https://github.com/llvm/llvm-project/commit/1e10f9a8222227ad665a1b9cd73ed27f5bc21845) describes this mechanism: recursive relative `extern module` paths can exceed the OS limit and cause a misleading strict-module-use error. Whether the installed Apple compiler contains that fix is unknown. This justified a short-sandbox experiment, not disabling compiler checks.

The authorized follow-up retained exact MediaPipe source `50505c8312c7eacb1bd411cecdc4cc9fd08d53cb`, patch SHA-256 `d4fac4e2dd35e60bfc62dbb34621167b43ed1ffac818027c1e72a28f615f416e`, Bazel 7.7.0, Xcode 27.0, jobs two, nested OpenCV jobs two and a 1 GiB JVM heap. It requested the same three additive targets: `SpottrPoseCommon_framework`, `SpottrPoseTaskGraphs_library` and `SpottrPoseVision_framework`. No source, dependency, toolchain, module/layering check or public API scope changed.

Only two build arguments were added: `--sandbox_base=/private/tmp/sp-avqeztck` and `--verbose_failures`. Actual Darwin action sandboxes were observed under that task-owned temporary root. There was one attempt and no subsequent retry.

## Guard preflight and terminal result

Before launch, the private monitor was extended to sum **both** the existing build tree and the temporary sandbox. Its behavior checks first failed for the missing two-root API, then passed **3/3**: real allocated files in both roots count, an unmeasurable root fails closed, and a combined over-limit sample terminates/reaps its child. The separate fast wall/RSS/free/pressure watchdog remained active.

| Check | Actual result |
| --- | --- |
| Time limit | Guard **560 s**, within **600 s** including cleanup |
| Terminal result | Exit **143**, `stopReason: time limit`, guarded duration **561.17 s** |
| Execution plus temporary sandbox cleanup | **575.62 s**, within the authorized ten minutes |
| Sampled storage | Peak combined owned storage **6,187,339,776 bytes**; minimum free **54,215,827,456 bytes** |
| Sampled memory/pressure | Peak aggregate descendant RSS **993,935,360 bytes**; pressure levels 1/2 |
| Enforced resource limits | Combined owned roots ≤21 GiB; free space ≥33 GiB; aggregate RSS ≤3 GiB; stop on critical pressure |

There were 38 primary and 270 fast samples. These are sampled observations, not continuous peaks. The time guard fired; no disk, RSS or critical-pressure guard fired. Existing compilation warnings remained.

The final logged progress was `[10,056 / 13,819] Compiling tflite/delegates/xnnpack/moe_delegate_kernel.cc`. No compiler `ERROR:` line was observed before interruption. The original failing simulator `log_message.o` is still **absent**, and its `.d` retains the first attempt's timestamp/hash. Absence of another error therefore does **not** show that the simulator action passed or that the shorter sandbox solved the problem.

Bazel PID/process group `39902`, monitor `39893`, and tool sessions `36218`/`87963` ended. Exact build/monitor PID checks and a check of all sampled descendant PIDs found none remaining. Only the owned `/private/tmp/sp-avqeztck` root was removed after an inventory; its absence was verified. Existing caches and other workloads were preserved, and the native compiler lane was released.

## Retained evidence and remaining gate

Ignored `.local/sdk-source-build-20261025/` contains:

- `short-sandbox-receipt.json`: exact command, two-root preflight, limits, result, cleanup, source/evidence hashes. SHA-256 `3431f5582b0069ae72031d8ad5a7448cecebedc8533a21d5cc1a05b67af336f0`.
- `logs/short-sandbox.log`: full interrupted compile log. SHA-256 `88d8be8778f1c63cf6818cf89161007e72b7a4fb39fb7868ac3beffb6be93a53`.
- `logs/short-sandbox-resources.jsonl`, `logs/short-sandbox-fast-resources.jsonl`, guard RED/GREEN logs, `short-sandbox-guard.py`, its behavior tests and `short-sandbox-partial-outputs.json`.
- `abseil-module-review.md`: the read-only slice/path diagnosis and its limits.

The original stock-attempt, successful [analysis](sdk-pose-analysis-2026-10-25.md), and first-compile receipts remained byte-for-byte unchanged. The only top-level packaged output remains the same **41,086-byte Vision header/dummy component** from the prior attempt, with SHA-256 `35e9b8ab3d58fb89ecc0673d34151009328e7ace08aae813b056fddd8297adb1`; Common/Graphs did not complete.

A later separately authorized investigation would need actual acceptance of the failing simulator action before claiming a path-length fix. Full component completion, Spottr API/link checks, real inference, resources/privacy and publisher-signature provenance remain separate gates. No further SDK attempt is planned in this task.

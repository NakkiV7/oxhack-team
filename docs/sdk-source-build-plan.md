# MediaPipe 1.1.1 source-build and packaging plan

Research checkpoint: **25 October 2026, 00:51 UTC**. This is an execution handoff, not a successful build or a privacy attestation. No SDK build, package installation, binary download, signing, upload, or application change was performed for this document. [Issue 52](https://github.com/NakkiV7/oxhack-team/issues/52) remains open; Apple processing of Spottr build 3 does not resolve it. Existing binary observations are in [release readiness](release-readiness.md#mediapipe-distribution-remains-unresolved) and the separate [encryption audit](release-encryption-audit.md).

A later [bounded build attempt](evidence/sdk-source-build-attempt-2026-10-25.md) reached source analysis and stopped at an absent upstream package; no SDK was compiled or integrated. The prepared recipe below remains the historical research handoff.

The later [reduced Pose variant](../integrations/mediapipe-source/README.md) passed configured analysis and exposes its exact patch. This is a reduced API experiment, with no replacement of the app dependency.

## Resolve the source identity first

The official [1.1.1 release](https://github.com/google-ai-edge/mediapipe/releases/tag/v1.1.1) resolves to **`50505c8312c7eacb1bd411cecdc4cc9fd08d53cb`**. Its [Package.swift](https://github.com/google-ai-edge/mediapipe/blob/50505c8312c7eacb1bd411cecdc4cc9fd08d53cb/Package.swift) selects the same three Google ZIP URLs and SHA-256 values as our [fetch script](../scripts/fetch-mediapipe.sh). No corrected distribution was identified in the official release/package examined at this checkpoint; changing to that Swift package would select those same binaries.

The earlier [THIRD-PARTY.md](../Native/Resources/THIRD-PARTY.md) attribution called `d761bb9a3fdc2135ebf046a093a99b95484897dc` the source revision. That attribution has been corrected to the release-tag identity. That is a [24 October audio-performance commit](https://github.com/google-ai-edge/mediapipe/commit/d761bb9a3fdc2135ebf046a093a99b95484897dc), [37 commits after the release](https://github.com/google-ai-edge/mediapipe/compare/50505c8312c7eacb1bd411cecdc4cc9fd08d53cb...d761bb9a3fdc2135ebf046a093a99b95484897dc). It is not the release tag. Retain the verified binary hashes, separately record the source-build pin, and do not assert which source produced Google’s ZIPs without upstream build provenance.

## Exact build inputs

Use a fresh, isolated checkout of the full release commit above, outside the app checkout. Preserve the pristine tree plus any packaging patch. These are source-derived requirements, not a toolchain combination tested here:

| Input | Pinned upstream evidence |
| --- | --- |
| Bazel | **7.7.0**, [`.bazelversion`](https://github.com/google-ai-edge/mediapipe/blob/50505c8312c7eacb1bd411cecdc4cc9fd08d53cb/.bazelversion) |
| Apple build rules | apple_support **2.6.1**, rules_apple **3.16.1**, rules_swift **2.3.0**, [MODULE.bazel](https://github.com/google-ai-edge/mediapipe/blob/50505c8312c7eacb1bd411cecdc4cc9fd08d53cb/MODULE.bazel) |
| Other toolchains | Python **3.11** module toolchain; remote JDK **21** in [`.bazelrc`](https://github.com/google-ai-edge/mediapipe/blob/50505c8312c7eacb1bd411cecdc4cc9fd08d53cb/.bazelrc) |
| iOS floor | **15.0**, [`MPP_TASK_MINIMUM_OS_VERSION`](https://github.com/google-ai-edge/mediapipe/blob/50505c8312c7eacb1bd411cecdc4cc9fd08d53cb/mediapipe/framework/tool/ios.bzl) |
| Native dependencies | LiteRT **2.3.0** source archive plus pinned TensorFlow and patches in [WORKSPACE](https://github.com/google-ai-edge/mediapipe/blob/50505c8312c7eacb1bd411cecdc4cc9fd08d53cb/WORKSPACE); preserve all resolved dependency hashes/licenses |
| OpenCV | `OPENCV=source` selects the [OpenCV 4.5.3 source rule](https://github.com/google-ai-edge/mediapipe/blob/50505c8312c7eacb1bd411cecdc4cc9fd08d53cb/third_party/opencv_ios_source.BUILD). Its M1 comment warns about CMake above 3.24.0; this is not evidence of compatibility with current Xcode. |

Select an existing Xcode with per-command `DEVELOPER_DIR`, record its complete version/build and SDK versions, and avoid changing global `xcode-select`. No exact Xcode release compatibility for this complete source build was established by this research. Start with dependency/toolchain analysis; stop on incompatibility and record the first failure before proposing a bounded patch. The older generic MediaPipe iOS example instructions are not a tested recipe for these Tasks targets.

Agree disk/cache/network and elapsed-time limits before execution: dependencies/toolchains can be large. Upstream defaults to **128 Bazel jobs**. Override that explicitly; `--jobs=2` does not cap OpenCV's nested build parallelism. Inspect/limit that sub-build separately. Keep caches task-owned, preserve effective rc files and resolved dependencies, and do not silently upgrade dependencies to get a build through.

For later provenance checking, these small upstream files were fetched as text and hashed at this checkpoint; tag and full-commit versions matched:

| File | SHA-256 |
| --- | --- |
| `.bazelversion` | `4eadffff0f101ee257a59e681df1ec9f163ead7c2f0d0865e2be54470c6f3c1b` |
| `MODULE.bazel` | `f503db12fada4d9001b2639ca70c7a9cfb5207542264c83131f5366ddac82d88` |
| `WORKSPACE` | `80f416c8c0bc08003dbd93a23168b3e7dd214c8508a73d929a33f79e9f2dd501` |
| `mediapipe/tasks/ios/BUILD` | `0dfd73f0f4777fbbddcabc58e0eeded700fa8e6ddc1ff3774d40220c25133b0d` |
| `mediapipe/tasks/ios/ios_build_rules.bzl` | `e1df9cbe53b27b3c778b847b39d04c63c6aa7bb384f33d1b91290dcae44e9c0b` |

## Source compilation route

The exact [public targets](https://github.com/google-ai-edge/mediapipe/blob/50505c8312c7eacb1bd411cecdc4cc9fd08d53cb/mediapipe/tasks/ios/BUILD) are:

- `//mediapipe/tasks/ios:MediaPipeTasksCommon_framework`
- `//mediapipe/tasks/ios:MediaPipeTaskGraphs_library`
- `//mediapipe/tasks/ios:MediaPipeTasksVision_framework`

Keep all three: Vision exposes headers, Common supplies implementations, and Graphs supplies calculator/graph registration. These targets include more than Pose Landmarker; this plan does not claim a pose-only dependency audit.

The following is a **prepared, unexecuted** command derived from the tagged [build helper](https://github.com/google-ai-edge/mediapipe/blob/50505c8312c7eacb1bd411cecdc4cc9fd08d53cb/mediapipe/tasks/ios/build_ios_framework.sh). Run only after the preflight above, from the verified source root, with `SDK_BAZEL` set to the selected Bazel 7.7.0 executable, `SDK_XCODE_DEVELOPER_DIR` set to the selected existing Xcode's Developer directory, and `SDK_BUILD_ROOT` set to an absolute task-owned cache/output directory:

```bash
: "${SDK_BUILD_ROOT:?Set an absolute task-owned cache/output directory}"
env DEVELOPER_DIR="$SDK_XCODE_DEVELOPER_DIR" "$SDK_BAZEL" \
  --output_user_root="$SDK_BUILD_ROOT/bazel" \
  --nosystem_rc --nohome_rc --noworkspace_rc --bazelrc="$PWD/.bazelrc" \
  build --repository_cache="$SDK_BUILD_ROOT/repository-cache" \
  --announce_rc --jobs=2 -c opt --config=ios_sim_device_fat \
  --apple_generate_dsym=false --define=OPENCV=source \
  --define=LITERT_LM_FST_CONSTRAINTS_DISABLED=1 \
  --define=DISABLE_HUGGINGFACE_TOKENIZER=1 \
  //mediapipe/tasks/ios:MediaPipeTasksCommon_framework \
  //mediapipe/tasks/ios:MediaPipeTaskGraphs_library \
  //mediapipe/tasks/ios:MediaPipeTasksVision_framework
```

Ensure the clean checkout contains no extra `.configure.bazelrc`/`.user.bazelrc`, which the upstream rc can import. Use `cquery` with identical configuration to enumerate outputs; inspect their ZIP contents and platform metadata rather than assuming a filename. The public macro defaults to arm64 device + arm64 simulator. An x86_64 simulator variant needs an explicit reviewed rule change and separate acceptance.

Do not run the helper blindly as the packaging solution: it still copies the Graphs target's output into files named `.a`, whereas that target now invokes an XCFramework rule. A source-level reading indicates that copy can mislabel a ZIP as an archive; execution must establish the actual output. Its query helper also invokes `bazel` from PATH independently of `BAZEL`.

## Make the result resource-capable

The tagged [MediaPipe macro](https://github.com/google-ai-edge/mediapipe/blob/50505c8312c7eacb1bd411cecdc4cc9fd08d53cb/mediapipe/tasks/ios/ios_build_rules.bzl#L133-L194) removes `bundle_format`, `bundle_id` and `infoplists`, then calls `apple_static_xcframework`. Thus the stock targets are not a completed manifest-carrying framework solution. Preserve that observation in the build receipt; do not advertise a vanilla build as closing issue 52.

Apple explicitly supports **manually creating static framework bundles around a static library** when the SDK is built outside Xcode. For each source-built component/platform, package the actual archive as `<Name>.framework/<Name>`, supply valid framework metadata, preserve public headers/module maps where applicable, and add the reviewed SDK `PrivacyInfo.xcprivacy` at that framework root. Verify arm64 device and simulator platform load commands; never combine their arm64 objects into one archive. [Apple manifest placement and manual static-library packaging](https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk).

Use Apple's `xcodebuild -create-xcframework -framework <device-framework> -framework <simulator-framework> -output <Name>.xcframework` route for each component. This is new local packaging work, not an upstream Google release. Preserve names/imports and required linkage; the official package explicitly retains graph registration with `-all_load`. Validate against duplicate definitions before changing linkage. [Apple XCFramework creation](https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle).

For integration, use Xcode's static-framework resource support and verify the Release app actually contains the framework resource bundles/manifests. Xcode 15+ can embed those resources while omitting the already-linked static binary. Merely adding a plist beside a bare `.a` is insufficient. [Apple static frameworks](https://developer.apple.com/documentation/xcode/creating-a-static-framework).

An alternative implementation is a reviewed local packaging rule using [`ios_static_framework` and its `resources` attribute](https://github.com/bazelbuild/rules_apple/blob/3.16.1/doc/rules-ios.md#ios_static_framework). Do not substitute `apple_xcframework` without checking linkage: it is a different product. Prefer one route, retain its patch, and test its final bundles.

## Declaration, signature and acceptance responsibilities

The SDK distribution maintainer must audit the exact retained dependency code and relevant runtime paths, then document each required-reason API's actual purpose against an approved reason. First-party UserDefaults/timer declarations do not describe SDK behavior. An empty manifest or guessed reason code is not a remedy. [Apple required-reason API responsibilities](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api).

The same maintainer needs evidence for SDK collection, tracking, domains and purpose declarations, including dependency behavior. Source availability and on-device inference do not establish “no collection.” Record the reviewer, scope and evidence used for each declaration; unresolved behavior remains a blocker to making that declaration. [Apple SDK data-use declarations](https://developer.apple.com/documentation/bundleresources/describing-data-use-in-privacy-manifests).

Sign a locally distributed XCFramework using the actual local publisher identity, record its certificate fingerprint/team and hashes, and explicitly review the trust change. Apple recognizes switching to a self-built/self-signed framework; that signature establishes this publisher, not Google provenance. Final app signing is separate. [Apple origin verification](https://developer.apple.com/documentation/xcode/verifying-the-origin-of-your-xcframeworks).

If seeking an upstream replacement instead, request the release source pin/build matrix, signed component XCFrameworks and complete SDK/dependency manifests with their declaration rationale. The [existing upstream API-declaration issue](https://github.com/google-ai-edge/mediapipe/issues/5351) concerns an older release; its discussion is not a 1.1.1 manifest or an approved declaration for this build.

Abseil and Protobuf are on Apple's list, including SDKs that repackage listed dependencies. Applicable binary signature and manifest obligations do not disappear because compilation occurred locally. [Apple SDK requirements](https://developer.apple.com/support/third-party-SDK-requirements/).

Preserve the [MediaPipe Apache 2.0 license](https://github.com/google-ai-edge/mediapipe/blob/50505c8312c7eacb1bd411cecdc4cc9fd08d53cb/LICENSE), required notices and modification notices; inventory transitive licenses separately. Do not label all dependencies Apache 2.0. Keep the independently pinned model and its existing attribution unchanged unless explicitly reviewed.

Before switching Spottr, require a receipt containing source/dependency hashes, toolchain versions, local patch, build logs, component/platform archive hashes, manifests and declaration rationale, publisher identity, and licenses. Accept the actual Release app with packaging checks, Xcode privacy report, existing blank/known-pose inference fixtures and graph-registration checks; then validate a newly exported archive with Apple. Keep SDK authorship/provenance acceptance, Apple processing and physical camera acceptance distinct. Until those gates pass, retain the present dependency and issue 52's unresolved status.

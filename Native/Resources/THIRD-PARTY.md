# MediaPipe

SDK: Google AI Edge MediaPipe 1.1.1, official arm64 iPhone and simulator binary distributions. The official release tag `v1.1.1` resolves to `50505c8312c7eacb1bd411cecdc4cc9fd08d53cb`; this identifies the release source tag, not independently verified source-to-binary build provenance for Google’s ZIPs. Apache 2.0 license is bundled as `MediaPipe-LICENSE.txt`.

The three XCFramework URLs and upstream SHA-256 hashes are pinned in `scripts/fetch-mediapipe.sh`. XCFrameworks are downloaded locally and excluded from git.

Pose Landmarker Lite, float16 version 1:
https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/1/pose_landmarker_lite.task

Model SHA-256: `59929e1d1ee95287735ddd833b19cf4ac46d29bc7afddbbf6753c459690d574a`.

Official task/model documentation: https://developers.google.com/edge/mediapipe/solutions/vision/pose_landmarker

Model card: https://storage.googleapis.com/mediapipe-assets/Model%20Card%20BlazePose%20GHUM%203D.pdf

Integration-test photograph (not displayed in the app): official MediaPipe test asset https://storage.googleapis.com/mediapipe-assets/pose.jpg . Blank video is a generated white 480×640, 10 fps test fixture.

Exercise and strength artwork: existing AI-generated Spottr artwork approved by Omar; prompts and provenance in `design/assets/PROMPTS.md`. Native PNG files are format conversions of those assets. App icons reuse the approved strength graphic on the required opaque background. No SVG artwork was authored.


# Presage SmartSpectra

Optional front-camera physiology adapter: [SmartSpectra Swift 3.4.0](https://github.com/Presage-Security/SmartSpectra-Swift/releases/tag/v3.4.0). The proprietary vendor binary is fetched by `scripts/fetch-presage.sh`; it is not committed. Archive SHA256: `eb99a609fc8069de020e0cf4328fb4a81a48b0aff7499348c6aa23e6fcb09947`. The outer XCFramework signature verifies as Presage Security Inc., team `54D6QF28QA`. Preserve its model/graph resources and vendor privacy manifest. The dynamic iPhone framework requires Embed & Sign; it is not linked into the Watch app. The application’s signing does not grant ownership of the vendor’s binary or its models.

An account key and explicit start/disclosure are required for a measurement. The SDK’s automatic Insights feature can transmit derived numeric readings to Presage and its LLM service; disabling diagnostic telemetry does not disable this feature. See [the integration and acceptance notes](../../docs/presage-integration.md). Binary compilation is separate from physiological/device validation and vendor data-use acceptance.

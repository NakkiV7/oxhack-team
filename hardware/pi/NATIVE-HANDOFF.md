# Native side-camera handoff

The native adapter is wired into the phone camera menu and existing pose pipeline; the physical Elgato USB disconnect remains unresolved. The adapter forwards JPEGs to phone-owned pose processing. It does not run inference on the Pi and does not start capture or make paid calls during initialization or pairing.

## Integration API

Present `SecondaryCameraSettingsView()` for explicit manual HTTPS address, SHA256 certificate fingerprint and masked token entry. All three values are saved together in one local Keychain record, accessible only while unlocked and excluded from synchronization. Saving validates all fields before replacing the record. Forget removes only Spottr's camera pairing. Stop/disconnect an old client before editing pairing; construct a new client after dismissal if the saved connection changed.

`try SecondaryCameraSettings.client()` constructs an idle `@MainActor @Observable SecondaryCameraClient`, or throws a sanitized configuration error when unpaired/unreadable. Tests may construct `SecondaryCameraClient(configuration:token:now:uptime:transport:)` with an injected transport and clocks.

- Explicitly `try await client.start()` after the user selects this camera and starts capture. It exposes `status`, `captureID`, `frame` and `errorMessage` for UI state. Constructor and settings never contact the Pi.
- Poll `try await client.fetchLatestFrame()` at the desired bounded rate, for example 10 fps. A new frame contains JPEG `data`, `metadata.frameID`, `metadata.capturedAt` and a conservative `metadata.validFor` receive budget. A duplicate returns `nil` and never extends freshness.
- Renew only while the user intends to capture: `try await client.renew()` before the server's 60-second lease expires, for example every 30 seconds. `start()` while streaming also renews the matching lease. Polling does not renew it.
- After asynchronous phone inference, require `client.isCurrent(theFrame)` before displaying or counting its result. This checks the active connection, latest identity and monotonic expiry. Reject images the native decoder/Vision cannot decode, and maintain the existing exercise-specific tracking validation.
- Use `await client.stop()` when capture finishes. Use `client.disconnect()` on pause, source replacement, view exit or application background: local frame/state clears immediately and a best-effort matching stop is sent. Cancel any caller-owned polling/renewal tasks too.

Any stale frame, invalid identity, non-success response, malformed image envelope or changed lease clears preview and marks the source unavailable. Expiry also clears without another HTTP response; late responses from a previous connection cannot revive it. A cancelled in-flight start closes a returned lease. If the start response is lost before the capture ID is known, server expiry remains the cleanup bound. Explicit restart is needed after failure.

## Phone inference worker

`SecondaryCameraVisionWorker` wraps that transport for the legacy validated camera journey. Construct it idle, set its MainActor callbacks, and explicitly call `start(client:generation:)`. It exposes `state`, `image` and `frame`. `onFrame(PoseFrame, UIImage, UUID)` delivers only a fresh result for the same active run; the store must additionally match its own session generation, active phase and chosen Pi source before using its existing pose/rep consumer. `onState(State, UUID)` reports starting/tracking/failure; failure must clear the store preview and pause counting. `stop()` clears worker preview and disconnects immediately.

Store/UI wiring should keep a separate `usingSecondaryCamera` selection flag while retaining `.camera` as the legacy session input source. The existing `.camera` VisionState preview branch chooses an AVCapture layer; guard that branch with `!usingSecondaryCamera` so Pi UIImage output is visible. Clear both store image and pose on source failure, pause, exit and background. Existing configured/manual journeys do not start this worker.

A minimal callback bridge calls the existing pose consumer only when `configured == nil`, `usingSecondaryCamera`, `generation == session.generation` and `session.phase == .active`. Worker validation precedes the callback, and the store performs those session checks synchronously on MainActor. Handle `.failed(message)` for the same selected session by clearing image/pose, displaying the sanitized message, and pausing. Stop both phone and Pi workers before changing source. Resume must explicitly start a new Pi worker run using the current session generation.

The default path loads a fresh existing `PoseDetector` on a dedicated serial queue before starting the camera. It uses the bundled lite MediaPipe model in video mode, including the existing single-person landmark/confidence mapping. JPEG decoding and inference run on that queue. Received monotonic time is the MediaPipe video timestamp. No detector rules or exercise geometry are duplicated.

The loop allows one JPEG request and one inference at a time, with a minimum 100 ms yield after each iteration. A separate task renews every 30 seconds. A 100 ms watchdog checks the current capture and the last published preview deadline even while inference is pending. Failure, source replacement or stop invalidates the run UUID; late inference cannot publish. Each inferred result rechecks `client.isCurrent(snapshot)` before callback delivery. Camera start after an established prior lease waits for its matching stop task to complete. A start whose response was lost still relies on the server lease expiry bound.

The default worker starts no paid calls. Only the explicit injected inference closure is replaced in lifecycle fixtures; production always uses the existing local detector. Six native worker tests pass on the existing iPhone simulator, covering actual bundled JPEG/model inference, backpressure, stop during inference, stale inference, decoder failure and renewal. The combined native run passed 15 client, six worker, three store lifecycle and one pairing UI tests. This verifies injected transport/inference behavior and one real bundled-image inference, not continuous physical camera tracking.

## Transport and boundaries

An ephemeral URLSession sends bearer credentials only in the Authorization header, refuses redirects, and uses the paired certificate DER SHA256 as a per-device trust anchor. Apple SecTrust still evaluates the configured hostname and certificate dates. There is no global certificate exception, system trust modification or query token. The private device certificate must include server-authentication usage and must be replaced/repaired when expired; the current seven-day certificate expiry is documented in the hardware evidence.

The server's capture timestamp is JPEG arrival on the Pi, not sensor exposure. Client freshness includes server monotonic age, full request duration and phone/Pi UTC age, then a local monotonic deadline. A phone/Pi clock disagreement of two seconds or more can reject capture; synchronize clocks normally rather than weakening freshness. The latest-frame API intentionally drops older intermediate frames.

Live credentials remain in ignored `.local/spottr-pi/pairing.json`; no live values are embedded in app code, tests or this handoff. Transfer pairing manually/private-device provisioning. The private certificate key remains on the Pi.

## Verification and remaining acceptance

Twenty-six offline Swift harness tests pass against exact sources, including client lifecycle/freshness/cancellation behaviors, pairing persistence, Apple SecTrust/redirect checks and pure configuration/frame validation. Cancellation-aware tests verify that a cancelled start still closes the returned matching lease before replacement capture begins. Pairing persistence failure tests use an injected secret store; physical iPhone Keychain/UI acceptance is separate. The SwiftUI form also passed the native simulator pairing flow; physical iPhone Keychain and local-network acceptance remain separate.

A separate bounded macOS URLSession check against the actual Pi accepted the current pinned certificate, received public health 200 and authenticated idle frame 503, and refused a deliberately wrong pin. It opened no camera and kept the token private. This confirms the transport on macOS, not iPhone local-network permissions or image ingestion. Twenty-three companion tests pass locally and on the Pi.

Remaining: native phone permission/pairing and preview acceptance, sustained USB continuity, camera orientation/exposure, side-view pose accuracy, and exercise counting accuracy. Configured manual/hold sessions keep their existing journey; extending validated camera tracking requires separate integration and acceptance.

Exact staged snapshot validation: 31 focused native/UI cases passed (65.1 seconds), all shared-core tests passed, and all 23 Python companion cases passed. One diagnostic came from the synchronous trust fixture running on the main actor; production trust runs on URLSession’s delegate queue. Result: `test_sim_2026-10-24T20-26-27-528Z_pid4129_e15b63e9.xcresult`.

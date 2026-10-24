# pushup-ios

iPhone display for the Push-up Coach. The Mac is the camera and runs pose detection; this app shows the result: rep count, posture advice, live video with the body-line drawing, elbow and body-line gauges, a rep history, an AI coach bubble with a Q&A page, and spoken counts.

Setup (Simulator or real iPhone, signing, troubleshooting): [../docs/TUTORIAL.md](../docs/TUTORIAL.md#2-iphone-display-optional).

Requires Xcode and iOS 17+. No third-party packages. Before running on a device, set your own Team and a unique Bundle Identifier in Signing and Capabilities (none is committed).

| File | Purpose |
|---|---|
| `MyApp.swift` | App entry |
| `ContentView.swift` | Dashboard, connection sheet, voice, Coach page (log, Q&A, references) |
| `PushupClient.swift` | SSE client over `NWConnection` (state, frames, coach), reconnect + watchdog, `ask()` |
| `HTTPPost.swift` | Minimal HTTP/1.0 POST over raw TCP (used for `/ask`) |
| `PoseView.swift` | Draws the camera frame and the body line/arm from normalized joints |
| `Models.swift` | `PushupState` (mirrors `publish()` in `../index.html`), coach and Q&A models |

Protocol and security notes: [../docs/ALGORITHM.md](../docs/ALGORITHM.md#7-streaming-to-the-iphone).

# Spottr

Native iPhone + Apple Watch training companion for OxHack 2026. Repository: [NakkiV7/oxhack-team](https://github.com/NakkiV7/oxhack-team).

The working baseline includes on-device MediaPipe push-up/squat tracking, camera and imported-video sessions, manual workout logging, timed holds, a 19-exercise library, local history, skill progression and deterministic session/week reports. Most exercises use manual logging or a timer; only push-ups and squats currently have camera tracking. Attribute points are game progress, not measured physiology. There is no sign-in or cloud sync requirement for the local demo.

Provider integrations and physical-device evidence have separate acceptance gates. A passing simulator test does not establish rep accuracy or real Watch sensor capture. See [roadmap and evidence gates](docs/ROADMAP.md) before describing a sponsor integration as connected.

## Start locally

Use a Mac with Xcode and installed iOS 26/watchOS 26 SDKs, Ruby with the `xcodeproj` gem, and the Xcode command-line tools selected. The Foundation-only package needs Swift 6. The optional gateway needs Node 22.9+ and npm; the prepared Pi companion checks use Python 3.10+. Bootstrap checks prerequisites and explains missing ones; it never installs packages, uses sudo, creates simulators or erases devices.

```bash
git clone https://github.com/NakkiV7/oxhack-team.git
cd oxhack-team
git switch -c feat/your-feature
./scripts/bootstrap.sh
cd server && npm ci && cd ..
./scripts/check.sh
open Spottr.xcodeproj
```

Bootstrap downloads only missing, pinned MediaPipe 1.1.1 XCFrameworks, verifies their archive hashes and regenerates the Xcode project. The model is already bundled. Dependency provenance is in [THIRD-PARTY.md](Native/Resources/THIRD-PARTY.md). The app needs no provider keys to use local training and reports.

In Xcode, select `Spottr` and an **existing** iPhone simulator. Use `xcrun simctl list devices available` to find your own device; for Watch work select an existing paired Watch and `SpottrWatch`. Reuse installed devices; do not automatically create or erase them. Physical phone/Watch builds need your own signing team and a matching phone/Watch bundle-ID pair. Coordinate generator changes before sharing signing edits.

The generated targets currently require iOS/watchOS 26; the standalone shared package supports older platforms. `./scripts/check.sh --static` checks shell/Ruby/JSON/JavaScript and Python syntax only. Normal `check.sh` additionally runs the offline Swift, gateway and Pi companion tests and requires installed gateway dependencies. Native XCTest/UI checks are manual in Xcode (`Product → Test`) against your selected existing simulator. No CI/CD is configured.

## Optional local gateway and keys

```bash
cp .env.example .env
# Edit .env privately, then:
cd server
npm ci
npm test
npm start
```

For hidden key entry, run `./scripts/local-config.py GEMINI_API_KEY` (Python 3). Running the helper without a key initializes an ignored `.env` and a random local gateway token. It prints no values; copy the gateway token privately from `.env` into Coach settings.

Use the variable descriptions in [.env.example](.env.example) and the [gateway setup](integrations/gateway/README.md). `.env` is ignored. Keep Gemini, database and other provider credentials on the server. The app receives only the gateway base URL and its separate gateway access token through local settings. Do not put provider keys in Swift, Xcode build settings, a committed plist, screenshots or PR text. Use a per-developer local token; a shared hackathon token is not production identity management.

The gateway defaults to `http://127.0.0.1:8787`; `GET /health` reports configuration without a provider call. Health readiness and a configured key do not prove a provider request succeeded. In **Coach → Coach settings** (sliders), enter the gateway URL and gateway access token, then save. The app stores the token in this-device Keychain. It accepts HTTPS and permits HTTP for localhost development; a physical phone needs a reachable HTTPS gateway. A remote deployment must provide its own authentication and transport hardening.

Use Send, Propose or Generate summary to explicitly share saved training, skill game points and recorded Watch summaries; raw sensor streams are not sent. Proposals start unselected: choose exercises, then **Approve & save selected exercises** to save a checklist. Each checklist item's Log action opens the manual logger; the camera foundation session remains a separate flow. Cancel/failure/invalid coaching preserves local reports and the current plan. See the gateway README for current routes and restrictions.

The local coaching policy evaluates form and pacing every second and at rep boundaries, using personal mean/sample SD from valid observed camera reps. It records actual rest between sets and emits expiring, prioritized text events for later voice playback. It makes no per-second provider call. See [coaching policy](docs/coaching-policy.md).

The [Pi camera companion](hardware/pi/README.md) is prepared for a later attached USB camera, with explicit authenticated capture and stale-frame/lease handling. It has not been deployed to the Pi or connected to iPhone inference.

## Pick up a feature

- [Team ownership and help wanted](docs/TEAM.md): claim a branch and file boundary before editing.
- [Contributing](CONTRIBUTING.md): small feature PRs, local checks, generated-project coordination and smoke tests.
- [Assigned GitHub issues](docs/ISSUES.md): current work, owners and suggested branches.
- [Roadmap](docs/ROADMAP.md): acceptance criteria and dependencies for each track.

Push-up CV belongs to [@azhar-rafiq](https://github.com/azhar-rafiq); squat CV to [@NakkiV7](https://github.com/NakkiV7); ElevenLabs voice and the landing page to [@MishaGitnik](https://github.com/MishaGitnik). [@omariosc](https://github.com/omariosc) owns the remaining tracks and integration. Both CV paths already have baselines: start with tests, calibration and observed errors.

## Source map

| Path | Purpose |
|---|---|
| `Native/iOS`, `Native/Watch` | SwiftUI app, camera/model pipeline, Watch companion and sensors |
| `Shared/Core` | Foundation-only session, exercise, progression, report and coach contracts |
| `Shared/Apple` | Apple companion transport |
| `Tests/Core`, `Tests/iOS`, `Tests/UI` | Offline behavior, native pipeline and UI checks |
| `server` | Optional local gateway; credentials stay here at runtime |
| `integrations` | Provider contracts, schemas, SQL preparation and integration setup |
| `scripts` | Pinned SDK fetch, Xcode generator and local checks |
| `design`, `research`, `docs` | Existing approved graphics, research and historical design notes |

Historical design documents describe intentions at their recorded date; source and the current evidence ledger take precedence for implementation status. Existing images are available for the demo; generation of additional images is paused.

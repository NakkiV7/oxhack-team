# Accounts, keys and local setup

## Local app first

A Mac with Xcode and the installed iOS/watchOS SDKs can build the phone and Watch targets. Follow the root README and `scripts/bootstrap.sh`; reuse existing simulators. Native camera preview needs a physical device or imported video. Simulator transport tests exercise message behavior, not physiological sensors.

Run `./scripts/local-config.py` to create ignored `.env` and a random gateway token. Set a secret privately with `./scripts/local-config.py VARIABLE_NAME`. Restart the gateway after changes. Each collaborator uses their own configuration. Never copy provider keys into the app bundle or repository.

## Optional services

| Service/account | Server configuration | Product role | Current acceptance |
|---|---|---|---|
| Google AI Studio / Gemini | `GEMINI_API_KEY`, `GEMINI_MODEL` | Chat, grounded workout/week explanations and catalogue proposals | Local live synthetic protocol checks passed; native connection and real-user entailment remain separate |
| Tiger Cloud | `TIGER_DATABASE_URL`, `SPOTTR_INSTALLATION_ID` | Explicit immutable workout sync and observed scalar time series | Adapter and migration exist; see current live ledger before assuming persistence works |
| ElevenLabs | `ELEVENLABS_API_KEY`; voice/model configuration in voice feature | Cached short cues, later streamed conversational output | Actual API secret pending; start with an available standard energetic voice. No synthesis has run |
| Vultr | `VULTR_API_KEY` for deployment tooling only | Host the small authenticated gateway | Deployment pending; do not put infrastructure credentials in runtime clients |
| Snowflake | Variables listed in `.env.example` for account, token type/token and optional warehouse/role | Fixed SQL API check, later batch feature evaluation | Offline adapter tests passed; live SQL/analytics pending |
| Presage | `PRESAGE_API_KEY` | Optional front-camera measurement distinct from Watch | Reserve limited credits for final bounded physical check |
| Delta + OpenRouter or available supported provider | Configure privately in Delta | Development/prompt evaluation threads | Installed; actual collaboration/evaluation evidence must be retained before claiming use |
| GitHub | Collaborator access and `gh auth login` if using CLI | Branches, PRs and issues | Repo: `NakkiV7/oxhack-team` |

The canonical names and comments are in [`.env.example`](../.env.example); do not invent alternate environment names. Empty configuration means unavailable, not a successful integration. The local gateway defaults to loopback. The physical phone requires a reachable HTTPS endpoint and its separate Spottr gateway token; localhost HTTP is for simulator development.

## Tiger acceptance

Use the provider's TLS connection string. Apply `npm run migrate` in `server` only to the intended Spottr database. Startup never migrates automatically. `npm run tiger:smoke -- --allow-live-synthetic` uses a reserved synthetic installation namespace and fixed year-2000 data, not the app user's workout namespace. It performs no cleanup or provider generation. Full certificate verification stays enabled; private/untrusted certificate failures must be resolved through supported trust configuration or a service with a trusted certificate.

## Camera companion

See [Pi instructions](../hardware/pi/README.md). Preserve existing LAVA/CI services and networking. Pair explicitly and authenticate camera control. Preview transport, phone inference and optional future Pi inference are distinct capabilities. Do not assume that a camera stream means pose inference ran on the Pi.

## Local identity and data

The current gateway is a single-owner installation-scoped prototype. A gateway token is not a personal account, and no cloud sign-in or cross-device account sync is claimed. Local profile/onboarding work and cloud identity work must remain clearly distinguished. Workout upload is explicit. Private camera recordings should not be added to public issues or test fixtures.

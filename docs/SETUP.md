# Accounts, keys and local setup

## Local app first

A Mac with Xcode and the installed iOS/watchOS SDKs can build the phone and Watch targets. Follow the root README and `scripts/bootstrap.sh`; reuse existing simulators. Native camera preview needs a physical device or imported video. Simulator transport tests exercise message behavior, not physiological sensors.

### Simulator signing and Keychain

For actual Coach connection or camera-pairing Keychain acceptance, build the simulator app with `CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-` and install that ad-hoc-signed build. Unsigned compilation or tests with `CODE_SIGNING_ALLOWED=NO` do not establish Keychain access. On 24 October 2026, Coach settings failed to save in the unsigned install, then saved successfully through the UI after the signed simulator build (MCP build log `21-20-32…8fa1267f`). No app, profile or Keychain-sharing change was needed. Simulator entitlement metadata can live in the executable's `__TEXT.__entitlements` section even when `codesign` prints no entitlements; verify runtime behavior before diagnosing a missing entitlement.

Run `./scripts/local-config.py` to create ignored `.env` and a random gateway token. Set a secret privately with `./scripts/local-config.py VARIABLE_NAME`. Restart the gateway after changes. Each collaborator uses their own configuration. Never copy provider keys into the app bundle or repository.

## Optional services

| Service/account | Configuration | Product role | Current acceptance |
|---|---|---|---|
| Google AI Studio / Gemini | Server `GEMINI_API_KEY`, `GEMINI_MODEL` | Chat, grounded workout/week explanations and catalogue proposals | Four native request types returned real responses with synthetic inputs, including approved-plan execution. Weekly planning passed offline, fixture UI and ARM64 image checks; [one bounded synthetic CLI request](evidence/weekly-gemini-compatibility-2026-10-25.md) returned real Gemini 200/schema-valid output. Live native weekly UI, physical HTTPS and real-user guidance review remain separate. |
| Tiger Cloud | Server `TIGER_DATABASE_URL`, `SPOTTR_INSTALLATION_ID` | Explicit immutable workout sync and observed scalar time series | Current endpoint verified, private-CA TLS blocked; no live persistence accepted |
| ElevenLabs | `ELEVENLABS_API_KEY`; future adapter voice/model settings | Optional remote spoken cues | Local Apple speech needs no key. ElevenLabs secret/synthesis and audible acceptance remain pending |
| Vultr | Signed-in Vultr account and scoped SSH administration; `VULTR_API_KEY` only if deliberately using API tooling | Host the small authenticated gateway | Existing account shows $5 credit; London demo form and approved hostname prepared. Spend/SSH confirmation and actual hosted TLS/authentication acceptance remain pending. No public VM yet |
| Snowflake | Server `SNOWFLAKE_ACCOUNT`, `SNOWFLAKE_TOKEN`, `SNOWFLAKE_TOKEN_TYPE`; live analytics also requires existing `SNOWFLAKE_WAREHOUSE`, `SNOWFLAKE_DATABASE`, `SNOWFLAKE_SCHEMA` | Fixed SQL API check and [pinned public forecast import/evaluation](snowflake-analytics.md); benchmark defaults to local dry-run, live requests require `--allow-live-public-data` | Offline adapter/analytics tests and artifact dry-run passed; no live SQL/import/warehouse execution accepted |
| Presage | Native SDK authentication choice pending; server key is only a placeholder | Optional front-camera measurement distinct from Watch | Proposal only; resolve SDK automatic derived-vitals LLM transmission and verify credits before one explicit bounded physical check |
| Delta + supported provider | Configure privately in the actual Delta app | Development/prompt evaluation threads | Official operator installation/legal completion and actual Delta judge run pending; the prepared packet and separate Codex calibration do not establish Delta use |
| GitHub | Collaborator access and `gh auth login` if using CLI | Branches, PRs and issues | Repo: `NakkiV7/oxhack-team` |

The live weekly check allowed one provider attempt, a 20-second timeout and 4,096 output tokens, with no retry; its loopback process was stopped afterward. Weekly requests retain the 64 KiB payload limit, 4,000-character messages and at most 20 history turns. A successful schema check is not evidence of appropriate personal exercise quantities. See [weekly contract and limits](weekly-planner.md).

The canonical names and comments are in [`.env.example`](../.env.example); do not invent alternate environment names. Empty configuration means unavailable, not a successful integration. The local gateway defaults to loopback on port 8787. The current gateway on Omar’s Mac uses 8788 to preserve another service on 8787. The physical phone requires a reachable HTTPS endpoint and its separate Spottr gateway token; localhost HTTP is for simulator development.

Google credits do not provide an HTTPS endpoint automatically. No active $300 credit was verified in the checked account; its visible projects have billing disabled. Current Gemini Developer API Welcome-credit restrictions and any separate Vertex migration are described in the [hosting checkpoint](vultr-deployment.md#25-october-account-and-domain-checkpoint).

For hosting, use the separate minimal templates under `deploy/` and [Vultr guide](vultr-deployment.md); do not copy every infrastructure/provider key into the runtime. For Presage, see the [SDK proposal](presage-integration.md) before choosing key-based internal testing versus OAuth/App Attest distribution. No SDK is currently installed by this setup.

## Tiger acceptance

Use the provider's TLS connection string. Apply `npm run migrate` in `server` only to the intended Spottr database. Startup never migrates automatically. `npm run tiger:smoke -- --allow-live-synthetic` uses a reserved synthetic installation namespace and fixed year-2000 data, not the app user's workout namespace. It performs no cleanup or provider generation. Full certificate verification stays enabled; private/untrusted certificate failures must be resolved through supported trust configuration or a service with a trusted certificate.

The current blocker is a verified private-CA chain, not a presumed stale hostname or an open-ended certificate wait. Follow [the recorded diagnosis](tiger-live-readiness.md) before retrying. Do not disable TLS validation.

## Camera companion

See [Pi instructions](../hardware/pi/README.md) and [physical evidence](../hardware/pi/EVIDENCE-2026-10-24.md). The companion is deployed and the native pairing/preview/inference client is merged. Preserve existing LAVA/CI services and networking. Pair explicitly using the private bearer credential and verified certificate pin; never copy pairing secrets into docs. The USB camera disconnect remains unresolved. Preview transport, phone inference and optional future Pi inference are distinct capabilities.

## Local identity and data

The current gateway is a single-owner installation-scoped prototype. A gateway token is not a personal account, and no cloud sign-in or cross-device account sync is claimed. Local profile/onboarding is implemented; goals and weekly target enter explicit Coach requests while the optional name stays local. Workout upload is explicit. Private camera recordings should not be added to public issues or test fixtures.

## Release status

The dated 25 October 01:32 UTC checkpoint records build **0.1 (4)** as valid, internally/externally available and beta-review approved. [Build 4 receipt](evidence/testflight-build-4-2026-10-25.md). Later source changes require a new reviewed archive/upload; physical installation remains separate. Follow [installation instructions](testflight.md), [release readiness](release-readiness.md) and [provisioning evidence](testflight-provisioning.md). Five actual-bundle packaging checks passed after the source metadata follow-up. Physical installs and the vendor SDK privacy/signature audit remain separate; do not commit a personal signing team or private signing assets.

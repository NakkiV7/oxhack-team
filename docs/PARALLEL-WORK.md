# Parallel demo work — 25 October 2026

Primary checkout: `/Users/scsoc/dev/AI PT`. Repository: `NakkiV7/oxhack-team`.
Use a separate managed worktree and feature branch from current `origin/main` before editing. Never switch, reset, stash or clean the primary checkout; it contains ongoing native integration. Read `/Users/scsoc/.claude/TDD.md` and applicable repository instructions. No CI/CD, committed secrets or invented provider/device results.

The primary chat owns native integration, project generation, signing, release, voice, Presage, front/side camera UI and optional body measurements. Existing subagents are implementing those slices. Do not duplicate them. The next TestFlight build is deliberately held until integration is ready.

Only the primary chat controls the shared iPhone/Watch simulators, native compiler queue and Safari service setup. Other chats can run isolated SwiftPM/server tests and build web assets. Prepare native tests and report exact selectors for coordinated execution. Reuse existing simulators; never create, erase or reset them.

## Separate chats

| Lane | Ownership | Completion evidence |
| --- | --- | --- |
| Watch data and reports | Watch recorder/transport contracts and sensor report components; coordinate any `TrainingStore.swift` or project edits with primary | Replay realistic Apple quantity/timestamp/unit payloads through transport, persistence and report projections. HR, active energy and wrist movement remain source-labelled; missing/stale/unsupported data stays unavailable. No running, zones or complications. |
| Tiger and Snowflake | `server/src/tiger*`, `server/src/snowflake*`, corresponding tests, SQL and provider-specific docs | Strict-TLS authenticated synthetic ingestion/replay/readback, useful rollups, and bounded Snowflake analytics. Preserve existing data and keep credentials private. Record exact external gates if account credentials are absent. |
| Onboarding crash diagnosis | Crash evidence, narrow regression/fix if reproduced; coordinate shared native files | Investigate the reported TestFlight 0.1 (5) crash using actual Apple reports and frozen source. No speculative fix or new TestFlight upload. |
| Landing publication | Existing `web/` landing sources (locate actual folder), landing docs and narrowly scoped static hosting/Caddy changes | Public professional landing page, correct TestFlight link and accurate capabilities. Preserve gateway authentication, allowlist, health and protected routes. No new paid resources. |
| Skill tree polish | Skill-tree view/components, existing progression tests and skill-specific docs | Professional connected grid and linear view, clear locked nodes, accessible unlock states and honest manual/camera provenance. Reuse raster icons; no generated SVGs or gamified medical claims. |

Open a small PR with behavior, actual validation and limitations; attach it using the app tool. Leave final integration/merging to the primary chat. Do not cherry-pick unrelated teammate work or bulk-merge `nakki-squat-model`. Its current changes require review; the native baseline already tracks push-ups and squats.

## Current evidence and useful private handoffs

- Current TestFlight remains **0.1 (5)**, frozen source `f3eae89ced8547e283bd93abe6c560c9e1ce8e2c`. Energy, keyboard and rewards source changes are later. Build 5's reported physical crash remains unresolved. Original and expanded optimized simulator onboarding checks pass; these do not establish a device fix.
- Crash handoff: ignored `.local/build5-onboarding-probe-20261025/diagnostic-report.md`; all 135 frozen Native/Shared files were hash-checked. ASC crash-feedback query at 06:23 UTC was empty. Xcode Organizer lacked a developer-account login. API helper `/tmp/spottr-asc.mjs` is private: never print its source, credentials, headers or signed URLs.
- Public gateway now exists at `https://spottr.omarchoudhry.co.uk`. One corrected synthetic hosted Gemini chat returned 200, matching generation and factual text, in 935 ms. An earlier checker used the wrong schema API and did not retain its provider result. No repeated paid tests are needed.
- Exact Vultr VM: `04331310-56ac-4b8d-b1ef-f17e946404fb`, label `spottr-demo-20261025`, London 1 GB, no backups. Existing funded balance only; $1 infrastructure ceiling. Target teardown **26 October 2026, 06:47 UTC**. Stopping does not end billing. Private receipt: `.local/vultr-deploy-20261025/`. Never print runtime env files.
- Tiger's original service still has an untrusted chain under Node's strict verification. Do not disable TLS verification or trust a socket-supplied CA. A second teammate service has independently verified public TLS but no local credentials: project `bhm5qdw7yb`, service `k1za89x0ef`, port 38300. Private portal guide: `.local/tiger-live-20261025/portal-next-steps.md`. Never try the original password against this other service.
- Snowflake account/warehouses were inspected, but SQL API token is absent. Existing offline analytics code is not live SQL evidence.
- New Pi LifeCam has passed Mac-to-Pi authenticated, pinned HTTPS frame retrieval and clean stop over IPv6. Existing LAVA service is preserved. Phone ingestion remains unverified. Pairing file is private: `.local/spottr-pi/lifecam-20261025/pairing.json`; never display its token/pin.
- Primary is integrating ElevenLabs calm/intense Goggins and Arnold choices, with local voice fallback. Working synthesis secret is still pending; do not fabricate it. Coach portraits are already imported. Presage SDK 3.4.0 was checksum/signature inspected; its automatic numeric-metric sharing requires explicit disclosure/consent. No Presage capture has run.

See [POST-HACKATHON.md](POST-HACKATHON.md) for deferred running, zones, Watch complications, full cloud accounts and Delta. The MVP keeps an optional local display name. Physical Watch checks and the user's 19 lesson recordings remain later human checks.

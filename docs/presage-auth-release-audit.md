# Presage authentication and release audit · 25 October 2026

Scope: authentication/account configuration only. The primary chat owns the evolving SDK adapter, camera, UI, project, signing and release. This audit did not start SmartSpectra, authenticate an SDK session, capture video, consume measurement credits, change an account, or run a native build.

## Verified local checkpoint

Read-only inspection of the primary checkout found SDK 3.4.0 integration sources and an app Embed Frameworks entry with `CodeSignOnCopy`. The native driver sets `enableTelemetry = false`, disables image output/logs, and requests pulse and breathing. These observations are source/configuration evidence; they do not prove runtime authentication or final archive packaging.

The primary `.env` has no configured `PRESAGE_API_KEY`. No `PresageService-Info.plist` or iOS host App Attest entitlement was found. The current driver requires a nonempty API key before constructing the SDK, so an OAuth-only release also needs an explicit authentication-mode change by the primary chat. A server environment variable cannot configure a native SDK by itself.

## Private internal demo

An existing account key can configure `SmartSpectraConfig.apiKey` for a deliberately authorized internal check. Retrieve only the existing key; do not rotate it. Store a recovered key in the ignored primary path `.local/presage-live-20261025/account.env`, mode `0600`, and hand off the filename only. Do not commit it or compile it into the public beta. The portal requires an activated account; existing sign-in does not establish remaining quota or successful SDK auth. [Provider API-key guide](https://github.com/Presage-Security/SmartSpectra/blob/v3.4.0/swift/docs/option-1-api-key.md).

Before the primary chat's single bounded physical check, verify account usage, explicit numeric-sharing consent, the stationary context and cancellation/deadline behavior. Record usage before/after and stop on auth/quota/network failure. No retries or purchases are implied. Remaining minutes and billing granularity are still unverified.

## OAuth distribution gate

Register the host bundle `com.omarchoudhry.spottr` with team `952HTWFJX7`; obtain the account-issued `PresageService-Info.plist` and include it in the iOS app target. Add App Attest and refresh provisioning through the primary chat. Check `DCAppAttestService.shared.isSupported` on a supported physical device; the simulator cannot attest.

The plist selector `IS_OAUTH_ENABLED` must be Boolean true (legacy integer 1 works); a string is invalid. OAuth also needs nonblank string `CLIENT_ID` and `SUB`; any `BUNDLE_ID` must match. Enabled OAuth overrides an API key. Invalid static configuration fails rather than falling back. Presage sandbox registration additionally accepts development attestations; production identities, including TestFlight, remain accepted. No registration, capability or provisioning changes occurred here. [Provider OAuth guide](https://github.com/Presage-Security/SmartSpectra/blob/v3.4.0/swift/docs/option-2-oauth.md).

Apple independently specifies that distributed apps use production App Attest, including TestFlight. An entitlement setting during development is not proof of distribution acceptance. [Apple App Attest preparation](https://developer.apple.com/documentation/devicecheck/preparing-to-use-the-app-attest-service).

## Privacy and final acceptance

Automatic Insights can send derived numeric series, a prompt and request/session metadata through Presage to an unnamed downstream LLM. The first stable pulse snapshot may occur within a 30-second check. Ignoring Insights or disabling diagnostic telemetry is not a verified opt-out. The Insights documentation excludes raw imagery for that feature; it does not establish every SDK data path or downstream retention. Preserve the SDK privacy manifests/assets and accurate disclosure; do not claim local-only processing. [Insights](https://github.com/Presage-Security/SmartSpectra/blob/v3.4.0/docs/llm-insights/index.md), [diagnostic telemetry](https://github.com/Presage-Security/SmartSpectra/blob/v3.4.0/docs/telemetry-and-privacy.md), [privacy policy](https://api.physiology.presagetech.com/privacypolicy).

Release remains gated on authentic account configuration; exact app registration/provisioning for OAuth; no permanent key in the distributable; final dynamic-framework signing/privacy/resource audit; explicit sharing opt-in; and the primary chat's permitted physical acceptance. Compilation and offline fixtures establish none of those live results. A valid physiological result is never guaranteed by a 30-second timer.

The documented account MCP offers read-only key, plan and app/config retrieval, separately from registration/deletion/rotation. It is not connected in this chat. Safari inspection remains serialized behind the other account lanes. [Provider account tooling](https://github.com/Presage-Security/SmartSpectra/blob/v3.4.0/docs/mcp-server.md).

# Spottr website and optional accounts

Live origin: https://spottr.omarchoudhry.co.uk

`landing/public` contains the marketing, support, privacy, terms and deletion pages. The public site has no application JavaScript; only `/account/` loads the bundled account client. Artwork and fonts are served locally. Exercise guides remain faceless stick figures.

The `spottr-site` Worker serves static assets and routes `/api/*` to D1. A website account is optional and separate from iPhone history, HealthKit, Apple purchases and TestFlight. There is no workout, video or health upload or online coach endpoint. No password, email-login or token-based AI service is used.

## Authentication

Registration verifies a resident passkey with user verification and the exact origin/RP ID, then confirms an Authenticator code before creating an account/session. Every new sign-in requires the passkey and a TOTP code. A single-use backup code can replace the TOTP factor; it cannot replace a lost passkey. Users should retain a synced passkey or a suitable passkey provider. No support bypass or email recovery exists.

Sessions last 12 hours. Enrollment, login and replacement challenges last five minutes and allow five second-factor attempts. TOTP steps cannot be replayed. Ten 80-bit backup codes are shown once, with only keyed hashes stored. Sensitive changes require a session with MFA within five minutes and a session-bound CSRF header. Authenticator replacement rotates recovery codes and revokes other sessions. Account deletion cascades public keys, encrypted seeds, sessions, linked challenges and code hashes. Export contains account metadata only.

Session and challenge cookies are Secure, HttpOnly, SameSite Strict and host-only. Raw tokens are not stored. AES-GCM encrypts the TOTP seed with account-bound additional data. D1 conditional batches protect against reused codes, stale sessions and concurrent rotations. Request bodies are limited to 32 KiB. POST attempts are limited to 60 per ten-minute keyed IP bucket. Hourly cleanup removes expired security records; validation rejects expiry before cleanup.

## Development and checks

Use Node 22+ and `npm ci` on the SSD. The local `node_modules` symlink points to the Extreme SSD development volume, which must be mounted. Do not commit dependencies or secrets.

```sh
npm test
npm run typecheck
npm run build
node --test ../landing/tests-public/*.test.mjs
```

Tests exercise actual SimpleWebAuthn signatures and Miniflare D1, including concurrent recovery and stale-session races. `scripts/live-smoke.ts --live` explicitly creates and deletes an ephemeral account at the production origin and writes a sanitized receipt. It never logs seeds, cookies, recovery codes or private keys. This software authenticator test does not prove Safari/Touch ID/passkey-manager acceptance. Run it only as a deliberate deployment check.

## Deployment

The existing Keychain-backed `codex-cloudflare personal` helper supplies Cloudflare authorization. `wrangler.jsonc` identifies only the Spottr Worker, D1 database, exact custom hostname and hourly cleanup trigger. It disables workers.dev, preview URLs and Worker request logs. No plan upgrade was purchased. Current CPU limits are compatible with Workers Free; account requests and this configuration's static requests still consume Worker quota. Check current provider allowances before increasing traffic.

```sh
codex-cloudflare personal ./node_modules/.bin/wrangler d1 migrations apply spottr-accounts --remote
codex-cloudflare personal ./node_modules/.bin/wrangler deploy
```

Worker secrets `AUTH_ENCRYPTION_KEY` and `AUTH_TOKEN_PEPPER` are distinct random 32-byte base64url values. Recovery copies are in macOS Keychain under `codex.spottr.accounts.auth_encryption_key` and `codex.spottr.accounts.auth_token_pepper`, account `spottr`. Never print their values, put them in CLI arguments, log them, or commit them. Do not replace them casually: changing the encryption key requires re-encrypting existing seeds; changing the pepper affects sessions, pending records and recovery-code verification. A controlled versioned migration is required.

Deployment receipts and the original DNS record are in ignored `.local/production-foundation/` and copied to the SSD release evidence directory. Host-specific response rule `spottr_hsts` preserves a one-year HSTS header despite the existing zone override. Existing unrelated rules remain unchanged. Re-deployment alone does not recreate this zone rule; preserve it. Rollback requires restoring the previous Worker version, or detaching only Spottr's custom domain and recreating the saved A record. Do not change zone-wide SSL/security settings or other applications' routes.

## Remaining release checks

- Test real passkeys and Authenticator QR setup in Safari on an iPhone, including cross-device/synced passkeys and recovery.
- Review privacy/controller contact, international-transfer arrangements and age/clinical scope against the actual public service before App Store launch. Published beta notices describe present functionality, not a compliance certification.
- Conduct independent security assessment and operational restore practice before holding valuable or sensitive account data. No such data should be added by merely extending this schema.
- Create/approve Apple products and the requested tester offer separately. Website accounts do not grant paid membership.

Primary references: [SimpleWebAuthn](https://simplewebauthn.dev/docs/packages/server), [D1 batches](https://developers.cloudflare.com/d1/worker-api/d1-database/), [Workers limits](https://developers.cloudflare.com/workers/platform/limits/), [custom domains](https://developers.cloudflare.com/workers/configuration/routing/custom-domains/), [HSTS](https://developers.cloudflare.com/ssl/edge-certificates/additional-options/http-strict-transport-security/).

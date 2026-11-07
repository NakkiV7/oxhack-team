# Spottr website, native accounts and optional statistics

Service origin: https://spottr.omarchoudhry.co.uk

The native-account, analytics and associated-domain changes in this source candidate require the activation and public readback receipts in `docs/service-activation.md`. Source tests alone do not establish that the deployed service includes these changes.

`landing/public` contains the marketing, support, privacy, terms and deletion pages. The public site has no application JavaScript; only `/account/` loads the bundled account client. Artwork and fonts are served locally. Exercise guides remain faceless stick figures.

The `spottr-site` Worker serves public assets, the same-account website and native MFA API, optional adult programme configuration sync and a separate unauthenticated coarse analytics endpoint. Native training requires account setup and verified Apple membership. Completed workout logs, video, raw Health and measurements are never analytics DTOs. No online AI service is part of the consumer workflow.

## Authentication and privacy

The exact native contract and operational requirements are in `docs/native-auth-contract.md`. Native identity bootstrap uses Apple or verified email, then UV passkey and TOTP. Persistent signed device sessions use 15-minute access and rotating 180-day refresh with durable single-flight retry. Existing website passkey/TOTP sessions and 12-hour cookies retain compatibility. Recovery is explicit and requires linked identity plus an unused backup. Local protected training storage remains separate.

Explicitly requested email ownership codes use AWS SES in London through the dedicated Spottr sender/configuration set. The signed request uses sender-only credentials and sends once under the existing 100/day, 3000/month and three-per-recipient/hour reservations, with a ten-second timeout and no redirect/retry/fallback. Provider acceptance is separate from inbox delivery; SES usage is not promised free. See the activation checklist for exact AWS_SES_* vars/secrets and the reviewed 7 November deployment/provider-path readback authorizing native activation. Actual inbox/native MFA and explicitly typed Apple private-relay email delivery remain separate acceptance steps.

Two independent adult consents default off. Analytics accepts strict coarse weekly snapshots with transient installation tags, bounded counters, request bytes and quotas. Each surfaced bucket requires ten distinct contributing installation tags. There is no public raw endpoint. See `docs/service-activation.md` for the source-reviewed activation checklist and exact retention/limits. No credential values belong in this repository.

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

The existing Keychain-backed `codex-cloudflare personal` helper supplies Cloudflare authorization. `wrangler.jsonc` identifies only the Spottr Worker, D1 database, exact custom hostname and hourly cleanup trigger. It disables workers.dev, preview URLs and Worker request logs. No plan upgrade was purchased. The configured 10 ms CPU limit targets Workers Free but real edge crypto/runtime acceptance remains to be measured; account requests and this configuration's static requests still consume Worker quota. Check current provider allowances before increasing traffic.

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

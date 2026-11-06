# Task 2 implementation report

Status: **DONE as a backend candidate for independent review**. No native integration, deployment, real mail, provider/key provisioning or physical acceptance is claimed.

Base: `3d2f73c802d16bb758f400a50d42792df7871adf`.
Implementation and exact contract commit: **`96630a6`** (`feat: add native MFA accounts and device-bound persistent sessions`). This report is committed separately.

## Delivered scope and exact API publication

`web/docs/native-auth-contract.md` is the binding Task 3 integration reference. It specifies every `/api/native/v1` route/request/response, allowed WebAuthn objects, complete MFA session response, device proof bytes/signature format, errors, ISO dates, five-minute partial-flow lifetime, five-attempt limits, 15-minute access and rolling 180-day refresh, exact 60-second idempotency policy, native/website identity linking, recovery, deletion, sanitized adult plan schemas, and operational/migration prerequisites.

Focused services:

- `native-auth.ts`: strict routing/body limits, real WebAuthn enrollment/assertion, TOTP/backup completion, atomic recovery, fresh native/website identity linking, native sign-out/revoke/delete.
- `identity.ts`: encrypted partial flows, one-time verified email ownership, real Apple RS256/JWKS verification, issuer/audience/subject/nonce/expiry checks, ES256 client-secret generation, authorization-code exchange and provider revocation. Apple email claims never merge accounts.
- `native-sessions.ts`: P-256 public-key validation, signed request authorization, one-time challenge/nonce consumption, access/refresh issuance, durable conditional rotation, bounded retries/reuse revocation, retention.
- `mail.ts`: ResendFree-only adapter, 100/day and 3,000/month hard atomic quotas plus three/recipient/hour, conservative failed-delivery accounting, generic fail-closed missing configuration, no Health/workout content, no debug OTP or paid overflow.
- `account-plans.ts`: account/profile-scoped, explicitly adult-consented, revision-checked saved preferences/programmes only; no raw ageContext, notes/rationale, history, effort, measurements or Health data.
- `0002_native_accounts.sql`: additive native devices, refresh history, proof challenges/nonces, encrypted partial flows, provider identities, quota reservations and cloud-plan slots. Existing users/passkeys/TOTP/backups/website sessions remain in original tables.

Shared changes are limited to exporting existing WebAuthn schemas, Apple-aware legacy deletion with injectable HTTP transport for tests, native route dispatch, and scheduled retention. Legacy registration/login/MFA routes and credentials retain their behavior. Original legacy tests run against both migrations.

Root's additional StoreKit attribution ruling is implemented: **`appAccountToken` explicitly equals authenticated `accountID`**, validated as UUID, in session issuance/current/refresh responses. Existing website user IDs originate from `crypto.randomUUID()`. No extra mapping database and no silently omitted token. Malformed imported non-UUID IDs fail closed. The field is attribution only, never entitlement/auth authority.

## Native adapter requirements

- Follow the exact contract; native/account-client tests are Task 3. Root confirmed there is no separate tracked existing account-client behavior suite in this checkout; do not claim one ran.
- Keep access/refresh credentials and P-256 private key in Keychain/Secure Enclave; separate account containers. Sign exact serialized body bytes, not a re-encoded object. Device ECDSA signatures are raw 64-byte `r || s`; WebAuthn signatures retain their own standard format.
- Serialize refresh per device. Persist old refresh token + request UUID before sending. Retry the same operation within 60 seconds with a fresh challenge/nonce/signature, and persist its returned successor before another rotation. A new request ID on a spent token, late reuse or reuse after the successor rotates revokes that device. Transient network/503 failures do not revoke healthy leases or erase local drafts/history.
- Apple/email are bootstrap/link proofs, never ordinary complete login. Ordinary new sessions require UV passkey plus TOTP or one unused backup substitute. Recovery requires an already-linked freshly verified identity plus an unused backup, then new UV passkey/new TOTP/new backup codes; atomic replacement occurs only on completion.
- Cloud DTO must be constructed separately from Core Codable. Guard known local adult age and explicit per-profile consent before any call; send only boolean eligibility/consent, never ageContext/age/DOB/guardian details. Use a dedicated UUID cloud slot per consenting adult local profile under its account. Never share slots across profiles or upload junior profiles.
- ISO8601 all network dates; explicit null for unknown startingPoint; omit rationale from plans and reconstruct a fixed local rationale. Revalidate restored programme execution through Core/current profile support and age policy. Core seconds-since-2001 Date encoding cannot cross this boundary.
- Fresh sensitive changes use a newly completed full MFA session (five minutes). Refresh does not reset MFA freshness. Identity linking may also use the same fresh legacy website cookie plus Origin/CSRF; native cookies alone grant no session authority.

## Test-first evidence

All logs, temporary runtime files and generated client bundle are in:

`/Volumes/Spottr Development/Audio/Holistic-Training-20261106/task2/`

Tests use independent fake secrets and actual WebCrypto/WebAuthn signatures. HTTP delivery/provider calls are fake injected transports; cryptographic verification is not stubbed. Behavioral database tests use real Miniflare D1. A narrow DB wrapper is used only to inject a revocation race/transient failure while all persisted operations still run against D1.

Red/green progression:

| Behavior | Red evidence | Green evidence |
| --- | --- | --- |
| Native rotating sessions/restart retry | `red-sessions.log`: missing native handler | `green-sessions.log` |
| Verified email → real UV passkey → TOTP enrollment | `red-enroll.log`: absent route 404 | `green-enroll.log` |
| Ordinary complete MFA/one-time backup | `red-login.log`: absent login contract | `green-login.log` |
| Atomic explicit recovery | `red-recovery.log`: absent recovery route | `green-recovery.log` |
| Real Apple signatures/nonce/audience/expiry/exchange | `red-apple.log`: absent provider route | `green-apple.log`; later ES256 client-secret, bad-signature and exchanged-subject checks in `green-device-key-apple.log` |
| Concurrent refresh, fresh revoke/delete, input/rate boundaries | `red-session-security.log` | `green-session-security-2.log`; initial green exposed D1 cascade change-count handling, corrected by DELETE RETURNING |
| Strict consented profile plans/revisions | `red-plans.log` | `green-plans.log` |
| Saved programme ISO DTO | `red-programmes.log` | `green-programmes.log` |
| Fresh verified identity linking/conflicts | `red-link.log` | `green-link.log` |
| Revocation race during refresh | `red-refresh-race.log`: retry loop became 503 | `green-refresh-race.log`: bounded 401, no credential destruction |
| Transient D1 proof-consumption outage | `red-transient.log`: incorrectly returned 401 | `green-legacy-transient.log`: 503 and healthy lease remains usable |
| Apple-aware legacy deletion | `red-legacy-revoke.log`: deletion incorrectly succeeded without revocation | `green-legacy-transient.log` |
| Expired/associated partial-state retention | `red-retention.log` | `green-retention.log` |
| Reject invalid P-256 curve points before account commit | `red-device-key.log`: invalid key incorrectly accepted | `green-device-key-apple.log` |
| Exactly one supplied MFA factor field | `red-exclusive-factor.log`: empty code plus valid backup incorrectly accepted | `full-web-final.log` |

Additional actual behavioral security coverage: `security-behaviour.log` and `concurrency-review.log` cover WebAuthn UV/origin/RP/challenge/signature failures, signed method/path/body/token/challenge/nonce/time binding and replay, duplicate nonce under fresh signature, one-winner backup completion, transaction-injected recovery failure preserving originals, expired enrollment, abandoned recovery, competing recovery completions, and stale/concurrent cloud-plan writes.

`mail-routing.log` covers generic enumeration-resistant start responses, bounded codes, no OTP leakage, failed/missing provider configuration, no Health content, daily/monthly quota concurrency, no overflow, and actual Worker route dispatch.

An initial test command was run from the repository root and could not resolve `tsx`; it was corrected to `web/` before the missing-module red was recorded. No passing claim relies on that command. The final migration test initially exposed implicit-any annotations from Miniflare's test API; explicit result types fixed typecheck without changing runtime behavior or loosening strict settings.

## Final checks and exact commands

The production/test implementation before the additional migration preservation test passed the full web suite:

```sh
cd '/Users/scsoc/dev/AI PT/web'
TMPDIR='/Volumes/Spottr Development/Audio/Holistic-Training-20261106/task2/tmp' \
  node --import tsx --test --test-concurrency=2 test/*.test.ts
```

- `full-web-final.log`: **49 tests passed, 0 failed**, 18.696 seconds. Includes every pre-existing web auth/crypto/site test and the native security tests at that point.
- `migration-preservation.log`: **1 additional test passed**, 0.949 seconds, applying 0002 over populated legacy users/credentials/TOTP/backups/sessions/pending records and comparing original rows byte-for-byte. Command: same Node invocation with `test/native-migration.test.ts`. This test was added after the 49-test full run; do not describe it as one 50-test full run.
- `typecheck-final.log`: `npm run typecheck` passed after adding the migration test. Strict/noUnused/noUnchecked settings unchanged; no new packages, any casts, suppression flags or dependency changes.
- `account-client-build.log`: existing client bundle succeeded in 122 ms, **482.0 kB**, written only to SSD:

```sh
node_modules/.bin/esbuild client/account.ts --bundle --format=esm --target=safari17 --minify \
  --outfile='/Volumes/Spottr Development/Audio/Holistic-Training-20261106/task2/account.js'
```

- `public-site.log`: **14 existing public-site tests passed**, 0.106 seconds:

```sh
cd '/Users/scsoc/dev/AI PT'
node --test --test-concurrency=2 landing/tests-public/*.test.mjs
```

- `git diff --check` and `git diff --cached --check`: clean before implementation commit.
- No overlapping suites, Chrome, simulator, native build or expensive validation campaign. Tests bounded to two files concurrently.
- Existing `web/node_modules` SSD symlink preserved. Scratch approximately 1 MiB before generated bundle; SSD remained **54 GiB available**. No cleanup/resizing/storage migration.
- Protected build 17, Vendor, release evidence, `.playwright-mcp/` and `prototype/images/` untouched. The pre-existing untracked `.playwright-mcp/` and `prototype/images/` remain untouched; the root agent's concurrent age-order spec edit is also preserved unstaged.

## Self-review, migration/recovery safety and limitations

Self-review found and test-fixed cascade change-count assumptions, refresh revocation-race recursion, incorrect transient-error classification, invalid device-key acceptance and an exact-factor-field contract edge case. D1 batches do not roll back a zero-row write automatically: subsequent mutations use the successful operation's random marker, and real rollback testing confirms no partial credential replacement. Refresh races converge on one durable response for the same request; real signed reuse revokes only that device. Replay/ineligible provider failures never mint trusted sessions.

Schema is additive and original records remain unchanged by migration. Deployment must back up/export D1 first, apply 0002 before new Worker code, and review rollback. Do not drop provider/refresh records, resurrect revoked auth versions/credentials, or roll legacy deletion back to code that ignores linked Apple grants. After native activity, disabling new routes while retaining revocation-aware legacy deletion is safer than silently reverting auth semantics. Full details and exact provider secret names are in the published contract.

Provider settings remain owner-controlled and unprovisioned/unverified for this candidate. Missing Resend or Apple configuration fails closed. No real Apple grant, mail delivery, DNS, AASA, Worker/D1 deployment, keychain secret change, paid service or capability write occurred. Production Apple audience/key association, associated-domain passkeys, free Worker 10 ms CPU budget/runtime behavior, delivery/quota configuration, and physical-device acceptance still need their separate checks. The existing public notices and native account UI are not rewritten by this backend task; updated notices and native integration must precede activation.

The eligibility boolean is a client declaration, not legal age verification; Task 3 must enforce known adult age and consent in the local adapter. Cross-account and profile scoping is enforced server-side, but the server deliberately never receives raw age to identify a junior profile. Cloud plans are configurations, not uploaded completed activity or medical guidance. Local execution must still validate catalogue unit/support/age suitability.

Handler re-creation is tested against durable D1 state; this is Worker-isolate restart behavior, not a claim that a production regional outage or real device/network restore was exercised. A completed initial enrollment response can be lost; the new user can still perform normal full MFA with their saved passkey/Authenticator. Refresh response loss has the explicitly tested bounded idempotent contract. No indefinite replay acceptance or support bypass was introduced.

Independent fresh task/security-aware review remains required before Task 3 integration. This report does not mark that review, deployment or live readiness complete.

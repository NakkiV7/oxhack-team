# Native account API v1

Candidate implementation; not deployed. Apply reviewed additive migration `0002_native_accounts.sql` after `0001_accounts.sql` before serving this code. Existing website accounts, credentials, sessions, encryption key and pepper remain authoritative. No separate native user database. The native handler never trusts a request-supplied account ID.

## Transport, errors and dates

All routes below are **POST**, prefixed by `/api/native/v1`, with `Content-Type: application/json`; bodies are UTF-8, at most **32,768 bytes**, and reject unknown fields recursively. No URL query parameters. Native requests need no browser `Origin`; when supplied it must equal configured `ORIGIN`. Cross-site browser requests are rejected. Cookie-authorized website linking requires exact Origin and CSRF. Responses are JSON with `Cache-Control: no-store`. Do not log request bodies, credentials, proof headers or response tokens. Worker observability remains disabled.

All application network timestamps are UTC ISO 8601 strings, e.g. `2026-11-06T14:00:00.000Z`. ISO strings without fractional seconds are also accepted. JWT `iat`/`exp` are standard NumericDate protocol fields, never Core `Date` serialization. `localDate` is a Gregorian `YYYY-MM-DD` calendar label, not a timestamp.

Errors contain exactly `{ "error": "<code>" }`:

| HTTP | Code | Client action |
| --- | --- | --- |
| 400 | `invalid_request` | Correct payload/schema; no state reset. |
| 401 | `verification_failed` | The presented proof cannot authorize this action. For a partial flow, restart or retry within its remaining attempts. For a protected request, reauthenticate if the saved credential is no longer valid. Never delete local history/profile/Watch queues. |
| 403 | `origin_rejected` | Configuration/origin mismatch. |
| 404 | `not_found` | Unknown route or missing account/profile plan. |
| 409 | `revision_conflict` | Read the current plan and resolve explicitly; do not overwrite blindly. |
| 413 | `body_too_large` | Bound payload locally. |
| 415 | `json_required` | Correct content type. |
| 429 | `rate_limited` | Wait for the next ten-minute window. |
| 503 | `temporarily_unavailable` | Retry later; preserve credentials and drafts. Provider/configuration/delivery/storage failure is not sign-out. |

Limit: 60 native requests per trusted Cloudflare connecting IP per ten-minute UTC bucket (includes challenge requests). Email adds three sends per normalized recipient per rolling hour, at most 100 reservations per UTC day and 3,000 per UTC month. Delivery failures conservatively consume quota. No overflow provider, paid fallback, automatic paid upgrade, email debug endpoint or production cryptography bypass exists.

Opaque tokens, challenges and nonces are 32 random bytes encoded base64url without padding (43 characters). Partial flow tokens expire **five minutes from initial issuance**, never extended by later stages. A stage permits five verification attempts; success is a conditional one-time transition. Partial flow tokens never authorize account/session/plan access. Keep them in transient memory, not persisted as a trusted account.

## Session and device proof

A successful `/enroll/complete`, `/mfa/complete` or `/session/refresh` returns:

```json
{
  "authenticated": true,
  "accountID": "c740c656-8f6e-44e8-8518-c9a2c6d32628",
  "appAccountToken": "c740c656-8f6e-44e8-8518-c9a2c6d32628",
  "deviceID": "d8fecf20-ee2f-4cb7-bf42-8063f20471df",
  "accessToken": "<opaque token>",
  "refreshToken": "<opaque token>",
  "accessExpiresAt": "2026-11-06T14:15:00.000Z",
  "refreshExpiresAt": "2027-05-05T14:00:00.000Z"
}
```

`accountID` is server-derived. All existing website producers use `crypto.randomUUID()` for user IDs. `appAccountToken` explicitly equals that stable UUID across website/native login, devices, refresh and recovery; native session issuance fails closed for a malformed imported non-UUID ID. Swift parses this trusted field using `UUID(uuidString:)` and passes it to StoreKit purchase attribution. It is pseudonymous attribution, never an entitlement, auth token or authority to access an account. No extra mapping table or silently omitted attribution.

`deviceKey` at final MFA completion is exactly a public P-256 JWK:

```json
{"kty":"EC","crv":"P-256","x":"<32-byte base64url>","y":"<32-byte base64url>"}
```

The client retains the private key in Keychain/Secure Enclave, and access/refresh credentials in Keychain. Never send `d`, use UserDefaults for tokens, or share a device key across account containers. Fresh complete MFA creates a new `deviceID`. Access lasts 15 minutes; refresh lasts 180 days and renews for 180 days on successful use. Rotation does **not** refresh the original MFA freshness timestamp. Linking, non-sign-out revocation and deletion require MFA within five minutes. Reauthenticate with passkey plus TOTP/backup to obtain a new fresh device session for sensitive changes.

Before each protected request, call `/session/challenge` with `{ "token": "<access or refresh token>" }`. Response: `{ "challenge": "<opaque>", "expiresAt": "<ISO8601>" }`, valid for 60 seconds. It is bound to that exact token and device. An unexpired spent refresh token can receive a challenge solely to resolve bounded retries/detect signed reuse.

Protected request headers:

- `Authorization: Bearer <token>` (access except on refresh).
- `X-Spottr-Proof`: JSON object `{ "challenge": "...", "nonce": "<fresh 32 random bytes base64url>", "issuedAt": "<ISO8601>", "signature": "<64-byte base64url>" }`.

Sign UTF-8 bytes of the following newline-joined fields, **without a trailing newline**:

```text
spottr-native-v1
POST
/api/native/v1/<exact-route>
<base64url SHA-256 of exact UTF-8 request body bytes>
<base64url SHA-256 of raw bearer token UTF-8 bytes>
<challenge>
<nonce>
<issuedAt exactly as in proof>
```

Signature: standard ECDSA P-256/SHA-256, IEEE P1363 raw 64 bytes (`r || s`), not DER. CryptoKit `P256.Signing` uses `signature.rawRepresentation`; when using Security/Secure Enclave DER signatures, convert the ASN.1 integers to fixed-width 32-byte coordinates before base64url encoding. WebAuthn assertion signatures remain the standard WebAuthn format and must not use this conversion.

Serialize the body **once** and sign those exact bytes. Do not regenerate JSON, reorder keys or change whitespace after signing. The server accepts `issuedAt` within ±60 seconds, consumes the challenge once, and prevents nonce reuse per device. For every retry request, obtain a **new challenge, nonce and signature**.

### Refresh idempotency

`/session/refresh`: `{ "requestID": "<UUID>" }`, signed with the refresh token. Store this request ID durably with the old refresh token before sending. Serialize refreshes per device. One transaction records the old token hash, request-ID hash and encrypted response, then rotates both tokens. Same old token + same request ID + correct device signature returns the **identical encrypted-record response for 60 seconds**, only while its successor is still current. A handler/process restart does not affect this policy. Concurrent identical requests converge on one result.

A different request ID, retry after the 60-second window, or an old predecessor after another rotation is signed reuse: revoke that device and return 401. Other devices and account factors remain intact. Clients must persist the response before starting another rotation. After an ambiguous response, retry that same operation promptly; do not invent another request ID. Once the bounded window is missed, complete MFA again. Invalid signatures cannot revoke another device. Persistent transport/503 failures do not revoke healthy credentials. Spent-token tombstones last to the old lease expiry; encrypted retry responses are never sent without the matching device proof.

### Protected session operations

| Route | Body | Response |
| --- | --- | --- |
| `/session/current` | `{}` | `authenticated`, `accountID`, `appAccountToken`, `deviceID`, `accessExpiresAt`, `refreshExpiresAt`; no new tokens. |
| `/session/sign-out` | `{}` | `{ "signedOut": true }`; revoke this device only, no fresh-MFA requirement. |
| `/session/revoke` | `{ "deviceID": "<UUID>" }` | `{ "signedOut": true }`; target must belong to the authenticated account; fresh MFA required. |
| `/account/delete` | `{ "confirm": "DELETE" }` | `{ "deleted": true, "phoneHistoryUnchanged": true }`; fresh MFA required. Revoke linked Apple grants before conditional account deletion. Provider failure returns 503 and retains account data for retry. |

Deletion cascades credentials, backups, website sessions, native devices/challenges/nonces/refresh history, linked identities, associated partial flows and cloud plans. Anonymous unverified challenges expire within five minutes. Conservative hashed mail quota reservations expire after 38 days and have no account/profile foreign key. Local phone/Watch data is not remotely removed.

## Email/Apple bootstrap and explicit linking

These endpoints only establish a **partial verified identity**, not a signed-in account. Purposes are exactly `enroll`, `recover`, or `link`. Email/Apple account existence is not revealed by the start endpoint. A verified owner may subsequently learn that enrollment/recovery cannot proceed. Apple email claims are never used to merge accounts or infer email ownership.

| Route | Exact request | Response |
| --- | --- | --- |
| `/identity/email/start` | `{ "email": "person@example.com", "purpose": "enroll" }` | `{ "flowToken": "...", "expiresAt": "<ISO8601>", "accepted": true }`; code delivered only through the configured mail adapter. |
| `/identity/email/verify` | `{ "flowToken": "...", "code": "123456" }` | `{ "flowToken": "...", "verified": true }`. |
| `/identity/apple/start` | `{ "purpose": "enroll" }` | `{ "flowToken": "...", "expiresAt": "<ISO8601>", "nonce": "..." }`. |
| `/identity/apple/verify` | `{ "flowToken": "...", "identityToken": "<Apple JWT>", "authorizationCode": "<Apple code>" }` | `{ "flowToken": "...", "verified": true }`. |
| `/identity/link/complete` | `{ "flowToken": "..." }` | `{ "linked": true }`; requires the same fresh authenticated session that started the link. |

Email is length-bounded and lowercased; a typed string or legacy username is never proof of ownership. Codes are hashed and bound to a random challenge. Pending recipient/code state is encrypted. Completed email subjects are keyed hashes, not raw addresses.

For Apple, assign the exact returned `nonce` to `ASAuthorizationAppleIDRequest.nonce` (do not independently hash/change it). Send Apple's actual identity token and authorization code. The server checks RS256 against Apple's HTTPS JWKS, exact issuer `https://appleid.apple.com`, configured client audience, subject, exact nonce, expiry, issued-at skew and maximum one-hour token lifetime. It consumes the challenge before exchanging the code; the exchange's signed token must have the same subject/nonce. Retry a failed exchange with a new Apple flow. Client-secret generation uses ES256 with the correctly configured **Sign in with Apple key**, never an App Store Connect API key. The provider refresh grant is encrypted for later revocation.

For purpose `link`, sign the start and complete requests using the same fresh native access session. Alternatively, an existing authenticated website can call these routes with its existing `__Host-spottr_session` cookie, exact Origin, and `X-Spottr-CSRF`, after fresh passkey/TOTP/backup authentication. Verification between start and complete uses the partial flow token. Complete rechecks session validity, freshness, auth version and identity uniqueness in the transaction. Existing links to another account fail; email matching never redirects the link to another user.

## Passkey enrollment and ordinary MFA login

Registration and assertion objects are standard SimpleWebAuthn `RegistrationResponseJSON` / `AuthenticationResponseJSON`. All normal fields are allowed as typed below; unknown fields fail. Native AuthenticationServices adapters must encode binary data base64url without padding and include the actual UTF-8 server user handle.

Registration credential: `id`, `rawId`, `type:"public-key"`, `clientExtensionResults:{}` (or `credProps:{rk:boolean}`), optional `authenticatorAttachment:"platform"|"cross-platform"`, and `response:{clientDataJSON,attestationObject,transports?}`. Transports: usb/nfc/ble/internal/hybrid/smart-card/cable. Assertion credential: same outer required identifiers/type, `clientExtensionResults:{}` (or `appid:boolean`), optional authenticatorAttachment, and `response:{clientDataJSON,authenticatorData,signature,userHandle}`. The parser permits absent userHandle for structural compatibility, but native authentication rejects it: provide the actual enrollment user ID bytes base64url. UV is required for registration and authentication. RP ID is configured `ORIGIN`'s hostname; expected WebAuthn origin is the exact configured HTTPS origin.

| Route | Request | Response |
| --- | --- | --- |
| `/passkey/enroll/options` | `{ "flowToken": "<verified enroll identity>" }` | `{ "flowToken": "...", "options": <PublicKeyCredentialCreationOptionsJSON> }`. |
| `/passkey/enroll/verify` | `{ "flowToken": "...", "credential": <registration> }` | `{ "flowToken": "...", "secret": "<base32 TOTP seed>", "uri": "otpauth://..." }`. Only a temporary setup seed; still no account session. |
| `/enroll/complete` | `{ "flowToken": "...", "code": "<TOTP>", "deviceKey": <public JWK> }` | Session response plus `backupCodes:[10 strings]`. Atomic new account creation or recovery replacement. |
| `/passkey/login/options` | `{}` | `{ "flowToken": "...", "expiresAt": "<ISO8601>", "options": <PublicKeyCredentialRequestOptionsJSON> }`; discoverable credentials, no username/email lookup. |
| `/passkey/login/verify` | `{ "flowToken": "...", "credential": <assertion> }` | `{ "flowToken": "...", "needsSecondFactor": true }`. |
| `/mfa/complete` | `{ "flowToken": "...", "code": "<TOTP>", "deviceKey": <public JWK> }` **or** `{ "flowToken": "...", "backupCode": "...", "deviceKey": <public JWK> }` | Session response plus `usedBackupCode:boolean`. Exactly one factor field. |

TOTP uses existing 30-second SHA-1 six-digit codes with ±1 step acceptance and account-wide monotonically spent steps. Backup codes are single-use and hashed with account context. Ordinary login always needs a UV passkey, followed by TOTP **or** backup; Apple/email proof and backup alone never create an ordinary session. Preserve/display new backup codes only from a successful final response. Never log/copy seed/codes into analytics. New credentials may be saved to the platform before server completion; expired/abandoned server enrollment creates no account.

AASA must separately be deployed with `webcredentials` entry `952HTWFJX7.com.omarchoudhry.spottr`, and native associated domains must match the configured RP. Task 2 does not deploy AASA or change native entitlements.

## Recovery

1. Start/verify email or Apple with `purpose:"recover"`. It must already be linked to the target account.
2. `/recovery/options` with `{ "flowToken": "...", "backupCode": "<unused backup>" }`. Response is `{flowToken,options}` for a **new** UV passkey. The backup is checked but not spent yet.
3. `/passkey/enroll/verify`, then `/enroll/complete`, with a new passkey, newly provided Authenticator seed and valid new TOTP.
4. The final conditional D1 transaction rechecks the linked account auth version and unused backup, then replaces all passkeys/TOTP/backups, increments auth version, revokes all website/native sessions and issues the new MFA-complete device session. New backup codes are returned once.

Until step 4 succeeds, existing credentials, sessions and backup codes remain valid. Competing recovery/login code consumption makes the losing transaction fail with no partial replacement. Provider proof, backup code or email string alone cannot recover an account. No support/admin bypass. If all linked identities and backups are lost, create a separate new account; that grants no access to the old account's data. Purchase restoration is a separate verified StoreKit flow.

## Adult cloud programme DTOs

Only saved future programme/preferences are synced. No workouts/history, effort, completion records, measurements/BMI, Health, camera/audio, age/DOB, guardian/child details or arbitrary metadata. Raw Core `ProgrammePreferences` and `CoachSavedPlan` must **not** be directly encoded for upload.

Every read/write includes explicit `{adultEligible:true,cloudPlanSync:true}`. The native adapter must check that the currently selected **local** profile has known age ≥18 and that this profile's explicit cloud-plan consent is on. Unknown and junior profiles never call these endpoints. The boolean is an eligibility/consent declaration, **not server-verified legal age**. Do not send `ageContext`, age years or a guardian identifier. Consent must not be inferred from mandatory account setup.

`profileSlot` is a dedicated random UUID for one consenting local adult training profile, stored under its authenticated account container. Never use an account ID, shared default slot, child profile ID, display name or user-entered text. Reuse only for that same adult profile across devices after an explicit restore/link choice. A programme ID is unique only within `(accountID, profileSlot)`; it is not an authorization key.

`preferences` has exactly:

```json
{
  "goals": ["balance", "weightManagement"],
  "weekdays": [1, 3, 5],
  "minutesPerSession": 20,
  "preferredLocalHour": 18,
  "availableSupport": ["Wall", "Stable chair"],
  "allowsFloorWork": false,
  "excludedExerciseIDs": ["wallSit"],
  "startingPoint": "somePractice"
}
```

- Unique nonempty goals from strength/stamina/mobility/balance/weightManagement.
- Unique nonempty ISO weekdays Monday=1 through Sunday=7.
- Minutes exactly 10/20/30/45; local hour 0–23.
- Unique support choices: Wall, Stable chair, Stable sofa or counter, Stable support.
- Unique excluded exercise IDs from the existing 53-entry catalogue (`exerciseIDSchema` in `account-plans.ts`).
- Starting point startingOut/somePractice/regularPractice/experienced, or **explicit null** for unknown. Swift's default omitted optional must be adapted to JSON null.

`programme` is null or `{id,timeZoneID,revision,days}`. `id` is `week:<IANA timezone>:<first YYYY-MM-DD>`, timezone is valid IANA, revision is a positive integer, and `days` contains exactly seven consecutive local dates. Each day is `{id,localDate,date,kind,plan}`: ID `programme:<timezone>:<localDate>`, `date` ISO8601 scheduled instant, kind workout/rest/recovery (no junior familyMovement), plan null for rest and non-null otherwise. Each plan is `{approvedAt:<ISO8601>,items:[...]}` with **no rationale**. Each item is exactly `{exerciseID,sets,target,unit,restSeconds}`: catalogue ID, sets 1–10, target 1–200 reps or 1–600 seconds, unit reps/seconds, rest 0–600 seconds. Items are unique by exercise ID, 1–12 per plan.

These are saved configuration bounds, not clinical suitability claims. Native restoration must revalidate the programme through Core `ConfigurableSession` and current local profile/support/age policy before launch. Preserve account/profile isolation. Supply a fixed local rationale when reconstructing `CoachSavedPlan`; no server-provided free text exists. Do not upload any local effort/history that informed the planner. ISO date encoding/decoding must be explicit (`JSONEncoder.dateEncodingStrategy = .iso8601`; decoder accepts UTC ISO8601 with/without fractions). Core's default seconds-since-2001 codec must never cross this boundary.

| Route | Exact request | Response |
| --- | --- | --- |
| `/plans/write` | `{profileSlot,adultEligible:true,cloudPlanSync:true,expectedRevision,preferences,programme}` | `{profileSlot,revision,updatedAt:<ISO8601>}`. New slot expects 0; existing slot requires its current server revision. |
| `/plans/read` | `{profileSlot,adultEligible:true,cloudPlanSync:true}` | `{profileSlot,revision,preferences,programme,updatedAt:<ISO8601>}`; 404 for missing/withdrawn/another account's slot. |
| `/plans/withdraw` | `{profileSlot,expectedRevision}` | `{withdrawn:true,revision}`. Clears saved content, keeps a revision tombstone to prevent stale writes resurrecting data. Store returned revision before any explicit later re-consent. |

All plan calls need signed access proof. Account ownership comes exclusively from that session. Revision checks and writes are conditional inside D1; concurrent same-revision writes have one winner. No endpoint lists another local profile's data or accepts accountID as authority.

## Private operational preparation and migration

Existing secrets: `AUTH_ENCRYPTION_KEY`, `AUTH_TOKEN_PEPPER` (preserve values). New server-only configuration:

- `RESEND_API_KEY`: owner-controlled Resend Free key. `RESEND_FROM`: verified sending address, e.g. `auth@<verified-domain>`. Missing key/sender fails closed. Owner must verify domain, account/free-tier status, DNS and delivery independently; do not put secrets in native bundles or source.
- `APPLE_CLIENT_ID`: the exact native Sign in with Apple audience (bundle identifier), `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY`: PKCS#8 P-256 **Sign in with Apple** key PEM. Correct App ID/capability/key association must be verified by owner. No ASC-key substitution, key guessing or environment fallback.
- Existing `ORIGIN` remains the HTTPS origin/RP source. No live provider flags or fake-verification environment bindings. Test-only dependency injection replaces the HTTP transport, never signature verification.

Before deployment: export/backup D1; review and apply 0002 additively; run staging authentication/legacy compatibility and provider/AASA checks; only then deploy reviewed Worker and native integration. Production provider readiness, real email delivery, associated-domain passkeys, runtime free CPU limits and physical-device acceptance remain unverified here. Local Miniflare success is not production performance or deployment evidence.

Rollback: retain 0002 tables and original 0001 data; roll code forward/fix or disable new native routing while retaining provider-revocation-aware legacy deletion. Do **not** drop native identity/refresh tables, revert to legacy code that silently deletes Apple-linked accounts without revocation, or roll back auth_version changes/recovery to resurrect revoked credentials. If no native account operations have occurred, code rollback before feature activation leaves additive tables inert. After activation, account/credential changes are real and require a separately reviewed recovery procedure and preserved backups.

Scheduled retention removes expired five-minute flows, 60-second challenges, 120-second nonce markers, spent-token records at old lease expiry and devices at refresh expiry. Quota reservations retain at most 38 days. Response ciphertext remains only with the spent-token record until its expiry; protected retrieval is restricted to the 60-second retry window. No real mail, live deployment, key provisioning or native capability edits were performed by this task.

Primary protocol references: [Apple token validation](https://developer.apple.com/documentation/signinwithapplerestapi/generate-and-validate-tokens), [Apple deletion and revocation](https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple), [Cloudflare D1 batch transactions](https://developers.cloudflare.com/d1/worker-api/d1-database/). A zero-row SQL update is not a transaction failure; every dependent mutation uses its successful conditional operation marker.

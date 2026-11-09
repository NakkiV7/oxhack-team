# Account and membership recovery polish

The user asks to finish Spottr account/subscription issues and improve the app. A read-only source investigation found four concrete dead ends. This phase fixes those normal flows without changing provider keys, server authentication requirements, purchase verification or workout/history isolation.

1. Cancelling the system passkey registration sheet must allow another attempt within the same still-valid identity flow. The first options request advances the server to registration. Reuse the corresponding outstanding creation options in memory rather than requesting an impossible second identity-to-registration transition. Bind the cached options to their current flow and expiry. Clear them on new flow, cancellation of the entire setup, successful stage advancement and expiry. Do not persist options or credentials for this retry. Recovery uses the already verified identity and backup proof within that same valid flow. If a verification request has an ambiguous committed response, provide an honest fresh-start route rather than automatically replaying an advanced server stage.

2. Backup-code choice belongs only to ordinary second-factor sign-in. New or replacement Authenticator enrollment always submits its new Authenticator code. Changing or cancelling flows clears transient input and backup selection. Preserve the store's defensive rejection of backup-based enrollment. A single rendered setup view must survive login with backup selected, cancel, then new account or recovery enrollment without an invisible sticky choice.

3. Keep the existing five-minute server expiry. Make temporary-flow expiry visible and actionable. An expired flow must hide its obsolete Authenticator secret, prevent futile completion requests and offer a styled Start again action. Clear temporary state without deleting local records or existing recovery-account credentials. Use an injectable clock at the relevant store boundary and a view lifecycle expiry check so this behaviour is deterministic and works when returning from another app. Avoid needless permanent timers. Normal valid setup needs clear, concise per-stage guidance and consistently styled primary actions.

4. An existing monthly subscriber attempting lifetime purchase must see pending or cancelled operation feedback. Separate operation-result feedback from generic catalogue status, keep it accessible next to membership actions, and clear/fence it across account changes and new operations. Pending purchase must not grant lifetime access or remove the existing monthly entitlement. Restore remains reachable for signed-out users. Preserve the warning that lifetime does not cancel monthly billing.

## Binding constraints

- Follow /Users/scsoc/.claude/TDD.md and add behavioural red-green regressions for all four findings.
- Existing server one-time transitions, UV passkeys, Authenticator MFA, backup-code use, device proofs, epoch/credential fencing and verified StoreKit entitlement gates remain intact.
- No auth bypass, fake membership, static reviewer credentials, secret exposure, new provider credential, paid API use or cloud raw-workout upload.
- Preserve guardian policy, junior protections, analytics opt-ins and existing local records.
- No human-style faces. Retain the abstract colour/waveform and faceless joint-stickman visual system.
- Use only existing simulator iPhone BF27AFBA-FF1E-4484-A3BD-42916CEB1170 with a controller-confirmed shared lease. No create, clone, erase, reset, uninstall or Watch simulator. No Chrome or new browser dependencies.
- All build/result artifacts belong on /Volumes/Spottr Development. Native jobs are serial with at most two build jobs and a scrubbed environment. Build 17, Vendor, all release archives and evidence remain untouched.
- Build 24 remains a frozen historical candidate. New reviewed native changes require a new build number before distribution or final iPhone install.
- Source fixes do not establish real inbox receipt, human MFA, Apple product availability, purchase or physical Watch/CV acceptance.

## Acceptance

Stateful transport tests enforce actual one-time options transitions for enrollment and recovery cancellation. Rendered view tests use one retained AccountSetupView for backup-choice leakage and expiry recovery, without bypassing its normal actions. Core and rendered membership tests show pending/cancelled lifetime outcomes with monthly access preserved. Existing account persistence, revocation, programme/workout launch and membership checks remain passing. Source and tests are reviewed before a fresh build and installation attempt.

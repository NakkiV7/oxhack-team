# Included Coach demo connection — integration handoff

Fresh installations default to `https://spottr.omarchoudhry.co.uk/demo`. A privately injected, expiring demo credential is validated and copied into this iPhone's Keychain on first use, without a network request. Existing custom connections remain selected; Coach settings offers an explicit reset and optional custom form. Missing, expired and Keychain-storage failures have actionable local errors. No automatic provider request or paid retry is introduced.

## Root's private injection contract

Root creates the credential, configures the existing VM and builds the release. This patch creates no actual credential and changes no live service or primary `.env`.

| Location | Contract |
| --- | --- |
| Private build input | Mode `0600`, ignored `.local/private-build/SpottrDemoAccess.json` |
| iPhone bundle output | `Spottr.app/SpottrDemoAccess.json` at the resource root; never a Watch resource |
| JSON fields | `token`: dedicated random 32–256 URL-safe ASCII characters (`A–Z`, `a–z`, digits, `_`, `-`); `expiresAt`: canonical UTC with milliseconds, `YYYY-MM-DDTHH:mm:ss.SSSZ` |
| Existing VM private env | `SPOTTR_DEMO_ACCESS_TOKEN` matches JSON `token`; `SPOTTR_DEMO_EXPIRES_AT` matches JSON `expiresAt`; `SPOTTR_DEMO_MAX_ATTEMPTS` is an explicit integer 1–100 |
| Expiry | Must be future and at most 24 hours away when gateway starts; retain the approved teardown of 26 October 2026, 06:47 UTC and existing $1 infrastructure ceiling |
| Existing owner identity | Keep `SPOTTR_GATEWAY_TOKEN` unchanged and distinct; never bundle it or a provider key |
| Keychain | Service `com.spottr.coach.gateway`, separate account `demo-access-v1`, `AfterFirstUnlockThisDeviceOnly`; custom token retains `access-token` |

The bundle credential is recoverable from a distributed app. Its strict route scope, expiry and shared provider-attempt budget are the access boundary. It is not a cloud account or a provider secret. A new valid private build can renew expired local access. Reset clears only connection selection and the two connection Keychain records, then reuses valid included access; it does not alter plans, profile or workout data.

### Project patch for root's owned generator

No project, Info.plist, TrainingStore, signing or release files are edited in this PR. Root may add this iPhone-only build phase to `scripts/generate-project.rb`, after resource setup and before saving the project:

```ruby
demo = app.new_shell_script_build_phase('Inject limited Coach demo access')
demo.input_paths = ['$(SPOTTR_DEMO_ACCESS_FILE)']
demo.output_paths = ['$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/SpottrDemoAccess.json']
demo.shell_script = <<~'SH'
  set -eu
  destination="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/SpottrDemoAccess.json"
  /bin/rm -f "$destination"
  if [ "$CONFIGURATION" = Release ]; then
    test -n "${SPOTTR_DEMO_ACCESS_FILE:-}" || { echo 'Private demo access file is required for this demo release.' >&2; exit 1; }
    test -f "$SPOTTR_DEMO_ACCESS_FILE" || { echo 'Private demo access file was not found.' >&2; exit 1; }
    /bin/cp "$SPOTTR_DEMO_ACCESS_FILE" "$destination"
    /bin/chmod 600 "$destination"
  fi
SH
```

Set `SPOTTR_DEMO_ACCESS_FILE` to the absolute private filename through root's local build setting/ignored xcconfig, including for a Release archive. Never put its contents into a build setting, command argument, tracked resource or log. Declare the input/output as above for existing Xcode script sandboxing. Root must validate the generated project, build-phase sandbox access and archive content. Debug builds can omit demo access and show the local unavailable message. This phase is a handoff snippet, not an executed native build.

## Server and proxy boundary

Public Caddy access is exact-path only for `/demo/v1/chat`, `/demo/v1/summary`, `/demo/v1/proposal`, `/demo/v1/week-proposal`, `/demo/v1/voice`, `/demo/v1/voices`. No prefix is stripped. The separate demo bearer authenticates only those aliases. The owner bearer cannot use the public aliases; all existing `/v1/...`, health and other routes retain the owner CIDR restriction. Landing `/` and `/assets/*` remain public. Demo bodies are capped at 64 KiB, and the voice handler retains its smaller limit. Proxy retries remain zero. See Caddy's [mutually exclusive handle behavior](https://caddyserver.com/docs/caddyfile/directives/handle) and [exact path matching](https://caddyserver.com/docs/caddyfile/matchers#path-matchers).

The existing guard reserves at most one provider attempt at a time across owner and demo coaching/voice requests, with an absolute expiry and finite nonrefundable attempt count. Invalid/authless requests and voice metadata cost no attempts; provider failures/timeouts consume one attempt and are never automatically retried. Voice cache hits do not invoke a provider and still require unexpired access. The existing budget is in process memory: a gateway restart resets its counter. Root must preserve cumulative accounting and reduce remaining attempts before any restart; this PR adds no durable ledger or automatic paid retries.

With dedicated demo access configured, owner database configuration remains permitted, but demo tokens cannot use `/v1/workouts` or any `/demo/v1/workouts` alias. Snowflake and owner configuration have no public demo route. Native `CloudSyncViews.swift` currently reuses Coach settings: default demo sync deliberately fails authentication/routing. Root should gate or label that UI in its integration lane. The inherited native HTTP 429/503 error text remains generic; root may refine `Shared/Core/CoachGateway.swift` status messages separately.

## Evidence and remaining gates

- Server TDD: five new auth/configuration/expiry/shared-budget tests first failed on the baseline, then passed. Added successful summary/workout/week alias and cross-identity concurrency tests. Existing guard/voice/contract tests are included in the full run: 93 tests passed, zero failures/skips with Caddy enabled. All requests use offline provider doubles.
- Caddy TDD: the real Caddy 2.11.7 loopback proxy test fails against the original configuration (403 instead of reaching demo authentication), then passes with this patch. It checks all six public aliases, protected health/workout/config paths, malformed demo prefixes and the landing page. `caddy adapt --validate` also succeeds against the actual configuration with synthetic settings. Local HTTP and synthetic CIDRs are not public TLS or cellular evidence.
- Reproduce the full server/proxy suite with an existing Caddy binary: `SPOTTR_TEST_CADDY=/absolute/path/to/caddy npm test --prefix server`. Without that variable, only the optional real-proxy test is skipped. No Docker engine, shared service, simulator or native build is started by the tests.
- `Tests/iOS/CoachSettingsTests.swift` was prepared before the native implementation. Root must run `SpottrTests/CoachSettingsTests` plus existing `SpottrTests/CoachFlowTests` and relevant settings UI checks in its serialized compiler queue. Native tests have not been compiled or run in this lane. Test names cover default/custom/reset, one-time private injection, malformed/missing/expired/overlong access, failed storage, renewal and offline stored access.
- Root still needs review/merge, private credential creation, server deployment/config validation, release-only private injection, archive audit and real-phone acceptance. On a fresh install on eduroam and cellular, verify no manual connection setup, no request on launch, explicit chat/session/week actions, optional configured voice, reset/custom behavior, expiry/exhaustion messages, and that protected owner/history paths stay blocked. No provider or phone acceptance is claimed by this PR.

Existing VM, funded balance and teardown deadline are unchanged. No actual token, secret file, provider call, paid resource, CI/CD change, deployment, simulator operation or TestFlight upload occurred in this lane.

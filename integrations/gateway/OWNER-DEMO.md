# Bounded owner demo

This optional gateway mode bounds synthetic owner coaching requests on a loopback or deliberately configured HTTPS gateway. The owner selected Vultr hosting; the historical Quick Tunnel commands below are not authorization to start a relay. It is implemented and tested offline. No relay, phone request or hosted service was started by this change. The Mac remains the compute host; this is separate from Vultr deployment and continuous service availability.

## Guard contract

Set **both** variables to enable the mode. With neither set, existing local gateway behavior remains unchanged. Partial, empty or invalid settings stop startup rather than falling back to unbounded mode.

| Setting | Accepted value |
| --- | --- |
| `SPOTTR_DEMO_MAX_ATTEMPTS` | Canonical decimal integer from 1 through 100, without whitespace or leading zeros |
| `SPOTTR_DEMO_EXPIRES_AT` | Future UTC timestamp in the exact `Date.toISOString()` form, including milliseconds and `Z`, at most 24 hours after startup |

Demo mode also refuses startup with a nonempty `TIGER_DATABASE_URL`. Only synthetic owner coaching is in scope; workout database access cannot be enabled in this mode.

One gateway instance shares one attempt budget and one active-generation slot across `/v1/chat`, `/v1/summary`, `/v1/proposal` and `/v1/week-proposal`. Authentication/input/configuration failures spend no attempt. A valid admitted generation consumes one attempt before contacting the provider, including unsuccessful, timed-out or canceled outcomes. Busy/exhausted requests return HTTP 429 immediately and are not queued or retried. Every valid coaching route returns HTTP 503 `demo_expired` at the absolute deadline; active generation is aborted at that deadline. Health remains available without provider calls, and unknown routes remain unavailable.

The budget is in memory. Restarting the gateway resets its count; the absolute expiry is unchanged. Do not use a watchdog or automatic process restart to replenish it. A new session/budget is an explicit operator decision. The attempt count is not an exact monetary cap, and cancellation cannot undo charges already incurred upstream.

Demo-only HTTP limits are five seconds for headers, ten seconds for receiving a complete request (checked at one-second intervals), 8 KiB of headers, 16 connections, 20 requests per socket and one-second idle keepalive. These read limits finish before provider generation begins. Existing 64 KiB coach input/output, 256 KiB provider-envelope, 2,048 output-token limit for existing routes, 4,096 for weekly proposals, and configured provider-timeout limits still apply.

## Operator commands, prepared only

Use this only during an approved owner demo window after reviewing the relay's terms/privacy and coordinating replacement of the existing **8788** process. Do not start another gateway against an occupied port or stop unrelated **8787**. Provider keys and the existing high-entropy owner bearer remain in ignored `.env`; do not paste them into commands, relay logs or a URL.

From the repository root, this example admits at most 12 generations over 30 minutes:

```sh
spottr_demo_expiry="$(node -p 'new Date(Date.now() + 30 * 60 * 1000).toISOString()')"
printf 'Owner demo expires at %s\n' "$spottr_demo_expiry"
HOST=127.0.0.1 PORT=8788 TIGER_DATABASE_URL='' \
  SPOTTR_DEMO_MAX_ATTEMPTS=12 SPOTTR_DEMO_EXPIRES_AT="$spottr_demo_expiry" \
  node --env-file=.env server/src/start.mjs
```

The shell overrides take precedence over `.env`, including the empty database URL. Verify the listener is exactly `127.0.0.1:8788`, health returns 200, and an unauthenticated coaching POST returns 401 without a provider call. Existing 8787 remains untouched.

If Cloudflare Quick Tunnel is separately approved and `cloudflared` has been installed from its official source, the proposed foreground relay command is:

```sh
cloudflared tunnel --url http://127.0.0.1:8788 --loglevel info
```

Confirm no inherited ingress/configuration exposes another service. Keep metrics local, keep the URL private, and arrange to stop the recorded connector at the gateway's printed expiry. Ctrl-C terminates the foreground connector. The gateway's deadline closes paid admission even if the connector is left running; **the public URL itself ends only when the connector stops**. No service installation, restart daemon, account, API token or DNS change is part of this procedure.

Quick Tunnels have a changing hostname, no uptime guarantee and a 200 in-flight-request ceiling, which is not a provider spending guard. Their email-authentication mode requires an interactive browser and does not support the current native URLSession client. The phone instead uses the generated HTTPS origin plus the existing owner bearer through Coach settings. Check public health/unauthenticated rejection without provider access first; an actual synthetic Coach action requires its separately authorized call allowance. Phone installation, trusted HTTPS and response rendering remain acceptance steps, not conclusions from local tests. See [Quick Tunnel documentation](https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/).

Cloudflare terminates HTTPS and processes traffic, including submitted facts and authorization credentials. The Google API key remains on the separate Mac-to-Google hop. Accountless service use is subject to [Cloudflare's terms](https://www.cloudflare.com/website-terms/) and [privacy policy](https://www.cloudflare.com/privacypolicy/); no agreement is represented as accepted here. Use synthetic facts, keep Tiger disabled, and use info-level logging: Cloudflare documents that debug logging includes request/response headers. [TLS processing](https://developers.cloudflare.com/data-localization/regional-services/http-requests/), [logging parameters](https://developers.cloudflare.com/tunnel/reference/run-parameters/).

## Verification

New offline behavior checks observed failures before implementation: ignored invalid settings, requests exceeding the shared allowance, post-expiry requests succeeding, and a stalled HTTP body outlasting 16 seconds. The implemented read limit returned HTTP 408 after approximately ten seconds with no provider attempt consumed. Further checks cover concurrent rejection, cross-route sharing, nonrefundable provider failures/timeouts, active deadline abort, database refusal and unchanged concurrent local behavior. Run `cd server && npm test`; tests use fake providers and no live database, public relay or external model call.

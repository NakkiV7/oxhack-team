# Vultr gateway deployment

Prepared 24 October 2026. Packaging is ready for a supervised single-owner hackathon deployment. No Vultr VM, account resource, credential, DNS record or public TLS certificate was created, and nothing was hosted. On 25 October the owner authorized Vultr use and the hostname `spottr.omarchoudhry.co.uk`. Google SSO succeeded; the console showed $5 credit and $0 current charges. Compute/storage/database/Kubernetes inventories inspected were empty. Credit expiry and eligible SKU restrictions were not displayed. No VM or DNS target has been created. API access is disabled and no SSH keys are registered; the browser deployment path remains available.

## What is packaged

Build from the repository root using `server/Dockerfile`. The image pins official Node **24.22.1 bookworm-slim**, an LTS security release, and its multi-platform digest. It installs locked production dependencies with lifecycle scripts disabled, runs as `node`, and contains only gateway source, migrations the canonical exercise catalogue and the bundled guidance registry. The catalogue must remain at `/app/Shared/Core/ExerciseCatalog.swift`, because the existing gateway reads it relative to its source. The Dockerfile-specific ignore file excludes `.env`, `.local`, Git history, native assets, node_modules and tests from the build context. Do not substitute `docker build server/` or use a remote builder with a broader context.

`deploy/compose.yaml` runs the gateway with a read-only root, no Linux capabilities, a 256 MB memory limit and no published gateway port. Caddy is the sole public service on TCP 80/443; its certificate/configuration volumes persist across restarts. The two image pins were checked against their official registry metadata. Updating them is an explicit maintenance step, followed by validation.

The Caddy configuration restricts callers to an explicit public client IP/CIDR allowlist, caps request bodies at 2 MiB, headers at 16 KB, header/body reads at 10/15 seconds and upstream response headers at 65 seconds. It uses an approximate overload threshold of four in-flight upstream requests and configures no proxy retries. Existing gateway limits remain stricter for coaching: 64 KiB input, 20-second default provider timeout (maximum 60 seconds), schema validation and no automatic paid retry. Proxy overload can return 503; these controls do not constitute a requests-per-minute or monetary budget.

## Authentication and data responsibility

This gateway uses **one owner bearer token**. It has no user registration, multi-tenant token registry, rate-limit account, token expiration or per-user revocation. `SPOTTR_INSTALLATION_ID` scopes optional Tiger sync to the single UUID shown by the owner's app; it does not create a separate identity for every token holder. Sharing the bearer token with other testers can expose the owner's synced history. Use only the owner's installation and synthetic demonstrations, and restrict the IP allowlist to the actual demo network. A public multi-user release needs a separate authentication, rate-limit and spending-control design.

The gateway receives the derived facts/chat text the user explicitly sends; Google receives the bounded coaching request. Goals and weekly targets can be included by the native Coach flow; optional profile names stay local. Optional Tiger sync persists the selected snapshot and supported telemetry in the configured database. Raw camera frames do not belong in these routes. Leave Tiger settings blank for a coaching-only deployment; no migration or synchronization runs on startup. The operator controls the server, provider accounts, secrets, retention, backups, access and eventual teardown. No database or data backup is created by this stack.

Caddy access logging is not enabled; Docker logs rotate at two 5 MB files per service. Operational/error logs can still contain network metadata, so do not enable debug/request-body logging or export raw logs casually. Secrets are runtime environment variables: host root/Docker administrators can inspect them. Keep private env files mode `0600`; never print resolved Compose configuration containing real secrets or run shell tracing. The Vultr infrastructure API key is not a gateway runtime dependency and must not enter the image/container.

## Concrete VM choices

The unauthenticated official [Vultr plans API](https://api.vultr.com/v2/plans?per_page=500) returned these USD list prices on 24 October 2026. Availability and the account's promotional eligibility are snapshots, not a confirmed quote or verified credit balance.

| Plan | RAM / storage / transfer | API price | Locations relevant to choice | Assessment |
| --- | --- | --- | --- | --- |
| `vc2-1c-0.5gb-free` | 512 MB / 10 GB / 0 GB listed transfer | $0 | Seattle, Frankfurt, Miami | Listed free SKU; eligibility and usable network allowance unverified. Do not assume access. |
| `vc2-1c-0.5gb-v6` | 512 MB / 10 GB / 512 GB | $0.003/hour, $2.50/month | New Jersey, Atlanta | IPv6-only; avoid for this phone demo until client/provider IPv6 connectivity is verified. |
| `vc2-1c-0.5gb` | 512 MB / 10 GB / 512 GB | $0.005/hour, $3.50/month | New Jersey | Cheapest listed paid IPv4 option, but tight headroom for OS, Docker and both containers. |
| **`vc2-1c-1gb`** | **1 GB / 25 GB / 1 TB** | **$0.007/hour, $5/month** | **London (`lhr`) available in response** | Recommended small demo candidate; no database on this VM. |

Vultr documents hourly billing with a one-hour minimum, and stopped instances continue to incur charges until destroyed ([billing policy](https://docs.vultr.com/support/platform/billing/how-am-i-billed-for-my-servers)). A 24-hour run of the recommended VM is approximately **$0.168 before tax and extras**. Credits, VAT, transfer overage, backups and snapshots must be checked separately. Do not add paid backups, snapshots, extra IPs, load balancers or managed databases by default. Container restart is automatic; it is not a spending cutoff.

Proposed final approval choice: one London `vc2-1c-1gb` Ubuntu 24.04 VM with its standard IPv4, for at most 24 hours, proposed **$1 total infrastructure ceiling**, no optional paid resources; use existing approved SSH access and one explicitly approved DNS hostname. Confirm account credits cover that SKU and agree the destruction time before creation. Reuse a suitable existing VM if one is already available and authorized. This proposal does not authorize provisioning or destruction.

## Setup after resource and hostname approval

Use a reviewed source commit in `/opt/spottr` on the approved VM. Install Docker Engine and the Compose plugin only through the [official Ubuntu instructions](https://docs.docker.com/engine/install/ubuntu/). Keep SSH restricted to the operator's public IP using existing keys. At the Vultr firewall, allow only operator SSH and public TCP 80/443; do not open 8787, 2019 or database ports. Apply the equivalent host policy without locking out the current SSH session. Docker publishes ports through its own networking rules, so check the actual external exposure rather than relying solely on UFW.

Point the approved hostname's A record at the VM. Add an AAAA record only if that IPv6 address is configured and reachable. Caddy's public certificate automation requires correct DNS, inbound 80/443 and persistent writable certificate storage ([automatic HTTPS](https://caddyserver.com/docs/automatic-https)). The service is intended to be reached directly, so its `remote_ip` allowlist identifies the caller's network egress; placing an unreviewed CDN/proxy in front changes that meaning.

From the checked-out repository root, create private configuration:

```sh
umask 077
cp deploy/gateway.env.example deploy/gateway.env
cp deploy/deployment.env.example deploy/deployment.env
chmod 600 deploy/gateway.env deploy/deployment.env
```

Privately set the existing owner token, existing Gemini key and account-enabled model in `gateway.env`. Set the approved hostname/email and exact client public CIDRs in `deployment.env`, and change `SPOTTR_GATEWAY_ENV_FILE` to `./gateway.env`. Do not use the loopback-only example as a working phone allowlist. Optional Tiger TLS must use a trusted certificate chain; if an additional public CA is needed, add an explicit read-only CA mount and `NODE_EXTRA_CA_CERTS`. Never set `NODE_TLS_REJECT_UNAUTHORIZED=0` or weaken database verification.

Validate and build; these commands alone do not start Caddy or issue certificates:

```sh
docker compose --env-file deploy/deployment.env -f deploy/compose.yaml config --quiet
docker compose --env-file deploy/deployment.env -f deploy/compose.yaml build gateway
docker compose --env-file deploy/deployment.env -f deploy/compose.yaml run --rm --no-deps caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
```

Start only after approval of the real service/data path:

```sh
docker compose --env-file deploy/deployment.env -f deploy/compose.yaml up -d
docker compose --env-file deploy/deployment.env -f deploy/compose.yaml ps
```

The gateway health check calls only local `/health`, and requires `status: ok` plus `authenticationConfigured: true`. It does not validate the bearer token's quality, contact Google, run SQL or establish provider readiness. Caddy waits for this health check. Docker does not restart a container merely because it becomes unhealthy; inspect health failures explicitly.

## Provider-free acceptance, then one deliberate paid check

From an allowed network, use a bounded GET:

```sh
curl --fail --max-time 5 https://APPROVED_HOSTNAME/health
curl --max-time 5 -o /dev/null -w '%{http_code}\n' -X POST https://APPROVED_HOSTNAME/v1/chat
```

Expect health 200 and the unauthenticated protected POST 401. Confirm an outside-allowlist client gets 403, and external 8787/2019 are unreachable. Verify a trusted TLS chain on the phone; do not bypass certificate validation. Enter the HTTPS origin and existing owner token through the native developer settings. Only then deliberately send one synthetic bounded Coach request if authorized, record its actual response/latency and check it contains only supplied facts. Provider health booleans alone do not prove this path.

For optional Tiger, migration, explicit synthetic smoke and real native sync remain separate authorized steps; see [gateway instructions](../integrations/gateway/README.md). Do not apply migrations during container startup. A request can continue on the provider until the server's timeout after the phone dismisses its UI; client cancellation is not a monetary guarantee.

At the agreed deadline, first stop this stack with the exact command below, export only explicitly required data, and have the authorized operator destroy the exact approved VM to stop Vultr billing. Do not delete other resources or remove volumes during a temporary restart.

```sh
docker compose --env-file deploy/deployment.env -f deploy/compose.yaml down
```

## Verification performed and remaining limits

On 24 October 2026 the actual image and Caddy configuration passed local container checks. A task-specific Colima profile supplied the engine; the existing `desktop-linux` context was preserved. The profile was stopped and its test containers removed afterward. No Vultr resource, public certificate or paid provider call was involved.

- The root Dockerfile built in 17.12 seconds from a 68.57 kB context with locked production dependencies. Image `sha256:1f59556a4b1bb2885e548a9cdf56c49f1f7835ee309eb7e0bb0f358c52ffa38e` is Linux/arm64, 82,640,575 bytes. All 19 copied runtime/catalogue files matched source hashes; private configuration, native assets and tests were excluded.
- With networking disabled, the gateway ran as UID 1000 with a read-only filesystem, no Linux capabilities and no published ports. Docker health passed. HTTP checks returned 200 for health, 401 for missing/wrong tokens, 404 for an unknown route and 503 for an unconfigured provider.
- A separate built-image HTTP check injected an in-memory fake provider configuration: malformed JSON returned 400; unknown fields and blank messages returned 422. There were **zero provider calls**. The actual container's provider settings stayed blank.
- The pinned Caddy image parsed the actual `deploy/Caddyfile` with blank example configuration and networking disabled: exit 0, valid configuration. Compose validation also passed. This verifies parsing, not certificate issuance, external CIDR enforcement or hosted HTTPS.
- The earlier gateway checkpoint passed **51/51** offline tests, including the server-owned catalogue context used by chat. The historical [container receipt](evidence/container-verification-2026-10-24.json) records that image and its checked source hashes; the current weekly image is recorded separately below.

Hosted acceptance remains: approved account/credit/hostname scope, an actual deployment, trusted HTTPS on the phone, allowlist/external-port checks and one deliberate authenticated request. The local ARM64 image check does not establish an AMD64 build or Vultr host behavior.

References: [Node release index](https://nodejs.org/dist/index.json), [official Node image](https://hub.docker.com/_/node), [Dockerfile-specific context exclusions](https://docs.docker.com/build/concepts/context/#dockerignore-files), [Caddy proxy limits](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy), [Caddy request size](https://caddyserver.com/docs/caddyfile/directives/request_body), [Vultr compute overview](https://docs.vultr.com/product-overviews/cloud-compute).

## 25 October account and domain checkpoint

- The existing `omarchoudhry.co.uk` Cloudflare zone is active under the personal account. The owner-approved `spottr` hostname has no existing DNS records, so no domain purchase or overwrite is needed. Add its A record only after the actual Vultr IPv4 is known; do not use a placeholder IP.
- The standard London Regular Cloud Compute form offered 1 vCPU / 1 GB / 25 GB / 1 TB at $5 per month ($0.007 per hour). Automatic backups were selected by default and added $1 per month; a 20% VAT notice was visible. Disable optional backups for the bounded demo. These are console snapshots, not a created instance or a billing guarantee.
- Keep infrastructure credentials off the VM. API access has not been enabled and no broad account API key has been created. Existing local public SSH keys are available for an explicitly chosen deployment path; private keys stay on the Mac.
- The owner requested Vultr hosting rather than a Cloudflare relay. Cloudflare DNS is separate from a relay; no tunnel or relay has been started.
- No active $300 Google credit was verified. The checked Google account shows AI Studio Free tier / no billing account and all seven visible Cloud projects have billing disabled. Current [Google billing rules](https://ai.google.dev/gemini-api/docs/billing) exclude Welcome credits from Gemini Developer API / AI Studio; a credit-eligible Vertex configuration would be a separate integration. Credits do not remove the need for trusted HTTPS and gateway authentication.
- The [25 October weekly ARM64 image check](evidence/container-weekly-verification-2026-10-25.md) passed against commit `7868d1d`: all 23 copied runtime hashes matched, including guidance JSON. UID 1000/read-only/network-none runtime, health/authentication and unconfigured weekly-route checks passed; an in-memory provider double produced valid weekly output and rejected invented guidance. Zero external provider calls; task container removed, task Colima profile stopped, default Docker context preserved. This does not establish AMD64, Vultr deployment or hosted HTTPS.

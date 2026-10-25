# Tiger live readiness — 24 October 2026

## 25 October gateway follow-up

At **07:23:45 UTC**, one bounded strict Node/`pg` read of the original configured service again failed with `SELF_SIGNED_CERT_IN_CHAIN`, before authentication success or SQL execution. The URI retained `sslmode=verify-full`; no CA, trust-store, provider configuration or data change occurred. The sanitized private receipt is `server/.local/data-integrations-20261025/strict-read.json` in the data-integrations worktree. This is the latest check in this lane; earlier console schema acceptance remains separate.

The existing teammate service in project `bhm5qdw7yb`, service `k1za89x0ef`, port `38300` has the primary chat's independently verified public-TLS handshake receipt, but its authorized credentials are absent locally. Do not reuse the original password against it. The remaining gate is either a provider-authenticated trust/certificate correction for the original service, or authorized connection details for that existing teammate service. Preserve both services and inspect its existing schema before any migration. The primary's private `.local/tiger-live-20261025/portal-next-steps.md` has the exact portal route. No Safari, credential reset, support message or new service was used here.

### Gateway rollup acceptance contract

`createTigerStore().rollups({ workoutID, from, to, bucketSeconds })` now queries **`spottr_gateway.scalar_sample`**, the actual gateway schema. `bucketSeconds` must be numeric `5` or `60`; the increasing `[from,to)` interval is at most 24 hours. The read checks owner/workout existence, then binds owner, workout, interval and bucket width. PostgreSQL [`date_bin`](https://www.postgresql.org/docs/current/functions-datetime.html#FUNCTIONS-DATETIME-BIN) aligns bins to an explicit UTC origin. This is an on-demand aggregate of existing hypertable rows: no migration, scheduled policy, materialized view, retention, backfill or data deletion is involved.

Each returned bucket retains sensor kind, unit, source, distinct observed-row count, mean/min/max, and first/last measurement timestamps. Retained Watch readings were already deduplicated by kind and observation time on ingestion. Counts are **observed samples**, not seconds of coverage; these are sample-weighted means, not time-weighted physiology. An empty interval returns no buckets. Window filtering happens before aggregation, so a boundary bucket can be partial; use the echoed `from`/`to`, bucket width and first/last times when presenting it. No missing-value filling, interpolation, readiness or clinical inference is performed.

The operator smoke command remains `cd server && npm run tiger:smoke -- --allow-live-synthetic`. It now refuses malformed/non-PostgreSQL URLs, absent/ambiguous/non-`verify-full` SSL modes, conflicting `ssl` settings and global TLS-verification bypasses **before constructing a pool**. Any approved provider CA still needs independent provenance; this code does not acquire or trust a socket chain.

After the access gate clears, the same immutable year-2000 fixture still creates at most **one snapshot/four scalar rows**, preserving original fixture IDs and hashes. The command checks replay/conflict/readback, raw half-open/gap reads, 5-second/minute rollups, partial-window counts and empty rollup gaps, returning sanitized counts and timings. It has not passed against live Tiger. The adapter method is prepared for primary integration; this PR adds no HTTP route, native UI or public-gateway deployment.

Local acceptance executes the real gateway migration and ingestion/rollup SQL inside embedded PostgreSQL (PGlite, a test-only dependency), omitting only Timescale extension/hypertable calls. Hand-checked varying fixtures verify means, counts, timestamp boundaries, gaps, replay, conflicts and isolation from other owners/workouts. This establishes PostgreSQL SQL behavior, not Timescale partitioning, provider TLS/authentication, live latency or device acceptance. The older `spottr` continuous-aggregate proposal below remains review-only and is unrelated to this gateway method.

**Gateway persistence remains blocked by certificate-chain trust. The development schema has separate provider-console acceptance.** By **23:37:35 UTC**, the authenticated console applied the exact gateway migration and read-only catalogue checks accepted its two empty tables, constraints, hypertable and indexes. No workout or sensor data was inserted. This does not establish a trusted Node connection or app writes. [Console receipt](evidence/tiger-console-2026-10-24.md).

The historical strict-connection review below was recorded at **20:17:57 UTC**. It performed one bounded strict PostgreSQL connection attempt and one strict TLS-only certificate inspection, with no database authentication success, SQL execution, migration, synthetic insertion or credential output at that checkpoint. No trust store, connection string or service setting was changed.

## Current service and endpoint

Service `hndd7wbr1z`, project `ucep75shdl`, was converted from shared free compute to the smallest standard service at approximately 18:35 UTC. The authenticated Safari Connect dialog was inspected by the parent task and confirmed that the stored connection details still match exactly:

- Host: `hndd7wbr1z.ucep75shdl.tsdb.cloud.timescale.com`
- Port: `34147`
- Database: `tsdb`
- User: `tsdbadmin`

No password or full connection URI is recorded here. The Connect dialog offered no CA download. The stale-endpoint hypothesis is therefore resolved for these connection fields. Provider provisioning and the previously observed console versions (PostgreSQL 18.6, TimescaleDB 2.31.0) do not establish gateway connectivity or schema persistence.

## Strict connection evidence

The existing `pg` pool configuration was used with one connection, a five-second connection/statement deadline and a seven-second query deadline. Stored `sslmode=verify-full` was checked, and a globally disabled TLS-verification setting was ruled out before connecting. The intended query read server/extension versions and `pg_stat_ssl`; connection negotiation failed before that query with **`SELF_SIGNED_CERT_IN_CHAIN`**.

An OpenSSL PostgreSQL STARTTLS probe used both `-verify_return_error` and `-verify_hostname`. It returned verification error **19** and the following nonsecret certificate metadata:

| Certificate | Issuer | Validity |
|---|---|---|
| Service leaf | `O=Timescale Inc, CN=ca.timescale.com` | 24 October 2026 18:35:39 UTC → 20 July 2029 18:35:39 UTC |
| Self-issued root | `O=Timescale Inc, CN=ca.timescale.com` | 23 January 2025 15:43:39 UTC → 20 October 2027 15:43:39 UTC |

The leaf issuance time matches the conversion time, but this does not authenticate the private CA. Receiving a CA from an unverified endpoint is not sufficient authority to trust it. The observed chain still lacks a trust anchor accepted by the client.

Tiger's [strict SSL guidance](https://www.tigerdata.com/docs/use-timescale/latest/security/strict-ssl) describes temporary self-signed initialization, subsequent public signed-certificate replacement normally within about 30 minutes, and stricter verification once the signed certificate exists. More than 100 minutes had elapsed at the recorded review time. Its [current psql guidance](https://www.tigerdata.com/blog/how-to-install-psql-on-mac-ubuntu-debian-windows) also describes public-CA verification. These documents do not prove issuance succeeded for this service; repeating a timed wait is not a diagnosis.

## Concrete next action, without new cost

1. Complete the authenticated service Security/Operations inspection already owned by the parent task. Look for certificate/provisioning status or an authenticated provider CA download/fingerprint; do not reset credentials or alter service resources merely to retry.
2. If no supported trust source exists there, prepare a provider support request through the existing authenticated console: identify the service/project, conversion time, confirmed endpoint, strict error 19 / `SELF_SIGNED_CERT_IN_CHAIN`, Timescale CA issuer and leaf issuance time. Ask Tiger to finish the public certificate deployment or provide its supported CA chain and SHA-256 fingerprint through an authenticated provider channel. Sending that request remains a separate external action.
3. If Tiger provides an authenticated CA bundle, validate its provenance/fingerprint and hostname coverage, then configure that server's PostgreSQL client with the supported CA while retaining full chain and hostname verification. Do not install the observed chain solely because a socket presented it. No supported authenticated CA bundle was found in this review; no CA was installed.
4. After a provider-confirmed change, run one bounded read-only version/TLS query. Only a successful, authorized strict Node connection advances the gateway to smoke-test readiness. The existing development schema was separately accepted through the console; inspect it rather than blindly rerunning the migration. The explicitly opted-in isolated synthetic smoke command remains a later acceptance step.

The [connection-details documentation](https://www.tigerdata.com/docs/integrate/find-connection-details) identifies the authenticated Connect dialog and separately provisioned API credentials. No Tiger connector, configured API credentials or installed Tiger CLI was available to this review. No account or new credentials were created.

## Why SSH does not resolve this blocker

No provider-managed SSH access endpoint was found for this service. An SSH tunnel to an unrelated host would still have a separate host-to-Tiger connection; removing TLS on that leg would not authenticate the database. Keeping strict PostgreSQL TLS through a tunnel preserves the same unresolved CA requirement. Tiger's [networking guidance](https://www.tigerdata.com/learn/postgres-security-best-practices) describes managed service access over TLS, and [console integration guidance](https://www.tigerdata.com/docs/build/data-management/run-queries-from-tiger-console) describes tunnels for network reachability. Neither establishes SSH as an alternative authenticated transport to this database. No tunnel, VM or new networking resource was created.

## Offline acceptance remains separate

`cd server && npm test` passed **36/36 checks** during this review, using provider/database doubles and local test servers. The checks cover immutable snapshots, scoped readback, observed scalar data, rollback, schema/metadata validation and explicit live-smoke opt-in, along with gateway/Snowflake boundaries. They do not prove live Tiger schema execution, persistence, rollups or native sync. Keep the live status **blocked** until the strict read succeeds; the offline adapter remains usable for development.

## TLS-only follow-up — 25 October 00:37 UTC

The current [official strict-SSL documentation](https://www.tigerdata.com/docs/deploy/tiger-cloud/tiger-cloud-aws/security/strict-ssl) still describes temporary self-signed initialization followed by a public certificate, and explicitly documents inspecting whether replacement has occurred. One bounded, strict OpenSSL STARTTLS/hostname probe at **00:37:05 UTC** returned exit 1 / verification error **19**, `self-signed certificate in certificate chain`. No database login, SQL, provider configuration or trust-store change occurred. This confirms the same unresolved trust condition; it does not establish its cause.

### Prepared provider-support text

This is a draft for the account owner to submit through the authenticated support channel; it has **not been sent**.

> Our Tiger service `hndd7wbr1z` in project `ucep75shdl` was converted from shared free compute to the smallest standard service at approximately 18:35 UTC on 24 October 2026. The authenticated Connect dialog confirms host `hndd7wbr1z.ucep75shdl.tsdb.cloud.timescale.com`, port `34147`, database `tsdb`. Strict PostgreSQL TLS still fails with `SELF_SIGNED_CERT_IN_CHAIN` / OpenSSL verification error 19 at 00:37 UTC on 25 October, more than six hours later. Earlier inspection found a Timescale private-CA leaf issued at 18:35:39 UTC. Please confirm public-certificate provisioning status and finish deployment, or provide the supported CA chain and its SHA-256 fingerprint through this authenticated channel. We are retaining full chain and hostname verification and have not imported the unverified socket chain. No database password is included in this request.

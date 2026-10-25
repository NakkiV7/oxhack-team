# Tiger live readiness — 24 October 2026

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

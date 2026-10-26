# Tiger Data access checkpoint — 25 October 2026

**Gateway persistence and rollups are implemented and tested offline; live gateway acceptance remains blocked by trust/access.** No provider support request was sent during the time-limited hackathon check.

## Successfully implemented and verified

- The [gateway adapter](../../server/src/tiger.mjs) stores owner-scoped immutable snapshots, rejects conflicting retries and extracts deduplicated observed scalar samples. Reads use bounded half-open windows; rollups provide counts, mean/min/max and observation times without filling missing gaps. They preserve kind, unit and source.
- [Offline behavior checks](../../server/test/tiger.test.mjs), [rollup SQL checks](../../server/test/tiger-rollup.test.mjs) and [gated-smoke checks](../../server/test/tiger-smoke.test.mjs) exercise these paths. Rollup SQL runs against test-only PGlite; that does not execute Timescale-specific extension/hypertable behavior or prove provider access.
- The authenticated provider console separately applied the exact [gateway migration](../../server/migrations/001_workouts.sql) and verified two empty tables, 15 columns, seven PK/CHECK constraints, the one-day scalar hypertable and four usable indexes. No workout/sensor rows were inserted. See the [24 October console receipt](tiger-console-2026-10-24.md).

Run the network-free Tiger checks from the repository root after installing the existing server dependencies:

```sh
node --test server/test/tiger.test.mjs server/test/tiger-rollup.test.mjs server/test/tiger-smoke.test.mjs
```

## Actual live blocker and investigation

The original service's last retained bounded strict Node read, at **07:23:45 UTC**, failed with `SELF_SIGNED_CERT_IN_CHAIN` before authentication/query execution. Earlier inspection observed a Timescale private-CA chain. No trust-store change or disabled certificate/hostname verification was used. No subsequent blind connection retry was made in this portal check; the current certificate state was not re-probed.

The signed-in account opened its original service successfully. Navigating to the documented teammate project redirected it to the original project; no authorized teammate URI was available. This is observed UI redirection, not a complete membership audit or captured API authorization diagnosis. An earlier strict TLS-only check of the teammate endpoint passed chain and hostname verification, but sent no database authentication or SQL and does not establish database access.

The Mac initially locked. After manual unlock, the investigation completed by **08:52 UTC**: Operations → Security offered networking/passwordless controls; Overview → Connect showed connection fields and installation guidance. Neither inspected surface exposed a CA download, fingerprint or certificate-provisioning repair action. No credentials were created/reset, service resources changed, teammate migrations run or real health data uploaded.

## What remains unavailable

There is no independently accepted strict gateway SQL connection, live synthetic ingestion/replay/conflict/readback, live provider rollup result or native-to-Tiger sync from this attempt. The [standalone push-up prototype](../../prototype/pushup/README-pushup.md) uses its own schema and contributor evidence; it does not validate the gateway path.

Local training/reports and the offline tests remain demonstrable. Resuming live acceptance requires a provider-authenticated CA bundle/fingerprint or completed public-certificate deployment for the original service, or an authorized URI for the existing teammate service. Then run one strict metadata-only catalogue read, compare the actual schema, obtain review before any necessary migration, and run the existing explicitly gated synthetic smoke: at most one artificial year-2000 snapshot/four scalar rows, with replay/conflict/readback/window/rollup assertions. No real health upload is needed. See [live readiness](../tiger-live-readiness.md) and the [smoke guide](../../integrations/gateway/README.md#opt-in-tiger-smoke-test).

# Tiger console schema acceptance — 24 October 2026 UTC

**The gateway schema is accepted through the authenticated provider console. The Node gateway's strict TLS connection remains blocked.** No workout or sensor data was inserted. Console acceptance does not establish gateway connectivity, ingestion, replay/conflict behavior or native sync.

## Scope and execution

The operator used Tiger's authenticated Explorer against the existing development service. Only [server/migrations/001_workouts.sql](../../server/migrations/001_workouts.sql) was applied: **1,506 bytes**, SHA-256 `229c3e7ff228e7ea07224496b20840ca2f8d40100c84a97a26572b1aae07f18a`. The separate review-only `integrations/tiger` proposal and standalone push-up migrations were not applied.

Operator-observed preflights, reported to the independent reviewer:

- **23:16:03 UTC:** one version query returned PostgreSQL **18.6**, TimescaleDB **2.31.0**, and `pg_stat_ssl.ssl=true`.
- **23:17:33 UTC:** `spottr_gateway` was absent; both target relations resolved to null.
- A read-only transaction showed `on`, then an assertion-checked rollback showed `off` on the same backend. A deliberate division-by-zero batch failed without executing its trailing sentinel query. This established observed transaction affinity and visible batch failure for that console session.
- **23:25:22 UTC:** the recovered session again showed an absent namespace, writable primary and schema-creation permission. Timescale routines were also checked as visible/executable before DDL. The exact migration then returned **Success**, **0 rows affected**, with a UI duration of **0.7 seconds**, before the **23:26:59 UTC** clock observation. This is a console receipt, not an ingestion-latency benchmark.

These preflight/version observations were operator-reported rather than preserved as AX row receipts. Postflight table values below were independently parsed from the saved private AX receipts. An incomplete long SELECT draft was abandoned without execution; acceptance uses the subsequent compact-query editor only.

## Independently checked catalogue results

Completed by **23:37:35 UTC**, using read-only catalogue queries and row counts:

| Check | Actual result |
| --- | --- |
| Namespace and ownership | Exactly two tables, `workout` and `scalar_sample`; schema/table ownership matches the execution role. |
| Columns | All **15** definitions match: five snapshot columns and ten scalar columns, including order, built-in types, `NOT NULL`, absence of domains/identity/generated columns, and defaults. Only the two `received_at` columns default to `clock_timestamp()`. |
| Constraints | **Seven validated** constraints: two primary keys and five CHECKs. PostgreSQL 18's separate NOT NULL catalogue entries are excluded from this count; nullability is verified with the columns. |
| Scalar CHECK | The complete **433-character** definition was reconstructed from **300 + 133** characters. All three correctly grouped alternatives match: heart rate/bpm/1–300; acceleration magnitude/g/0–1000; rotation magnitude/rad/s/0–1000. Source is restricted separately to `apple_watch`; sample index is 0–7199. |
| Hypertable | `scalar_sample`, one `Time` dimension on `measured_at`, interval **1 day**, **0 chunks**. An empty hypertable requires no physical chunks. |
| Indexes | **Four usable** indexes, with valid/ready/live all true: both expected unique primary-key indexes, `scalar_sample_workout_time`, and Timescale's additional `measured_at DESC` index. The three required index definitions and key order match the migration. |
| Data | `workout`: **0 rows**; `scalar_sample`: **0 rows**. |

Private AX receipts and screenshots remain under ignored `.local/tiger-console/`; they are not published with account or billing details. The AX text exposes the actual table values; screenshots alone are not the basis of the value comparisons.

## Remaining acceptance

The console's TLS-protected database connection is distinct from the gateway connection that fails certificate-chain verification. No CA, trust store, connection setting, grant, retention/rollup policy or destructive cleanup was changed. The migration created the new schema, tables, hypertable and indexes; it did not validate application writes.

A supported trust resolution and successful strict Node read remain necessary before the explicitly opted-in [gateway smoke test](../../integrations/gateway/README.md#opt-in-tiger-smoke-test). Immutable ingest/replay/conflict, snapshot/scalar readback, gateway-role access and actual native sync remain unverified. No synthetic fixture or real biometric measurement was used here.

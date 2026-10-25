# Existing-account acceptance handoff

This is the operator procedure for the pinned public PAMAP2 SQL API evaluation. It adds no Cortex, RAG, LLM, native-app or Watch acceptance. The importer and configuration-only command are supplied by [PR #132](https://github.com/NakkiV7/oxhack-team/pull/132); integrate that reviewed change before using `--check-configuration` below. Do not copy or reimplement its provider code.

## Establish the existing-resource scope

Keep an independent, ignored `.local/snowflake-live-20261025/account.env` with mode `0600`. Preserve the original `.env` and `root.env`. Set only the existing account/token/token type, warehouse, database, schema and optional existing role; transfer secret values privately, never through command arguments, receipts or commits. An authenticated Snowsight session does not establish an available SQL API token. Do not create/reset credentials or use browser session cookies as an API token.

Before SQL, inspect existing account metadata through the authorized account surface and record the chosen database/schema, table existence, effective role, warehouse size/status/auto-suspend and credit scope privately. Account and warehouse values in an old local file are configuration, not live verification. Do not create databases, schemas, roles or warehouses, grant privileges, resize a warehouse or change suspension settings for this procedure. The existing role needs USAGE on the chosen warehouse/database/schema and SELECT/INSERT on the target table.

If the table is absent, stop and give the integration owner the **resolved existing database and schema**, effective role, exact SQL below and its scope for review. The identifiers below are placeholders; they must be replaced with reviewed existing identifiers before approval or execution. No table creation has been authorized or executed by this document.

```sql
CREATE TABLE <EXISTING_DATABASE>.<EXISTING_SCHEMA>.SPOTTR_PUBLIC_PAMAP_FORECAST_RUNS (
    RUN_ID VARCHAR(64) NOT NULL,
    PAYLOAD_SHA256 VARCHAR(64) NOT NULL,
    PAYLOAD VARIANT NOT NULL,
    IMPORTED_AT TIMESTAMP_LTZ NOT NULL DEFAULT CURRENT_TIMESTAMP()
);
```

The scope is one standard table, four columns, no replacement/deletion/grants and no other resources. This is the qualified form of [001_public_pamap_forecast.sql](001_public_pamap_forecast.sql). Inspect an existing table's definition and privileges before reusing it; do not replace an incompatible table. Standard-table uniqueness is not enforced: keep a single operator, and stop on duplicate/conflicting run IDs.

## Network-free preparation

From `server/`, after PR #132 is integrated:

```sh
node --env-file=../.local/snowflake-live-20261025/account.env src/snowflake-benchmark-cli.mjs --check-configuration
node src/snowflake-benchmark-cli.mjs
```

Use the config path for the checkout that actually holds the private file. Node gives an inherited environment variable priority over an env-file value: use a clean, reviewed process environment so stale `SNOWFLAKE_*` settings cannot silently select another account. Do not print the environment to diagnose it.

The first command must return `ready:true` before any live attempt. It consumes no warehouse credits and proves only syntactic completeness. The second must return the unchanged manifest run ID and payload digest:

| Field | Required value |
| --- | --- |
| `runID` | `5b0bf1d168c094f5e45aa799e77a9723431e04d79b3c3b8bffe8d7e374865024` |
| `payloadSha256` | `d52c503e2face2f95d84e1784a894c71cb20bc4070e0400864e13bccbdc6e12d` |
| `sourceRows` | `1622` |
| metric rows | `18` |

A complete config or passing dry run does not prove authentication, object access, SQL syntax or warehouse execution. Preserve each command's exit status and sanitized JSON receipt.

## One deliberate public import

After the existing resources, table and credit scope have been confirmed, run once:

```sh
node --env-file=../.local/snowflake-live-20261025/account.env src/snowflake-benchmark-cli.mjs --allow-live-public-data
```

This uploads only the pinned derived public artifact. It performs at most four statement submissions on an absent run: lookup, insert-only MERGE, lookup and evaluation. An already matching run uses two reads and skips MERGE. All values are bound; there is no arbitrary SQL argument, refitting or download step. Do not run a second import merely to demonstrate replay: offline tests cover that behavior, and a second paid attempt needs a separate reason and authority.

The client limits each statement to 60 seconds, each HTTP operation to 10 seconds, total polls across the workflow to 10, and total elapsed budget to 90 seconds including reserved cancellation time. Those are execution limits, not a verified credit charge or monetary cap. Retain actual usage separately when available; never infer zero cost from a failed or cancelled request.

Stop on the first failure. A submission with no returned handle can have uncertain server execution; a known pending statement gets one cancellation attempt. Resolve the request in query history or its known handle before replay; follow the uncertain-submission instructions in [the analytics guide](../../docs/snowflake-analytics.md). Never automatically resubmit, expand the polling budget, renew credentials or resume/resize resources to make a failed acceptance pass.

## Reviewable evidence

Keep sanitized receipts in the ignored local handoff directory. Record UTC start/end, exact command and exit status, implementation commit, config **filename** and permissions, request/submission counts, any known pending/cancellation status, run ID/digest, `mode`, `replayed`, returned metric count and reconciliation outcome. Keep account context and query-history details private; exclude tokens, headers, provider bodies and browser states from shared evidence.

A successful receipt requires `mode:live`, the pinned hashes, 1,622 source forecasts and all 18 reconciled metric rows, including the zero-scored participant/horizon and one contributing participant for the 30-second macro metric. Record software tests, account inspection, live SQL/import, usage and physical acceptance as separate evidence. If access is missing, report the exact missing names and zero submissions rather than presenting offline metrics as Snowflake results.

Official request/context/binding behavior: [Snowflake SQL API](https://docs.snowflake.com/en/developer-guide/sql-api/submitting-requests). The existing [analytics guide](../../docs/snowflake-analytics.md) remains the implementation and uncertainty reference.

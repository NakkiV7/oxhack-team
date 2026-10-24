# Snowflake retrospective analytics

Tiger's implemented adapter is intended to store operational workout snapshots and observed Watch measurements; live TLS acceptance remains pending. Snowflake's implemented role is a bounded, explicit batch import and retrospective evaluation of the reviewed public PAMAP2 forecast experiment. It compares the frozen HR ridge, latest-value persistence, and fixed adaptive-bias model by participant and horizon, retains coverage including zero scored forecasts, and computes participant-macro metrics with the number of contributing people.

## Current status and dry run

Implementation and fake-network tests are complete. No Snowflake query, table creation, import or warehouse execution has been performed by this task. The existing fixed connection-check command remains available; configured credentials alone do not establish a successful analytics import.

From `server/`:

```sh
npm run snowflake:benchmark
node src/snowflake-benchmark-cli.mjs --artifacts ../research/hr_forecast
```

Both commands are local dry runs. They validate pinned files and print the run/payload hashes, source-row count and 18 expected evaluation rows. They do not inspect Snowflake credentials or contact a provider. There is no arbitrary SQL argument and no download/refitting step.

The reviewed input has 1,622 delivered forecasts. Scored coverage is 803/816 planned origins for participant 108 at 10 seconds, 799/816 at 30 seconds, 4/17 for participant 109 at 10 seconds, and 0/17 at 30 seconds. The macro MAE includes only people with scored outcomes; it retains the zero-coverage row and reports just one contributing person at 30 seconds. Macro RMSE and bias are arithmetic means of the corresponding participant metrics, rather than pooled-window statistics. The [public benchmark](public-data-benchmark.md) documents dependent windows, the losing adapter and limits on inference. This workflow does not validate Watch transfer, clinical decisions, readiness, reserve or failure prediction.

## Immutable batch and lineage

The [pinned manifest](../integrations/snowflake/pamap2-forecast-v1.manifest.json) binds 12 exact artifact/code files. `RUN_ID` is the SHA-256 of its canonical sorted JSON. `PAYLOAD_SHA256` binds the canonical import JSON. The payload preserves original CSV numeric strings and model/protocol/selection JSON text; numerical casts occur only when computing evaluation. It also retains dataset archive, protocol, model/selection, license, original run-source and artifact hashes. No raw PAMAP archive is needed for this import.

The fixed table is `SPOTTR_PUBLIC_PAMAP_FORECAST_RUNS` in an existing, explicitly configured database/schema. Each row contains the run ID, payload hash, a bounded VARIANT payload, and import timestamp. Its [table definition](../integrations/snowflake/001_public_pamap_forecast.sql) is review-only and is never run by the CLI. Any table creation needs separate operational approval.

Import first checks the ID/hash. An identical existing row skips the write. A missing row uses a fixed insert-only `MERGE`, followed by another ID/hash check. Matched rows are never updated. A conflicting hash, duplicate run ID or missing post-write row fails the workflow. Run this as a **single-writer operator job**: standard Snowflake tables do not enforce primary-key/unique constraints, so this is sequential replay idempotence plus duplicate detection, not a concurrent uniqueness guarantee. The workflow neither overwrites nor deletes duplicate/conflicting rows. [Snowflake constraints documentation](https://docs.snowflake.com/en/sql-reference/constraints)

The evaluation statement uses fixed `FLATTEN`/aggregate SQL over only the bound run. It cross-joins the three prespecified models with planned participant/horizon coverage so missing targets remain visible. All 18 returned metric rows must reconcile with the independently computed local trace/report metrics within `1e-8` bpm. A mismatch fails instead of returning a verified evaluation. SQL syntax and actual warehouse results still require a separately authorized live acceptance run.

## Later live acceptance

After explicit operator approval, an existing account/token, database, schema, warehouse and the precreated table are required. Required environment names are `SNOWFLAKE_ACCOUNT`, `SNOWFLAKE_TOKEN`, optional `SNOWFLAKE_TOKEN_TYPE`, `SNOWFLAKE_DATABASE`, `SNOWFLAKE_SCHEMA`, and `SNOWFLAKE_WAREHOUSE`. Context names must match Snowflake's existing identifier case. Store credentials only in the private local environment; do not put them in this directory or command arguments. The package dry-run command deliberately does not load `.env`.

```sh
node --env-file-if-exists=../.env src/snowflake-benchmark-cli.mjs --allow-live-public-data
```

Only that explicit flag enables live requests. It uploads the pinned derived public forecast artifact, not app data. Use an existing role with the required existing-resource USAGE and table SELECT/INSERT privileges; this workflow does not create or grant a role. Output contains public evaluation metrics and hashes, never authorization headers, tokens, provider bodies or database context names.

Requests use JSON `TEXT` bindings, fixed statements, the existing account/token header conventions, and redirects disabled. They never interpolate artifact values into SQL. See Snowflake's [SQL API bindings and request documentation](https://docs.snowflake.com/en/developer-guide/sql-api/submitting-requests).

Limits are 10,000 CSV rows, 1 MiB per input file/CSV, 2 MiB total input and SQL request, 256 KiB per HTTP response, a 60-second server statement timeout, 10-second HTTP deadlines, at most 10 polls across the workflow at up to one-second intervals, and a 90-second total budget including a reserved five-second cancellation request. The poll bound may cancel before the server timeout. Pending statements are polled by their validated handle; SQL submission is never automatically retried.

On timeout or poll failure, any known pending handle receives one cancellation request before returning an error. A failed/unconfirmed cancellation is reported as `cancel_unconfirmed`; the operator must inspect its status separately. If submission times out before a handle arrives, its execution status is unknown. Resolve that status through Snowflake query history, or wait through the configured 60-second statement timeout after the uncertain submission, before a manual rerun. No automatic resubmission occurs. [SQL API cancellation](https://docs.snowflake.com/en/developer-guide/sql-api/reference)

## Source and tests

The twelve new offline tests cover dry-run isolation, manifest/CSV/coverage rejection, exact-value lineage, fixed parameterized writes, sequential replay/conflict/duplicates, opt-in, asynchronous success, total/poll deadlines and cancellation, sanitized failure, and metric mismatch. Existing Snowflake connection-check tests continue to cover authentication, response bounds, HTTP timeout and error redaction. These are mocked-provider tests, not evidence of a live Snowflake execution.

Attribution: Reiss, A. (2012), *PAMAP2 Physical Activity Monitoring*, UCI Machine Learning Repository, [DOI 10.24432/C5NW2H](https://doi.org/10.24432/C5NW2H). [UCI declares CC BY 4.0](https://archive.ics.uci.edu/dataset/231/pamap2+physical+activity+monitoring). Features, fitted models, forecasts and analytics are derived modifications; source notices stay with the ignored original archive. No model is refitted by this integration.

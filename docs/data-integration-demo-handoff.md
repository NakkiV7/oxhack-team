# Local demo and provider activation handoff

The coordinating Spottr chat owns the native app, TestFlight preview and integration. PR #132 is merged; PR #144 supplies local HTTP/PostgreSQL acceptance, rejection of unsupported Snowflake personal databases, and this activation guide. Preview can use explicitly staged data without either provider. Keep preview data visibly identifiable as preview; do not label it as live Tiger sync or a completed Snowflake evaluation.

## Verified locally on 25 October 2026

The server suite passed **91/91 tests**. Embedded PostgreSQL executes the real gateway table definitions and ingestion/rollup queries; only Timescale extension/hypertable calls are omitted. A separate ephemeral loopback run used the existing private gateway token: unauthenticated 401, create 201, replay 200, changed-content conflict 409, foreign installation 403, readback/telemetry 200. Seven deduplicated scalar rows yielded five 5-second buckets; the artificial minute heart fixture had count 4, mean 4, min 1, max 7, with an empty gap. Its listener and database were closed afterward.

Repeat the committed checks from the repository root with Node 22.9 or later:

```sh
cd server
npm ci
npm test
npm run snowflake:benchmark
npm run snowflake:configuration
```

Tests and the benchmark dry run make no provider requests. The last command is also network-free, but exits 1 while required private configuration is missing or invalid. It checks syntax only. PGlite is a test dependency; `npm start` still requires Tiger for persisted workout sync. There is no production in-memory persistence fallback. Local tests do not establish provider access, native sync or device acceptance.

The benchmark dry run must retain **1,622 forecasts / 18 expected metric rows**, run ID `5b0bf1d168c094f5e45aa799e77a9723431e04d79b3c3b8bffe8d7e374865024`, and payload SHA-256 `d52c503e2face2f95d84e1784a894c71cb20bc4070e0400864e13bccbdc6e12d`. The fixed adaptive model's unfavorable results and zero-coverage rows remain intact. These public research artifacts are separate from staged app biometrics.

## Local app and gateway

Copy only needed settings from `.env.example` into a private, ignored environment file (mode 0600). The primary chat must set `SPOTTR_GATEWAY_TOKEN`, an accepted `TIGER_DATABASE_URL`, and `SPOTTR_INSTALLATION_ID` to the UUID actually displayed by the app. The last inspection found the installation ID absent. Never substitute the synthetic smoke installation for the app's owner.

Start the gateway with `cd server && npm start`. Its default address is `http://127.0.0.1:8787`. A health response reports configuration, not database authentication or successful persistence. The primary chat must verify the app's gateway URL reaches this Mac from the intended simulator or device and exercise explicit Sync, replay and readback with that app installation. A physical iPhone's loopback address refers to the phone itself; configure reachable local networking in the native demo lane. Preview should remain usable when no gateway is configured.

## Tiger: operator actions before enabling live sync

1. Obtain either a provider-authenticated certificate/trust correction for the original service, or authorized credentials for the existing teammate service. The original strict Node connection failed `SELF_SIGNED_CERT_IN_CHAIN` before SQL. Do not trust a certificate solely because the failing socket presented it, reuse the original password against another service, or disable chain/hostname verification.
2. Keep `sslmode=verify-full` and verify a bounded read-only connection succeeds. Inspect PostgreSQL/Timescale versions, TLS, the `spottr_gateway` tables, constraints, indexes and hypertable. The original gateway migration was accepted separately in the provider console; do not blindly reapply it. Any authenticated-console public-CA diagnostic must use existing file-read privileges and return public certificates only, with no grants or private-key reads.
3. If the selected database genuinely needs the gateway schema, review `server/migrations/001_workouts.sql` and use the existing explicit migration workflow only with approval for that target. Preserve existing data and policies.
4. With accepted private configuration, run **one** explicit synthetic acceptance:

   ```sh
   cd server
   npm run tiger:smoke -- --allow-live-synthetic
   ```

   This writes at most one immutable year-2000 snapshot/four scalar rows with fixed synthetic IDs, then checks replay/conflict/readback, gaps and 5/60-second rollups. It leaves those synthetic records in place. Record the sanitized result before enabling real app Sync.
5. Configure the actual app installation and test its local HTTP path against accepted Tiger storage. `createTigerStore().rollups(...)` is available to the coordinating chat; no rollup HTTP route or native chart integration was added here.

Full endpoint evidence and the prepared, unsent provider-support text are in [Tiger readiness](tiger-live-readiness.md).

## Snowflake: operator actions before the public import

The account lane confirmed the approved setup succeeded in the existing **standard** database `SNOWFLAKE_LEARNING_DB`: schema `SPOTTR_PUBLIC`, table `SPOTTR_PUBLIC_PAMAP_FORECAST_RUNS`, and role `SPOTTR_PUBLIC_FORECAST_IMPORTER` assigned to `OMAR`. A separate grant check confirmed only warehouse/database/schema USAGE and table SELECT/INSERT for that role. The warehouse is the existing X-Small `COMPUTE_WH`. No new warehouse, billing enrollment or administrator token is required. The account lane is handling the approved one-day restricted token; token availability and API authentication remain separate checks.

1. Inspect the account's existing trial/prepaid balance and billing state. The observed month-to-date usage is **not proof of remaining credits**. The user is unsure and explicitly accepts code/instructions plus preview if funding cannot be verified. **Hold the live import if existing funded credits cannot be established; do not buy credits or enable paid billing.** Preserve other workloads; the warehouse was already running during inspection.
2. Have the account owner supply the approved short-lived token privately. Set `SNOWFLAKE_ACCOUNT`, `SNOWFLAKE_TOKEN`, `SNOWFLAKE_TOKEN_TYPE=PROGRAMMATIC_ACCESS_TOKEN`, `SNOWFLAKE_WAREHOUSE=COMPUTE_WH`, `SNOWFLAKE_DATABASE=SNOWFLAKE_LEARNING_DB`, `SNOWFLAKE_SCHEMA=SPOTTR_PUBLIC`, and `SNOWFLAKE_ROLE=SPOTTR_PUBLIC_FORECAST_IMPORTER`. Never commit the token or put it in shell arguments, app configuration or screenshots. Replace it privately after expiry; do not silently broaden the role. `USER$...` personal databases are rejected before transport because they cannot store this table.
3. Run the network-free `npm run snowflake:configuration` against the private environment. Readiness does not establish credentials, privileges, table contents or credits. Verify the account setup receipt rather than rerunning CREATE/GRANT statements.
4. Only after configuration, access and existing funding are verified, run one bounded single-writer import:

   ```sh
   cd server
   node --env-file-if-exists=../.env src/snowflake-benchmark-cli.mjs --allow-live-public-data
   ```

   If the account lane supplied a separate private environment file, load it with Node's additional `--env-file` option before the script instead of copying its secret into source. The command uploads only the pinned derived public benchmark, uses the existing warehouse, and must reconcile all 18 metric rows within `1e-8` bpm. Retain the sanitized hashes/counts/result.
5. Do not automatically retry a failed submission. The importer has a 90-second total client budget, 60-second statement timeout, bounded polling and one cancellation request for a known pending handle. Resolve uncertain execution or unconfirmed cancellation through query history before any manual rerun. Existing equal-hash rows skip insertion; conflicting or duplicate rows fail and are not overwritten.

The full contract, fixed SQL and timeout semantics are in [Snowflake analytics](snowflake-analytics.md). No live SQL API import or metric reconciliation has passed in this lane. Keep that status explicit even when local checks and account setup pass.

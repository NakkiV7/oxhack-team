# Local Spottr integration gateway

Runnable Node gateway in `server/`, with Gemini REST coaching, a Tiger PostgreSQL/TimescaleDB session adapter and an explicit Snowflake SQL API connection-check command. Tests use mocked provider responses and a mocked PostgreSQL boundary; no paid provider request or database migration has been executed by the gateway implementation task. Configuration presence is separate from a verified connection. No deployment or CI/CD is included.

From the repository root, copy `.env.example` to `.env`, fill values privately, then:

```sh
cd server
npm ci
npm test
npm start
```

Use Node 22.9 or newer for `--env-file-if-exists` (current Node is suitable). Default origin is `http://127.0.0.1:8787`. `HOST` and `PORT` override binding. The server reads root `.env` through the start command; real environment values take precedence. Keep the filled `.env` out of Git. Configure the native app with the gateway URL and owner bearer token through its local developer settings; the Gemini and database keys stay on the server.

`GET /health` needs no authentication and performs no provider or database calls. It returns only readiness booleans (`configured`, `adapterImplemented`), plus `authenticationConfigured`; it never proves a connection. All `/v1/` routes require `Authorization: Bearer <SPOTTR_GATEWAY_TOKEN>`. This is a single-owner local gateway: `SPOTTR_INSTALLATION_ID` binds that owner token to one installation, and caller IDs cannot change the scope. For remote use, add TLS and a deliberate installation authentication/rate-limit design before exposing it publicly. Presage and Vultr currently have configuration placeholders only; this server is not evidence of using those services.

## Gemini

Set `GEMINI_API_KEY` and explicitly choose an account-enabled `GEMINI_MODEL`. `GEMINI_TIMEOUT_MS` defaults to 20000, with a permitted range of 1–60000. No automatic retries or fake fallback responses are performed. Each accepted user action sends at most one model request.

| Endpoint | Request | Response |
|---|---|---|
| `POST /v1/chat` | Common JSON below, nonempty `message` | `{generationID,text}` |
| `POST /v1/summary` | Common JSON, at least one fact; `kind` defaults to `session` | Raw `CoachSummary` JSON |
| `POST /v1/proposal` | Common JSON, at least one fact | Raw `WorkoutProposal` JSON |

```json
{
  "generationID": "unique-current-generation",
  "message": "Summarise this session",
  "history": [{"role": "user", "text": "Previous message"}],
  "facts": [{"id": "set-123", "text": "Recorded 8 squats manually."}],
  "availableSupport": ["Wall"],
  "kind": "session"
}
```

`generationID` is required, nonblank and at most 128 characters. Optional `message` is at most 4000 characters; history has at most 20 `user`/`model` turns of 4000 characters. Facts have unique IDs (128 characters), nonblank text (2000 characters), and at most 128 entries. Support has at most 16 nonblank entries of 100 characters. Only `session`/`weekly` kinds are accepted. Unknown fields are rejected. Incoming coach bodies and outgoing model text are capped at 64 KiB; the Google envelope is capped at 256 KiB. Personal facts are sent to Google only through an accepted coach request; summaries and proposals are not stored in Tiger by this server.

The gateway uses Google `generateContent` with a server key in the `x-goog-api-key` header. Structured requests use `generationConfig.responseFormat.text` with `mimeType: APPLICATION_JSON` and a request-specific JSON Schema. The gateway additionally validates matching generation, current fact references, unique evidence references, unknown fields, text length and all proposal bounds. It derives permitted exercise IDs, units and support from the current `Shared/Core/ExerciseCatalog.swift`; retain that file at the same relative location when packaging. A catalogue format change that cannot be read fails startup.

Defaults match `CoachContracts.swift`: at most 12 distinct exercises, 5 sets per exercise, 30 repetitions or 120 hold seconds per set, 600 rest seconds and 24 total sets. Summary insights are capped at three. Grounded text cites 1–16 supplied fact IDs and has at most 500 characters. These checks establish the wire contract and evidence membership, not factual entailment or clinical suitability. The app independently validates output and requires explicit proposal selection before changing its local plan.

Provider refusals, safety blocks, truncated responses and malformed results fail. Raw provider bodies, keys and request payloads are not logged. Health does not check model availability. A real account-enabled request, factual review, latency/token/cost measurement and app acceptance remain live validation work.

## Tiger

Set `TIGER_DATABASE_URL` using the provider's TLS connection string and set `SPOTTR_INSTALLATION_ID` to the persistent installation UUID displayed in the app's explicit Sync card. Use the provider's trusted certificate configuration; the gateway does not disable certificate verification. It creates no database resources on startup. Apply the migration explicitly once with:

```sh
npm run migrate
```

`server/migrations/001_workouts.sql` requires TimescaleDB with `create_hypertable`/`by_range` support (target ≥2.18). It creates the separate `spottr_gateway` schema, immutable session snapshots, and a scalar sample hypertable partitioned on `measured_at`, with that timestamp included in the primary key. It does not apply or depend on the earlier review-only `integrations/tiger/001_schema.sql` proposal. No retention, rollup policy or destructive cleanup is enabled. The migration has not been executed against a real database by this task.

| Endpoint | Input / scope | Response |
|---|---|---|
| `POST /v1/workouts` | `{installationID,record}` where `record` is native `SessionRecord` with ISO8601 dates, optional fractional seconds | First write: 201 `{workoutID,sha256,replayed:false}`; identical replay: 200 with `replayed:true`; changed content for the same ID: 409 |
| `GET /v1/workouts/{UUID}` | Server-bound installation only | `{installationID,record,sha256}` or 404 |
| `GET /v1/workouts/{UUID}/telemetry?from=ISO8601&to=ISO8601` | Required increasing half-open interval of at most 24 hours | `{workoutID,samples:[{measuredAt,sentAt,kind,value,unit,source}]}` |

Workout bodies are capped at 2 MiB, 120 total unique sets and 7200 telemetry envelopes. The gateway validates catalogue/unit relationships, tracked exercise IDs, source/reason enums, finite bounded measurements, ISO8601 dates and telemetry session ownership. Snapshot hashing sorts object keys recursively while preserving array order; property ordering does not affect replay. Snapshot and all observed samples commit in one transaction on one PostgreSQL connection. Failure rolls back, and all SQL values are parameterized. Native sensor measurement timestamps remain separate from Watch envelope time and database receipt time.

Only observed scalar values are inserted: `heartRate` in bpm (1–300), `accelerationMagnitude` in g, and `rotationMagnitude` in rad/s (both 0–1000). Watch scalar magnitudes are not raw three-axis vectors. Missing readings produce no scalar row and remain missing in the preserved snapshot; no interpolation or recovery inference is performed. Queries return at most the full session limit of 21600 scalar rows. Readback is currently developer tooling; this gateway does not merge remote records back into the native library.

PostgreSQL pool connection timeout is five seconds; each statement is limited to ten seconds. The adapter does not retry a failed transaction. An uncertain network result can be explicitly retried using the identical snapshot; the receipt hash prevents overwriting a committed different snapshot. Actual migration, ingest/replay/conflict, readback and measured latency on Tiger remain to be verified live.

## Snowflake connection check

Set `SNOWFLAKE_ACCOUNT` to the account identifier (without URL/suffix), `SNOWFLAKE_TOKEN` to a server token, and `SNOWFLAKE_TOKEN_TYPE` to `PROGRAMMATIC_ACCESS_TOKEN` (default), `KEYPAIR_JWT` or `OAUTH`. Optional `SNOWFLAKE_WAREHOUSE` supplies an existing warehouse. Then explicitly run:

```sh
npm run snowflake:check
```

This sends the single fixed statement `SELECT CURRENT_VERSION()` to the Snowflake SQL API. A completed response returns `{status:"ready",version}`; asynchronous HTTP 202 returns `{status:"pending",statementHandle}`. To check a pending result manually, run `npm run snowflake:check -- STATEMENT_HANDLE`; that performs one status GET. Each operation has a ten-second HTTP deadline and a 256 KiB envelope limit. There is no automatic polling or retry, generic SQL execution endpoint, telemetry export, warehouse provisioning or analytics pipeline. The adapter has mocked network tests; no live Snowflake request has been performed by this task.

## Errors

Errors have `{error:{code,message}}`. Main statuses: 400 malformed JSON; 401 bearer rejection; 403 installation mismatch; 404 missing route/workout; 405 method; 409 immutable-workout conflict; 413 body limit; 415 content type; 422 invalid input; 502 invalid/provider response; 503 missing configuration, provider throttling/unavailability or database unavailability; 504 Gemini timeout. Messages contain no raw provider or database errors. Request/response payloads and health values are never logged by the gateway.

Official references checked 24 October 2026: [Google generateContent](https://ai.google.dev/api/generate-content), [Google structured outputs](https://ai.google.dev/gemini-api/docs/generate-content/structured-output), [node-postgres pool transactions](https://node-postgres.com/apis/pool), [node-postgres TLS](https://node-postgres.com/features/ssl), [Tiger hypertable creation](https://www.tigerdata.com/docs/learn/hypertables/creating-and-configuring-hypertables), [Snowflake statement submission](https://docs.snowflake.com/en/developer-guide/sql-api/submitting-requests), [Snowflake SQL API reference](https://docs.snowflake.com/en/developer-guide/sql-api/reference).

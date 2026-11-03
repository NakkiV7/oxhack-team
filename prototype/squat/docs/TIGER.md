# Tiger Data: the live form stream

What the squat and push-up prototypes write to Tiger Data (PostgreSQL 18 + TimescaleDB 2.31), what they read back, and how it was verified. Shared code: [`prototype/shared/tiger-stream.mjs`](../../shared/tiger-stream.mjs) and the SQL in [`prototype/shared/db/`](../../shared/db/).

## Why a time-series database here

Every frame the browser analyses is a measurement: hip travel, depth, lean, knee tracking, balance (squat) or elbow angle, body line, hip offset (push-up), about 30 times a second. That stream is the raw material for the coach's fatigue judgement and for the next-rep prediction. Keeping it in the page loses it when the tab closes; keeping it in a hypertable makes it queryable across sessions, rolls it up as it arrives, and compresses it once a chunk closes.

## What is stored

| Table | One row per | Key columns |
|---|---|---|
| `spottr_cv.workout` | set started on a page | exercise, variation, source (camera or video), client, started_at, ended_at |
| `spottr_cv.frame` (hypertable, 5-minute chunks) | analysed frame | measured_at, workout_id, clock_ms, state, view, travel, depth, lean, knees, balance, elbow, body_line, hip_drop |
| `spottr_cv.rep` (hypertable, 1-day chunks) | rep or attempt | measured_at, rep_n, counted, good, secs, issue, faults, worst-frame values of the signals above |

Signals keep the units the pages show: travel and depth in leg or thigh lengths, angles in degrees, knees and balance as ratios. A signal the page does not judge (knees from a side view, elbow on a squat) is NULL, never zero.

## What is read back

Two continuous aggregates, both real time (a query adds the raw tail past the materialisation watermark, so the live set is always complete):

- `spottr_cv.frame_1s`: per workout per second, frame count and mean, max and min of every signal. Refreshed every 10 seconds. This is the line on the Tiger card: the squat waveform at 1 Hz, read from the database, not from the page.
- `spottr_cv.rep_1m`: per workout per minute, reps, good reps, attempts, mean and max rep duration, mean depth and lean, min elbow. Refreshed every 30 seconds. This is what the fatigue model and the coach will read.

Columnstore is on for `frame`, segmented by workout and ordered by time. A chunk is converted a minute after it closes; the card's **Compress now** button converts every closed chunk at once.

## How the pages use it

1. The page queues one record per analysed frame and one per rep, and posts them to its own server once a second (`POST /telemetry`, loopback only, at most 900 frames per batch).
2. The server validates the batch (`validateBatch`), writes it in at most four statements (`ingest`: workout row, one multi-row frame insert, one multi-row rep insert, end mark) and replies 204. Every row has a natural key, so a replayed batch changes nothing.
3. The Tiger card polls `GET /tiger?workout=<id>` every two seconds while a set runs: total rows, rows per second over the last ten seconds, columnstore ratio on compressed chunks, the timed per-second rollup query, and the series for the sparkline.

Without `TIGER_DATABASE_URL` nothing is sent and the card says so; counting, grading and the coach are unchanged.

## Setup

Put the team's connection string in `prototype/squat/.env` and `prototype/pushup/.env` (both gitignored) as `TIGER_DATABASE_URL`, with `sslmode=verify-full`. TLS is strict in both prototypes: chain and hostname verified against the system roots. The team's service presents a Google Trust Services certificate, so no private CA is involved. `TIGER_CA_CERT` can add an operator-verified root for a service that still has a private CA; nothing is ever learned from the server.

The schema and policies are applied on every server start (`migrate`, idempotent). Restart `npm run ui` after editing `.env`.

## Verification, 25 October 2026

- Strict connection: PostgreSQL 18.6, TimescaleDB 2.31.0, TLS 1.3, chain verified, 125 ms to connect, 11 ms round trip.
- Migration applied cleanly on first boot: two hypertables, two continuous aggregates, three policies (refresh every 10 s and 30 s, columnstore every 1 min).
- Synthetic three-squat workout through the server: 300 frames and 3 reps stored, a replayed batch added nothing, a malformed batch was rejected with 500, the workout row carried its end mark.
- Rollups: 11 per-second rows for the workout in 26.8 ms; the per-minute tempo row (3 reps, 2 good, mean 3.7 s, max 4.0 s) in 47.6 ms.
- Browser pass, both pages, tutorial clips replayed through the real MediaPipe pipeline: squat 1,266 frames and 6 reps over two workouts; push-up 6,083 frames and 24 counted reps over two workouts; 27 to 50 rows a second while a clip plays; the per-second rollup answered in 24 to 36 ms on the card; each **End workout** wrote the end mark.
- Columnstore: the first five-minute chunk was converted by the policy about a minute after it closed, 442 KB to 106 KB (75.9% saved). **Compress now** converted it on demand with no error. The ratio rises with chunk size, because a few thousand rows give the per-column codecs little to work with; the eight `real` columns are rounded to three decimals on the page for the same reason. Storing them as scaled integers would compress further if the headline number matters.
- Offline: 22 squat tests and 92 push-up tests pass with no network; the stream tests use a fake pool.

See [TEST_PLAN.md](TEST_PLAN.md) for the browser pass.

## Next

The heart-rate and tempo prediction for the HRT track reads `rep_1m` and `frame_1s` for its features and will write its predictions to a table of their own, so each actual rep scores the prediction made before it.

-- Continuous aggregates and columnstore for the frame stream. Each statement after a split marker runs on its own
-- because aggregates cannot be created inside a transaction. Idempotent.

-- Per-second rollup of the frame stream, per workout: the squat/push-up waveform at 1 Hz instead of 30 Hz.
-- Real time: a query adds the raw tail past the materialisation watermark, so the live set is always complete.
CREATE MATERIALIZED VIEW IF NOT EXISTS spottr_cv.frame_1s
WITH (timescaledb.continuous) AS
SELECT time_bucket(INTERVAL '1 second', measured_at) AS bucket, workout_id, exercise,
       count(*) AS frames,
       avg(travel) AS avg_travel, max(travel) AS max_travel,
       avg(depth) AS avg_depth, min(depth) AS min_depth,
       avg(lean) AS avg_lean, max(lean) AS max_lean,
       avg(knees) AS avg_knees, avg(balance) AS avg_balance,
       avg(elbow) AS avg_elbow, min(elbow) AS min_elbow,
       avg(body_line) AS avg_body_line, avg(hip_drop) AS avg_hip_drop
FROM spottr_cv.frame
GROUP BY 1, 2, 3
WITH NO DATA;
-- split
ALTER MATERIALIZED VIEW spottr_cv.frame_1s SET (timescaledb.materialized_only = false);
-- split
SELECT add_continuous_aggregate_policy('spottr_cv.frame_1s',
  start_offset => INTERVAL '1 hour', end_offset => INTERVAL '5 seconds',
  schedule_interval => INTERVAL '10 seconds', if_not_exists => TRUE);
-- split

-- Per-minute rep tempo and quality, per workout: what the coach and the fatigue model read.
CREATE MATERIALIZED VIEW IF NOT EXISTS spottr_cv.rep_1m
WITH (timescaledb.continuous) AS
SELECT time_bucket(INTERVAL '1 minute', measured_at) AS bucket, workout_id, exercise,
       count(*) FILTER (WHERE counted) AS reps,
       count(*) FILTER (WHERE counted AND good) AS good_reps,
       count(*) FILTER (WHERE NOT counted) AS attempts,
       avg(secs) FILTER (WHERE counted) AS avg_secs,
       max(secs) FILTER (WHERE counted) AS max_secs,
       avg(depth) FILTER (WHERE counted) AS avg_depth,
       avg(lean) FILTER (WHERE counted) AS avg_lean,
       min(elbow) FILTER (WHERE counted) AS min_elbow,
       avg(body_line) FILTER (WHERE counted) AS avg_body_line
FROM spottr_cv.rep
GROUP BY 1, 2, 3
WITH NO DATA;
-- split
ALTER MATERIALIZED VIEW spottr_cv.rep_1m SET (timescaledb.materialized_only = false);
-- split
SELECT add_continuous_aggregate_policy('spottr_cv.rep_1m',
  start_offset => INTERVAL '1 day', end_offset => INTERVAL '30 seconds',
  schedule_interval => INTERVAL '30 seconds', if_not_exists => TRUE);
-- split

-- Columnstore: a closed five-minute chunk of frames is converted a minute after it closes (segmented by workout, ordered
-- by time, which is where the 90%+ comes from). The page can also convert closed chunks on demand.
ALTER TABLE spottr_cv.frame SET (
  timescaledb.enable_columnstore = true,
  timescaledb.segmentby = 'workout_id',
  timescaledb.orderby = 'measured_at DESC'
);
-- split
CALL add_columnstore_policy('spottr_cv.frame', after => INTERVAL '1 minute',
  schedule_interval => INTERVAL '1 minute', if_not_exists => true);

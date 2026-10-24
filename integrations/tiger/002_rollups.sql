-- REVIEW-ONLY. Run only after schema/reference integrity and ingest replay checks.
CREATE MATERIALIZED VIEW spottr.heart_5s
WITH (timescaledb.continuous) AS
SELECT time_bucket(INTERVAL '5 seconds', measured_at) AS bucket,
       installation_id, workout_id, source,
       avg(bpm) AS mean_bpm, min(bpm) AS min_bpm, max(bpm) AS max_bpm,
       count(bpm) AS observed_samples, count(*) AS received_samples
FROM spottr.heart_sample
GROUP BY bucket, installation_id, workout_id, source
WITH NO DATA;
ALTER MATERIALIZED VIEW spottr.heart_5s SET (timescaledb.materialized_only = false);
SELECT add_continuous_aggregate_policy('spottr.heart_5s',
  start_offset => INTERVAL '7 days', end_offset => INTERVAL '10 seconds',
  schedule_interval => INTERVAL '10 seconds');

CREATE MATERIALIZED VIEW spottr.heart_1m
WITH (timescaledb.continuous) AS
SELECT time_bucket(INTERVAL '1 minute', measured_at) AS bucket,
       installation_id, workout_id, source,
       avg(bpm) AS mean_bpm, min(bpm) AS min_bpm, max(bpm) AS max_bpm,
       count(bpm) AS observed_samples, count(*) AS received_samples
FROM spottr.heart_sample
GROUP BY bucket, installation_id, workout_id, source
WITH NO DATA;
ALTER MATERIALIZED VIEW spottr.heart_1m SET (timescaledb.materialized_only = false);
SELECT add_continuous_aggregate_policy('spottr.heart_1m',
  start_offset => INTERVAL '7 days', end_offset => INTERVAL '1 minute',
  schedule_interval => INTERVAL '1 minute');

-- Columnstore starts outside the active refresh window (7 days).
ALTER TABLE spottr.heart_sample SET (
  timescaledb.enable_columnstore = true,
  timescaledb.segmentby = 'installation_id,workout_id',
  timescaledb.orderby = 'measured_at DESC'
);
CALL add_columnstore_policy('spottr.heart_sample', after => INTERVAL '8 days');
-- Retention is deliberately a separately gated operation. Read README before enabling.
-- SELECT add_retention_policy('spottr.heart_sample', drop_after => INTERVAL '30 days');
-- Apply reviewed columnstore/retention settings separately to other streams after
-- their feature rollups and late-arrival behavior are measured.

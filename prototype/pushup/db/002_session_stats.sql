-- Continuous aggregates cannot be created inside a transaction, so each chunk below (split on the marker
-- line) is sent as its own query by db.mjs.
CREATE MATERIALIZED VIEW IF NOT EXISTS pushup.session_stats
WITH (timescaledb.continuous) AS
SELECT
  time_bucket(INTERVAL '1 day', measured_at) AS day,
  user_id,
  session,
  source,
  count(*) AS reps,
  count(*) FILTER (WHERE label = 'good') AS good_reps,
  avg(elbow) FILTER (WHERE label = 'good') AS good_elbow,
  avg(body_line) FILTER (WHERE label = 'good') AS good_body_line,
  avg(seconds) AS avg_seconds
FROM pushup.rep
GROUP BY 1, 2, 3, 4
WITH NO DATA;
-- split
CALL refresh_continuous_aggregate('pushup.session_stats', NULL, NULL);

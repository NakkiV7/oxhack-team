-- 1. Daily Rollup View for Calendar Screen
-- Extracts structured daily summary stats from spottr_gateway.workout
CREATE OR REPLACE VIEW spottr_gateway.daily_workout_summary AS
SELECT
  w.installation_id,
  (w.record->>'date')::timestamptz::date AS workout_date,
  w.workout_id,
  w.received_at,
  jsonb_array_length(COALESCE(w.record->'sets', '[]'::jsonb)) AS tracked_sets_count,
  jsonb_array_length(COALESCE(w.record->'loggedSets', '[]'::jsonb)) AS logged_sets_count,
  (
    SELECT COALESCE(SUM((s->>'reps')::int), 0)
    FROM jsonb_array_elements(COALESCE(w.record->'sets', '[]'::jsonb)) AS s
  ) + (
    SELECT COALESCE(SUM((ls->>'reps')::int), 0)
    FROM jsonb_array_elements(COALESCE(w.record->'loggedSets', '[]'::jsonb)) AS ls
  ) AS total_reps,
  (
    SELECT COALESCE(SUM((s->>'activeSeconds')::double precision), 0)
    FROM jsonb_array_elements(COALESCE(w.record->'sets', '[]'::jsonb)) AS s
  ) AS total_active_seconds
FROM spottr_gateway.workout w;

-- 2. Set-Level Breakdown View for Statistics & Progression Charts
CREATE OR REPLACE VIEW spottr_gateway.set_progression AS
SELECT
  w.installation_id,
  w.workout_id,
  (w.record->>'date')::timestamptz AS session_date,
  (s->>'id')::uuid AS set_id,
  (s->>'exercise')::text AS exercise,
  (s->>'number')::int AS set_number,
  (s->>'reps')::int AS reps,
  (s->>'target')::int AS target,
  (s->>'activeSeconds')::double precision AS active_seconds,
  CASE
    WHEN (s->>'reps')::int > 0 THEN ((s->>'activeSeconds')::double precision / (s->>'reps')::int)
    ELSE NULL
  END AS cadence_seconds_per_rep,
  (s->>'reserve')::int AS reps_in_reserve,
  (s->>'restSecondsBefore')::double precision AS rest_seconds_before,
  s->>'reason' AS finish_reason,
  s->>'source' AS tracking_source
FROM spottr_gateway.workout w,
LATERAL jsonb_array_elements(COALESCE(w.record->'sets', '[]'::jsonb)) AS s;

-- 3. Daily Telemetry Aggregates View
-- High performance aggregation directly over scalar_sample hypertable
CREATE OR REPLACE VIEW spottr_gateway.daily_telemetry_rollup AS
SELECT
  installation_id,
  time_bucket('1 day', measured_at) AS day_bucket,
  AVG(value) FILTER (WHERE kind = 'heartRate') AS avg_heart_rate,
  MAX(value) FILTER (WHERE kind = 'heartRate') AS max_heart_rate,
  MIN(value) FILTER (WHERE kind = 'heartRate') AS min_heart_rate,
  AVG(value) FILTER (WHERE kind = 'accelerationMagnitude') AS avg_acceleration,
  COUNT(*) AS sample_count
FROM spottr_gateway.scalar_sample
GROUP BY installation_id, time_bucket('1 day', measured_at);

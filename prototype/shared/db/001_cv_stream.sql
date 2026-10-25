-- Live computer-vision stream from the squat and push-up prototypes. Idempotent: run on every server start.
BEGIN;
CREATE EXTENSION IF NOT EXISTS timescaledb;
CREATE SCHEMA IF NOT EXISTS spottr_cv;

CREATE TABLE IF NOT EXISTS spottr_cv.workout (
  workout_id uuid PRIMARY KEY,
  exercise text NOT NULL CHECK (exercise IN ('squat', 'pushup')),
  variation text NOT NULL,
  source text NOT NULL CHECK (source IN ('camera', 'video')),
  client text NOT NULL,
  started_at timestamptz NOT NULL,
  ended_at timestamptz CHECK (ended_at IS NULL OR ended_at >= started_at)
);

-- One row per analysed frame (about 30 a second). Signals are the counter's smoothed values in the units the pages show:
-- travel and depth in leg or thigh lengths, angles in degrees, knees and balance as ratios. NULL means not judged.
CREATE TABLE IF NOT EXISTS spottr_cv.frame (
  measured_at timestamptz NOT NULL,
  workout_id uuid NOT NULL,
  exercise text NOT NULL,
  clock_ms integer NOT NULL CHECK (clock_ms >= 0),
  state text NOT NULL,
  view text,
  travel real, depth real, lean real, knees real, balance real,
  elbow real, body_line real, hip_drop real,
  received_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (measured_at, workout_id)
);
SELECT create_hypertable('spottr_cv.frame', by_range('measured_at', INTERVAL '5 minutes'), if_not_exists => TRUE);
CREATE INDEX IF NOT EXISTS frame_workout ON spottr_cv.frame (workout_id, measured_at DESC);

-- One row per rep or attempt, at the moment it finished. Worst-frame values of the signals above.
CREATE TABLE IF NOT EXISTS spottr_cv.rep (
  measured_at timestamptz NOT NULL,
  workout_id uuid NOT NULL,
  exercise text NOT NULL,
  rep_n integer NOT NULL CHECK (rep_n >= 0),
  counted boolean NOT NULL,
  good boolean NOT NULL,
  secs real CHECK (secs IS NULL OR secs BETWEEN 0 AND 600),
  issue text,
  faults text[] NOT NULL DEFAULT '{}',
  travel real, depth real, lean real, knees real, balance real,
  elbow real, body_line real, hip_drop real,
  received_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (measured_at, workout_id, rep_n)
);
SELECT create_hypertable('spottr_cv.rep', by_range('measured_at', INTERVAL '1 day'), if_not_exists => TRUE);
CREATE INDEX IF NOT EXISTS rep_workout ON spottr_cv.rep (workout_id, measured_at DESC);
COMMIT;

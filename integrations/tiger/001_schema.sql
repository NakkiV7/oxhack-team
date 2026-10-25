-- REVIEW-ONLY proposal. Not deployed or executed. Target TimescaleDB >=2.18.
-- Seed exercise_catalog from ExerciseCatalog.all at the selected catalogue version.
CREATE EXTENSION IF NOT EXISTS timescaledb;
CREATE SCHEMA IF NOT EXISTS spottr;

CREATE TABLE spottr.exercise_catalog (
  exercise_id text NOT NULL,
  catalog_version integer NOT NULL CHECK (catalog_version > 0),
  name text NOT NULL,
  family text NOT NULL,
  target_unit text NOT NULL CHECK (target_unit IN ('reps', 'seconds')),
  required_support text,
  PRIMARY KEY (exercise_id, catalog_version)
);
CREATE TABLE spottr.workout (
  workout_id uuid PRIMARY KEY,
  installation_id uuid NOT NULL,
  started_at timestamptz NOT NULL,
  ended_at timestamptz,
  calendar_timezone text NOT NULL,
  CHECK (ended_at IS NULL OR ended_at >= started_at)
);
CREATE TABLE spottr.workout_set (
  set_id uuid PRIMARY KEY,
  workout_id uuid NOT NULL REFERENCES spottr.workout,
  exercise_id text NOT NULL,
  catalog_version integer NOT NULL,
  ordinal integer NOT NULL CHECK (ordinal >= 0),
  measured_at timestamptz NOT NULL,
  reps integer NOT NULL CHECK (reps BETWEEN 0 AND 200),
  hold_seconds double precision NOT NULL CHECK (hold_seconds BETWEEN 0 AND 600),
  target_unit text NOT NULL CHECK (target_unit IN ('reps', 'seconds')),
  source text NOT NULL CHECK (source IN ('manual', 'camera', 'imported_video')),
  stop_reason text NOT NULL,
  reserve_reps integer CHECK (reserve_reps BETWEEN 0 AND 20),
  asset_fingerprint text,
  FOREIGN KEY (exercise_id, catalog_version) REFERENCES spottr.exercise_catalog,
  UNIQUE (workout_id, ordinal),
  CHECK ((target_unit = 'reps' AND hold_seconds = 0) OR (target_unit = 'seconds' AND reps = 0))
);
CREATE TABLE spottr.ingest_receipt (
  installation_id uuid NOT NULL,
  batch_id uuid NOT NULL,
  payload_sha256 text NOT NULL CHECK (payload_sha256 ~ '^[0-9a-f]{64}$'),
  received_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  accepted_rows integer NOT NULL CHECK (accepted_rows BETWEEN 0 AND 500),
  PRIMARY KEY (installation_id, batch_id)
);

CREATE TABLE spottr.heart_sample (
  measured_at timestamptz NOT NULL,
  received_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  event_id uuid NOT NULL,
  installation_id uuid NOT NULL,
  workout_id uuid NOT NULL,
  set_id uuid,
  device_id text NOT NULL,
  source text NOT NULL,
  quality double precision CHECK (quality BETWEEN 0 AND 1),
  missing_reason text,
  model_version text NOT NULL,
  policy_version text NOT NULL,
  bpm double precision CHECK (bpm BETWEEN 1 AND 300),
  CHECK ((bpm IS NULL) = (missing_reason IS NOT NULL)),
  PRIMARY KEY (measured_at, installation_id, event_id)
);
SELECT create_hypertable('spottr.heart_sample', by_range('measured_at', INTERVAL '1 day'));
CREATE INDEX ON spottr.heart_sample (installation_id, workout_id, measured_at DESC);

CREATE TABLE spottr.motion_sample (
  measured_at timestamptz NOT NULL,
  received_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  event_id uuid NOT NULL,
  installation_id uuid NOT NULL,
  workout_id uuid NOT NULL,
  set_id uuid,
  device_id text NOT NULL,
  source text NOT NULL,
  quality double precision CHECK (quality BETWEEN 0 AND 1),
  missing_reason text,
  model_version text NOT NULL,
  policy_version text NOT NULL,
  acceleration_g double precision[],
  rotation_rad_s double precision[],
  CHECK (cardinality(acceleration_g) = 3),
  CHECK (cardinality(rotation_rad_s) = 3),
  CHECK (missing_reason IS NOT NULL OR (acceleration_g IS NOT NULL AND rotation_rad_s IS NOT NULL)),
  PRIMARY KEY (measured_at, installation_id, event_id)
);
SELECT create_hypertable('spottr.motion_sample', by_range('measured_at', INTERVAL '1 day'));
CREATE INDEX ON spottr.motion_sample (installation_id, workout_id, measured_at DESC);

CREATE TABLE spottr.pose_sample (
  measured_at timestamptz NOT NULL,
  received_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  event_id uuid NOT NULL,
  installation_id uuid NOT NULL,
  workout_id uuid NOT NULL,
  set_id uuid,
  device_id text NOT NULL,
  source text NOT NULL,
  quality double precision CHECK (quality BETWEEN 0 AND 1),
  missing_reason text,
  model_version text NOT NULL,
  policy_version text NOT NULL,
  capture_id uuid NOT NULL,
  landmarks_normalized jsonb,
  CHECK (landmarks_normalized IS NULL OR jsonb_typeof(landmarks_normalized) = 'array'),
  CHECK (missing_reason IS NOT NULL OR landmarks_normalized IS NOT NULL),
  PRIMARY KEY (measured_at, installation_id, event_id)
);
SELECT create_hypertable('spottr.pose_sample', by_range('measured_at', INTERVAL '1 day'));
CREATE INDEX ON spottr.pose_sample (installation_id, workout_id, measured_at DESC);

CREATE TABLE spottr.rep_event (
  measured_at timestamptz NOT NULL,
  received_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  event_id uuid NOT NULL,
  installation_id uuid NOT NULL,
  workout_id uuid NOT NULL,
  set_id uuid,
  device_id text NOT NULL,
  source text NOT NULL,
  quality double precision CHECK (quality BETWEEN 0 AND 1),
  missing_reason text,
  model_version text NOT NULL,
  policy_version text NOT NULL,
  rep_index integer NOT NULL CHECK (rep_index > 0),
  eccentric_seconds double precision CHECK (eccentric_seconds BETWEEN 0 AND 600),
  concentric_seconds double precision CHECK (concentric_seconds BETWEEN 0 AND 600),
  PRIMARY KEY (measured_at, installation_id, event_id)
);
SELECT create_hypertable('spottr.rep_event', by_range('measured_at', INTERVAL '1 day'));
CREATE INDEX ON spottr.rep_event (installation_id, workout_id, measured_at DESC);

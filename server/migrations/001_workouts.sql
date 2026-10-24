BEGIN;
CREATE EXTENSION IF NOT EXISTS timescaledb;
CREATE SCHEMA IF NOT EXISTS spottr_gateway;

CREATE TABLE IF NOT EXISTS spottr_gateway.workout (
  installation_id uuid NOT NULL,
  workout_id uuid NOT NULL,
  payload_sha256 text NOT NULL CHECK (payload_sha256 ~ '^[0-9a-f]{64}$'),
  record jsonb NOT NULL CHECK (jsonb_typeof(record) = 'object'),
  received_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (installation_id, workout_id)
);

CREATE TABLE IF NOT EXISTS spottr_gateway.scalar_sample (
  measured_at timestamptz NOT NULL,
  received_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  sent_at timestamptz NOT NULL,
  installation_id uuid NOT NULL,
  workout_id uuid NOT NULL,
  sample_index integer NOT NULL CHECK (sample_index BETWEEN 0 AND 7199),
  kind text NOT NULL,
  value double precision NOT NULL,
  unit text NOT NULL,
  source text NOT NULL CHECK (source = 'apple_watch'),
  CHECK ((kind = 'heartRate' AND unit = 'bpm' AND value BETWEEN 1 AND 300)
      OR (kind = 'accelerationMagnitude' AND unit = 'g' AND value BETWEEN 0 AND 1000)
      OR (kind = 'rotationMagnitude' AND unit = 'rad/s' AND value BETWEEN 0 AND 1000)),
  PRIMARY KEY (measured_at, installation_id, workout_id, sample_index, kind)
);

SELECT create_hypertable('spottr_gateway.scalar_sample', by_range('measured_at', INTERVAL '1 day'), if_not_exists => TRUE);
CREATE INDEX IF NOT EXISTS scalar_sample_workout_time ON spottr_gateway.scalar_sample (installation_id, workout_id, measured_at);
COMMIT;

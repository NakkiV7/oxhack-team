BEGIN;
CREATE EXTENSION IF NOT EXISTS timescaledb;
CREATE SCHEMA IF NOT EXISTS pushup;

-- One row per rep. `source` keeps mock rows (generated CSV) apart from real camera sessions, so reported
-- numbers can be filtered to real data only.
CREATE TABLE IF NOT EXISTS pushup.rep (
  measured_at timestamptz NOT NULL,
  user_id text NOT NULL,
  session integer NOT NULL,
  rep integer NOT NULL,
  elbow double precision NOT NULL CHECK (elbow BETWEEN 0 AND 180),
  body_line double precision NOT NULL CHECK (body_line BETWEEN 0 AND 180),
  seconds double precision CHECK (seconds IS NULL OR seconds >= 0),
  counted boolean NOT NULL,
  label text NOT NULL CHECK (label IN ('good', 'shallow', 'sagging', 'fatigued')),
  source text NOT NULL CHECK (source IN ('mock', 'real')),
  PRIMARY KEY (measured_at, user_id, session, rep)
);

SELECT create_hypertable('pushup.rep', by_range('measured_at', INTERVAL '7 days'), if_not_exists => TRUE);
CREATE INDEX IF NOT EXISTS rep_user_session ON pushup.rep (user_id, session, rep);
COMMIT;

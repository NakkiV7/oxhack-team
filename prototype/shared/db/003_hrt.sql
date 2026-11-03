-- Forecast records for the tempo prediction (HRT). Additive only. Forecasts are immutable; outcomes are added later and
-- point at the forecast. Idempotent.
BEGIN;
ALTER TABLE spottr_cv.rep ADD COLUMN IF NOT EXISTS down_secs real, ADD COLUMN IF NOT EXISTS up_secs real; -- lowering and rising phase
ALTER TABLE spottr_cv.workout ADD COLUMN IF NOT EXISTS note text;                                         -- e.g. the replayed file name

CREATE TABLE IF NOT EXISTS spottr_cv.model_run (
  model_run text PRIMARY KEY,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  git_commit text,
  dataset_sha256 text,
  label_version text NOT NULL,
  feature_version text NOT NULL,
  policy_version text NOT NULL,
  hyperparameters jsonb NOT NULL,
  metrics jsonb,
  artifact jsonb NOT NULL,
  status text NOT NULL
);

CREATE TABLE IF NOT EXISTS spottr_cv.prediction (
  prediction_id uuid PRIMARY KEY,
  workout_id uuid NOT NULL,
  exercise text NOT NULL,
  rep_n integer NOT NULL CHECK (rep_n > 0),           -- the origin: forecast made after this counted rep
  model_run text NOT NULL,
  target_id text NOT NULL,
  label_version text NOT NULL,
  feature_version text NOT NULL,
  policy_version text NOT NULL,
  horizon integer NOT NULL CHECK (horizon > 0),
  cutoff_at timestamptz NOT NULL,                      -- no information after this instant was used
  emitted_at timestamptz NOT NULL,
  received_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  features jsonb NOT NULL,
  probability real NOT NULL CHECK (probability BETWEEN 0 AND 1),
  threshold real,
  action text NOT NULL CHECK (action IN ('cue', 'silent', 'suppressed')),
  suppressed_reason text,
  delivered_at timestamptz,
  latency_ms real,
  mode text NOT NULL CHECK (mode IN ('shadow', 'coaching')),
  provenance text NOT NULL CHECK (provenance IN ('live', 'video', 'synthetic')),
  UNIQUE (workout_id, rep_n, model_run)
);
CREATE INDEX IF NOT EXISTS prediction_workout ON spottr_cv.prediction (workout_id, rep_n);

CREATE TABLE IF NOT EXISTS spottr_cv.prediction_outcome (
  prediction_id uuid PRIMARY KEY REFERENCES spottr_cv.prediction,
  label_version text NOT NULL,
  state text NOT NULL CHECK (state IN ('observed', 'excluded')),
  outcome smallint CHECK (outcome IN (0, 1)),
  exclusion_reason text,
  onset_offset smallint,
  lead_secs real,
  future_reps jsonb NOT NULL,
  observed_at timestamptz NOT NULL,
  received_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  coached boolean NOT NULL DEFAULT false,              -- a cue was delivered before this outcome
  CHECK ((state = 'observed') = (outcome IS NOT NULL))
);
COMMIT;

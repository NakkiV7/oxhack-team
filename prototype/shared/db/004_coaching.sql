-- Connected coaching journey: profile, programme, node progress, coaching attempts, session and weekly reports, research
-- sources. Additive to the existing spottr_cv stream; workouts, reps, frames, predictions and outcomes stay where they are
-- and are referenced by id. Idempotent.
BEGIN;
CREATE TABLE IF NOT EXISTS spottr_cv.profile (
  user_id text PRIMARY KEY,
  timezone text NOT NULL DEFAULT 'Europe/London',
  survey jsonb NOT NULL DEFAULT '{}',            -- goal, ability, equipment, minutes, days per week, coaching style, limitations
  goals jsonb NOT NULL DEFAULT '[]',             -- accepted goals: [{ id, text, kind, exerciseId, target, acceptedAt, source }]
  preferences jsonb NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE IF NOT EXISTS spottr_cv.programme (
  programme_id uuid PRIMARY KEY,
  user_id text NOT NULL REFERENCES spottr_cv.profile,
  version integer NOT NULL CHECK (version > 0),
  goal text NOT NULL,
  catalog_version integer NOT NULL,
  graph jsonb NOT NULL,                          -- { nodes: [{ id, exerciseId, title, why, instructions, assessable, prerequisites, optional }], start, goalNode }
  rationale jsonb NOT NULL,                      -- Gemini rationale with fact ids, or the catalogue fallback marker
  provenance text NOT NULL CHECK (provenance IN ('gemini', 'catalogue-fallback')),
  status text NOT NULL CHECK (status IN ('active', 'superseded')),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (user_id, version)
);

CREATE TABLE IF NOT EXISTS spottr_cv.node_progress (
  programme_id uuid NOT NULL REFERENCES spottr_cv.programme,
  node_id text NOT NULL,
  user_id text NOT NULL REFERENCES spottr_cv.profile,
  availability text NOT NULL CHECK (availability IN ('locked', 'available', 'current', 'not_required')),
  practice_count integer NOT NULL DEFAULT 0,
  practice_workouts jsonb NOT NULL DEFAULT '[]',  -- workout ids already counted as practice, so a repeated log adds nothing
  verification text NOT NULL DEFAULT 'none' CHECK (verification IN ('none', 'first_completion', 'consistent')),
  evidence jsonb NOT NULL DEFAULT '[]',          -- [{ attemptId, workoutId, at, kind }] exact qualifying evidence
  criteria_version text,
  xp integer NOT NULL DEFAULT 0,
  badges jsonb NOT NULL DEFAULT '[]',
  completed_at timestamptz,
  verified_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (programme_id, node_id)
);

-- One coach -> retry -> verify loop. The target and rule are frozen before the retry; the outcome is calculated by the
-- application; Gemini's cue and explanation are stored apart from it. Written once per state transition, keyed by id.
CREATE TABLE IF NOT EXISTS spottr_cv.coaching_attempt (
  attempt_id uuid PRIMARY KEY,
  user_id text NOT NULL REFERENCES spottr_cv.profile,
  workout_id uuid NOT NULL,
  programme_id uuid REFERENCES spottr_cv.programme,
  node_id text,
  exercise text NOT NULL,
  variation text NOT NULL,
  contract_version text NOT NULL,
  status text NOT NULL CHECK (status IN ('setup', 'baseline', 'preparing_cue', 'cue_ready', 'ready_to_retry', 'retry', 'verifying', 'result', 'paused', 'cancelled')),
  target jsonb,                                  -- frozen: { metric, value, unit, tolerance, rule, targetId }
  baseline_reps jsonb NOT NULL DEFAULT '[]',     -- [{ repN, at, down, up, secs, depth, valid, reason }]
  retry_reps jsonb NOT NULL DEFAULT '[]',
  cue jsonb,                                     -- { action, text, rationale, evidenceIds, provenance: 'gemini'|'deterministic'|'unavailable', generationId }
  outcome jsonb,                                 -- calculated: { classification, baselineError, retryError, tolerance, comparableRange, ... }
  explanation jsonb,                             -- Gemini: { text, nextAction, factIds, generationId } or null
  interventions jsonb NOT NULL DEFAULT '[]',     -- HRT cues delivered during baseline/retry, if any
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX IF NOT EXISTS coaching_attempt_user ON spottr_cv.coaching_attempt (user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS spottr_cv.session_report (
  workout_id uuid PRIMARY KEY,
  user_id text NOT NULL REFERENCES spottr_cv.profile,
  version text NOT NULL,
  facts jsonb NOT NULL,                          -- calculated by the application
  timeline jsonb NOT NULL,
  narrative jsonb,                               -- Gemini: { headline, insights: [{ text, factIds }], generationId } or null
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE IF NOT EXISTS spottr_cv.weekly_report (
  report_id uuid PRIMARY KEY,
  user_id text NOT NULL REFERENCES spottr_cv.profile,
  period_start date NOT NULL,
  period_end date NOT NULL,                      -- exclusive
  comparison_start date,
  timezone text NOT NULL,
  cutoff_at timestamptz NOT NULL,
  input_fingerprint text NOT NULL,
  status text NOT NULL CHECK (status IN ('pending', 'generating', 'ready', 'failed', 'stale')),
  version integer NOT NULL DEFAULT 1,
  facts jsonb,
  narrative jsonb,
  proposed_goals jsonb,
  research_refs jsonb NOT NULL DEFAULT '[]',
  model_version text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (user_id, period_start, input_fingerprint, version)
);

CREATE TABLE IF NOT EXISTS spottr_cv.research_source (
  source_id text PRIMARY KEY,                    -- sha256 of the document, or 'web:' + sha256 of the url
  owner text NOT NULL,                           -- user id or 'shared'
  origin text NOT NULL CHECK (origin IN ('discovered', 'supplied')),
  title text NOT NULL,
  authors text,
  year integer,
  url text,
  doi text,
  access text NOT NULL CHECK (access IN ('full_text', 'abstract', 'metadata')),
  content_hash text,
  findings jsonb NOT NULL,                       -- { question, design, population, intervention, outcomes, mainFindings, limitations, relevance, evidence: [{ page, quote }] }
  grounding jsonb,                               -- search grounding metadata, when discovered
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
COMMIT;

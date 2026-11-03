-- Path redesign: practice log with timestamps (one reward per step per day) so practice can be measured over time.
-- Additive and idempotent.
BEGIN;
ALTER TABLE spottr_cv.node_progress ADD COLUMN IF NOT EXISTS practice_log jsonb NOT NULL DEFAULT '[]';  -- [{ key, at }]
COMMIT;

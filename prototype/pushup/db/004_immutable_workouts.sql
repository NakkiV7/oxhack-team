BEGIN;
-- Existing rows retain their original identity and provenance; only new explicit uploads get a receipt.
ALTER TABLE pushup.rep ADD COLUMN IF NOT EXISTS workout_id uuid;
CREATE TABLE IF NOT EXISTS pushup.workout_receipt (
  user_id text NOT NULL,
  workout_id uuid NOT NULL,
  content_hash text NOT NULL CHECK (content_hash ~ '^[0-9a-f]{64}$'),
  rep_count integer NOT NULL CHECK (rep_count BETWEEN 1 AND 500),
  PRIMARY KEY (user_id, workout_id)
);
COMMIT;

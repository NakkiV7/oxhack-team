-- Bind all parameters in the gateway. IDs below are server-scoped installation IDs.
-- Real-time aggregate combines materialization with its actual raw tail watermark.
SELECT bucket, mean_bpm, min_bpm, max_bpm, observed_samples, received_samples, source
FROM spottr.heart_5s
WHERE installation_id = $1 AND workout_id = $2
ORDER BY bucket;

-- Preserve timestamps and gaps. No interpolation or latest-value carry-forward.
SELECT measured_at, received_at, bpm, quality, missing_reason, source
FROM spottr.heart_sample
WHERE installation_id = $1 AND workout_id = $2
  AND measured_at >= $3 AND measured_at < $4
ORDER BY measured_at;

-- Weekly exposure: supply explicit [start,end) instants derived from the user's
-- calendar/timezone. A partial week must be labelled by the client.
SELECT s.exercise_id, s.catalog_version, count(*) AS recorded_sets,
       sum(s.reps) AS reps, sum(s.hold_seconds) AS hold_seconds, s.source
FROM spottr.workout_set s JOIN spottr.workout w USING (workout_id)
WHERE w.installation_id = $1 AND s.measured_at >= $2 AND s.measured_at < $3
GROUP BY s.exercise_id, s.catalog_version, s.source;

-- Claim a stable batch key in the SAME transaction as all its sample inserts.
-- Zero returned rows: read stored hash; equal = replay, different = HTTP 409.
INSERT INTO spottr.ingest_receipt(installation_id, batch_id, payload_sha256, accepted_rows)
VALUES ($1, $2, $3, $4)
ON CONFLICT (installation_id, batch_id) DO NOTHING
RETURNING batch_id;

-- Retry event insert: preserve original event ID AND measured_at on every retry.
INSERT INTO spottr.heart_sample(measured_at, event_id, installation_id, workout_id,
  device_id, source, model_version, policy_version, bpm)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
ON CONFLICT (measured_at, installation_id, event_id) DO NOTHING;

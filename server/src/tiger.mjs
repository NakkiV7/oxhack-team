import { createHash } from 'node:crypto';
import { GatewayError } from './errors.mjs';
import { workoutRequest, workoutIDContract, telemetryQuery } from './tiger-contracts.mjs';

function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (value !== null && typeof value === 'object') return Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])]));
  return value;
}

function scalarSamples(record) {
  const metrics = [['heartRate', 'heartRate', 'bpm'], ['accelerationG', 'accelerationMagnitude', 'g'], ['rotationRadiansPerSecond', 'rotationMagnitude', 'rad/s']];
  const samples = (record.telemetry ?? []).flatMap((sample, sampleIndex) => metrics.filter(([field]) => sample[field] != null).map(([field, kind, unit]) => ({
    measured_at: sample[field].date, sent_at: sample.sentAt, sample_index: sampleIndex,
    kind, value: sample[field].value, unit, source: 'apple_watch'
  })));
  const observations = Map.groupBy(samples, sample => `${sample.kind}:${Date.parse(sample.measured_at)}`);
  return Array.from(observations.values(), group => group[0]);
}

export function createTigerStore({ pool, installationID }) {
  const owner = installationID.toLowerCase();
  const read = async workoutID => {
    if (!workoutIDContract.safeParse(workoutID).success) throw new GatewayError(422, 'invalid_request', 'A valid workout UUID is required.');
    const result = await pool.query('SELECT record, payload_sha256 FROM spottr_gateway.workout WHERE installation_id = $1 AND workout_id = $2', [owner, workoutID.toLowerCase()]);
    if (!result.rows[0]) throw new GatewayError(404, 'not_found', 'Workout not found.');
    return { installationID: owner, record: result.rows[0].record, sha256: result.rows[0].payload_sha256 };
  };
  return {
    async ingest(input) {
      const parsed = workoutRequest.safeParse(input);
      if (!parsed.success) throw new GatewayError(422, 'invalid_request', 'The session record is invalid or exceeds limits.');
      if (parsed.data.installationID.toLowerCase() !== owner) throw new GatewayError(403, 'installation_mismatch', 'Installation does not match the configured gateway owner.');
      const record = parsed.data.record;
      const workoutID = record.id.toLowerCase();
      const sha256 = createHash('sha256').update(JSON.stringify(canonical(record))).digest('hex');
      const client = await pool.connect();
      let discardError;
      try {
        await client.query('BEGIN');
        const inserted = await client.query('INSERT INTO spottr_gateway.workout (installation_id, workout_id, payload_sha256, record) VALUES ($1, $2, $3, $4::jsonb) ON CONFLICT (installation_id, workout_id) DO NOTHING RETURNING workout_id', [owner, workoutID, sha256, JSON.stringify(record)]);
        if (!inserted.rows.length) {
          const existing = await client.query('SELECT payload_sha256 FROM spottr_gateway.workout WHERE installation_id = $1 AND workout_id = $2', [owner, workoutID]);
          if (existing.rows[0]?.payload_sha256 !== sha256) throw new GatewayError(409, 'workout_conflict', 'This workout already exists with different content.');
          await client.query('COMMIT');
          return { workoutID, sha256, replayed: true };
        }
        const samples = scalarSamples(record);
        if (samples.length) await client.query(`INSERT INTO spottr_gateway.scalar_sample (installation_id, workout_id, measured_at, sent_at, sample_index, kind, value, unit, source)
          SELECT $2::uuid, $3::uuid, s.measured_at, s.sent_at, s.sample_index, s.kind, s.value, s.unit, s.source
          FROM jsonb_to_recordset($1::jsonb) AS s(measured_at timestamptz, sent_at timestamptz, sample_index integer, kind text, value double precision, unit text, source text)`, [JSON.stringify(samples), owner, workoutID]);
        await client.query('COMMIT');
        return { workoutID, sha256, replayed: false };
      } catch (error) {
        try { await client.query('ROLLBACK'); } catch (rollbackError) { discardError = rollbackError; }
        throw error;
      } finally { client.release(discardError); }
    },
    read,
    async telemetry(input) {
      const parsed = telemetryQuery.safeParse(input);
      if (!parsed.success) throw new GatewayError(422, 'invalid_request', 'Telemetry requires a workout UUID and an increasing ISO8601 interval of at most 24 hours.');
      const { workoutID, from, to } = parsed.data;
      await read(workoutID);
      const result = await pool.query(`SELECT measured_at AS "measuredAt", sent_at AS "sentAt", kind, value, unit, source
        FROM spottr_gateway.scalar_sample WHERE installation_id = $1 AND workout_id = $2 AND measured_at >= $3 AND measured_at < $4
        ORDER BY measured_at, sample_index, kind LIMIT 21600`, [owner, workoutID.toLowerCase(), from, to]);
      return { workoutID: workoutID.toLowerCase(), samples: result.rows };
    },
    async calendar({ year, month } = {}) {
      const y = Number(year) || new Date().getFullYear();
      const m = Number(month) || (new Date().getMonth() + 1);
      const start = new Date(Date.UTC(y, m - 1, 1)).toISOString();
      const end = new Date(Date.UTC(y, m, 1)).toISOString();
      const result = await pool.query(
        `SELECT workout_date::text AS date, workout_id AS "workoutID", total_reps AS "totalReps",
                total_active_seconds AS "activeSeconds", tracked_sets_count AS "setsCount"
         FROM spottr_gateway.daily_workout_summary
         WHERE installation_id = $1 AND workout_date >= $2::date AND workout_date < $3::date
         ORDER BY workout_date ASC`,
        [owner, start, end]
      );
      return { year: y, month: m, days: result.rows };
    },
    async statistics({ days = 30, exercise = 'all' } = {}) {
      const dayWindow = Math.min(Math.max(Number(days) || 30, 1), 365);
      const params = [owner, `${dayWindow} days`];
      let exerciseClause = '';
      if (exercise && exercise !== 'all') {
        params.push(exercise);
        exerciseClause = 'AND exercise = $3';
      }
      const result = await pool.query(
        `SELECT session_date::date::text AS date, exercise,
                SUM(reps)::int AS reps,
                ROUND(AVG(cadence_seconds_per_rep)::numeric, 2) AS avg_cadence,
                ROUND(AVG(reps_in_reserve)::numeric, 1) AS avg_reserve
         FROM spottr_gateway.set_progression
         WHERE installation_id = $1 AND session_date >= (now() - $2::interval) ${exerciseClause}
         GROUP BY session_date::date, exercise
         ORDER BY session_date::date ASC`,
        params
      );
      return { rangeDays: dayWindow, series: result.rows };
    }
  };
}

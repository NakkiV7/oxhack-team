import { createHash } from 'node:crypto';

export const MAX_SYNC_REPS = 500;

// Same cues the app shows, mapped to the labels allowed in pushup.rep. These come from the app's own rules, not
// from a person, so a tree trained on them mostly learns those rules back (see ALGORITHM.md).
export function labelOf(rep) {
  if (!rep.counted) return 'shallow';
  if (rep.good) return 'good';
  const issue = String(rep.issue ?? '');
  if (/sagging/i.test(issue)) return 'sagging';
  if (/too high/i.test(issue)) return 'piking';
  return 'other';
}

const num = (v, lo, hi, what) => {
  if (typeof v !== 'number' || !Number.isFinite(v) || v < lo || v > hi) throw new Error(`${what} is not a number between ${lo} and ${hi}`);
  return v;
};

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const object = (value, keys) => {
  if (!value || typeof value !== 'object' || Array.isArray(value) || Object.keys(value).some(k => !keys.includes(k))) throw new Error('Unknown or invalid sync fields');
};

// Real observation dates come from camera completion events, never an even spacing estimate.
export function parseSync(body, { userId, now = Date.now() } = {}) {
  object(body, ['workoutId', 'userId', 'cloudConsent', 'source', 'variation', 'startedAt', 'endedAt', 'timeMs', 'reps']);
  if (typeof userId !== 'string' || !userId.trim() || userId.length > 128 || body.userId !== userId) throw new Error('Workout owner does not match this server');
  if (body.cloudConsent !== true || body.source !== 'real' || body.variation !== 'standard') throw new Error('Explicit consent and a real standard-camera workout are required');
  if (typeof body.workoutId !== 'string' || !uuid.test(body.workoutId)) throw new Error('A stable workout UUID is required');
  if (!Array.isArray(body.reps) || !body.reps.length || body.reps.length > MAX_SYNC_REPS) throw new Error('Workout needs 1–500 observed reps');
  const startedAt = num(body.startedAt, Date.UTC(2020, 0, 1), now + 2000, 'startedAt');
  const endedAt = num(body.endedAt, startedAt, now + 2000, 'endedAt');
  if (!Number.isSafeInteger(startedAt) || !Number.isSafeInteger(endedAt) || endedAt - startedAt > 86400000) throw new Error('Workout dates must be integer milliseconds within 24 hours');
  const timeMs = num(body.timeMs, 0, endedAt - startedAt, 'timeMs');
  let previous = startedAt - 1;
  const reps = body.reps.map(r => {
    object(r, ['observedAt', 'counted', 'good', 'minElbow', 'minLine', 'secs', 'issue']);
    const observedAt = num(r.observedAt, startedAt, endedAt, 'observedAt');
    if (!Number.isSafeInteger(observedAt) || observedAt <= previous) throw new Error('Rep observation times must be strictly ordered');
    previous = observedAt;
    if (typeof r.counted !== 'boolean' || typeof r.good !== 'boolean' || (r.good && !r.counted)) throw new Error('Rep judgments must be consistent booleans');
    if (r.issue != null && (typeof r.issue !== 'string' || r.issue.length > 200)) throw new Error('Rep issue exceeds its text limit');
    return { observedAt, counted: r.counted, good: r.good, minElbow: num(r.minElbow, 0, 180, 'elbow'), minLine: num(r.minLine, 0, 180, 'body line'), secs: r.secs == null ? null : num(r.secs, 0, 600, 'seconds'), issue: r.issue ?? null };
  });
  const workoutId = body.workoutId.toLowerCase();
  const snapshot = { workoutId, userId, cloudConsent: true, source: 'real', variation: 'standard', startedAt, endedAt, timeMs, reps };
  const contentHash = createHash('sha256').update(JSON.stringify(snapshot)).digest('hex');
  const session = Math.floor(startedAt / 1000);
  const rows = reps.map((r, i) => ({ measured_at: new Date(r.observedAt).toISOString(), session, rep: i + 1, elbow: r.minElbow, body_line: r.minLine, seconds: r.secs, counted: r.counted, label: labelOf(r) }));
  return { workoutId, userId, source: 'real', session, rows, contentHash };
}

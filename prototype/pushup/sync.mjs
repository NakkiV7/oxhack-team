// Turns a finished workout from the page into rep rows for Tiger Data. Pure, so it is easy to test.
// The page sends { startedAt (ms), timeMs, reps: [{ counted, good, minElbow, minLine, secs, issue }] }.

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

// Session id = start time in epoch seconds, so sending the same workout again maps to the same rows
// (inserts skip rows that already exist) and a retry never creates a duplicate session.
export function parseSync(body) {
  if (!body || !Array.isArray(body.reps)) throw new Error('reps must be a list');
  if (!body.reps.length) throw new Error('no reps to save');
  if (body.reps.length > MAX_SYNC_REPS) throw new Error(`more than ${MAX_SYNC_REPS} reps`);
  const startedAt = num(body.startedAt, Date.UTC(2020, 0, 1), Date.now() + 86400000, 'startedAt');
  const timeMs = num(body.timeMs ?? 0, 0, 86400000, 'timeMs');
  const step = Math.max(1000, Math.floor(timeMs / body.reps.length));
  const session = Math.floor(startedAt / 1000);
  const rows = body.reps.map((r, i) => ({
    measured_at: new Date(startedAt + i * step).toISOString(),
    session,
    rep: i + 1,
    elbow: num(r.minElbow, 0, 180, `rep ${i + 1} elbow`),
    body_line: num(r.minLine, 0, 180, `rep ${i + 1} body line`),
    seconds: r.secs == null ? null : num(r.secs, 0, 600, `rep ${i + 1} seconds`),
    counted: !!r.counted,
    label: labelOf(r),
  }));
  return { session, rows };
}

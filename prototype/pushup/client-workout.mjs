// Local workout provenance and an explicit, durable upload outbox. No startup requests or automatic retries.
const KEY = 'pushup.pendingSync.v2';
const copy = value => JSON.parse(JSON.stringify(value));

export function createWorkoutClient({ storage, context, send, status = () => {}, now = Date.now, uuid = () => crypto.randomUUID() }) {
  let current = null;
  const activeUploads = new Set();
  const entries = () => {
    const rows = JSON.parse(storage.getItem(KEY) ?? '[]');
    if (!Array.isArray(rows) || rows.some(row => !row?.body || typeof row.body.workoutId !== 'string' || typeof row.body.userId !== 'string')) {
      throw new Error('Pending uploads are unreadable; preserve browser storage for recovery.');
    }
    return rows;
  };
  const write = rows => storage.setItem(KEY, JSON.stringify(rows));
  const notify = (id, info) => { if (current?.workoutId === id) status(info); };
  async function upload(body, suppliedContext) {
    const payload = copy(body);
    if (!payload.userId) throw new Error('A captured workout owner is required.');
    if (activeUploads.has(payload.workoutId)) throw new Error('This workout is already uploading.');
    const rows = entries(), existing = rows.find(row => row.body.workoutId === payload.workoutId);
    if (existing?.conflict) throw new Error('workout_conflict: discard the pending copy explicitly before any new upload.');
    if (existing && JSON.stringify(existing.body) !== JSON.stringify(payload)) throw new Error('Pending workout differs; preserve it for review.');
    write(existing ? rows : [...rows, { body: payload, conflict: false }]); // Must succeed before the upload request starts.
    activeUploads.add(payload.workoutId);
    notify(payload.workoutId, { status: 'saving', text: 'Uploading workout to Tiger Data…' });
    try {
      const access = suppliedContext ?? await context();
      if (payload.userId !== access.userId) throw new Error('This workout belongs to another user; it was not uploaded.');
      if (!access.cloudAvailable || !access.token) throw new Error('Cloud upload is unavailable; check the local server configuration.');
      const result = await send(payload, access.token);
      let cleanupFailed = false;
      try { write(entries().filter(row => row.body.workoutId !== payload.workoutId)); } catch { cleanupFailed = true; }
      const receipt = result.saved === 0 ? 'Already saved to Tiger Data.' : `Saved ${result.saved ?? payload.reps.length} reps to Tiger Data.`;
      notify(payload.workoutId, { status: 'saved', text: receipt + (cleanupFailed ? ' Browser cleanup failed; a later explicit retry is safe.' : '') });
      return result;
    } catch (error) {
      if (error.status === 409) write(entries().map(row => row.body.workoutId === payload.workoutId ? { ...row, conflict: true } : row));
      notify(payload.workoutId, { status: 'failed', text: error.status === 409 ? 'Upload conflict. Pending copy retained; review and discard it explicitly.' : 'Not uploaded. Retained in this browser; retry explicitly.' });
      throw error;
    } finally { activeUploads.delete(payload.workoutId); }
  }
  return {
    start({ source, variation, userId }) {
      current = { workoutId: uuid(), userId: userId ?? null, source, variation, startedAt: now(), reps: [] };
      status(null);
      return current.workoutId;
    },
    observe(rep) {
      if (!current || current.endedAt != null) return;
      current = { ...current, reps: [...current.reps, {
        observedAt: now(), counted: rep.counted, good: rep.baseGood ?? rep.good,
        minElbow: rep.minElbow, minLine: rep.minLine, secs: rep.secs ?? null, issue: 'baseIssue' in rep ? rep.baseIssue : rep.issue ?? null,
      }] };
    },
    finish(timeMs) {
      if (!current) return null;
      if (current.endedAt == null) current = { ...current, endedAt: now(), timeMs };
      if (current.source !== 'camera' || current.variation !== 'standard' || !current.userId || !current.reps.length) return null;
      return copy({ ...current, source: 'real', cloudConsent: true });
    },
    pending: () => entries().map(row => row.body),
    conflicts: userId => entries().filter(row => row.conflict && row.body.userId === userId).map(row => row.body),
    discard(workoutId, userId) { write(entries().filter(row => row.body.workoutId !== workoutId || row.body.userId !== userId)); },
    upload,
    async retry() {
      const access = await context();
      let saved = 0, failed = 0;
      for (const row of entries().filter(row => !row.conflict && row.body.userId === access.userId)) {
        try { await upload(row.body, access); saved++; } catch { failed++; }
      }
      return { saved, failed };
    },
  };
}

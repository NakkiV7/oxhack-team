import { createHash } from 'node:crypto';
import { buildProfile, readiness, mockShare, validateRows, READY } from './profile.mjs';

function trainingContext({ rows, where, userId, selectedSources }) {
  if (typeof userId !== 'string' || !userId.trim() || userId.length > 200) throw new Error('Invalid profile owner');
  if (!Array.isArray(selectedSources) || !selectedSources.length || selectedSources.some((s) => !['mock', 'real'].includes(s))) throw new Error('Invalid profile source selection');
  const sources = [...new Set(selectedSources)].sort();
  const validated = validateRows(rows);
  if (validated.some((row) => !sources.includes(row.source ?? 'mock'))) throw new Error('Invalid profile row source for selection');
  const canonical = validated.map((row) => JSON.stringify([
    row.session, row.rep, row.elbow, row.body_line, row.seconds, Boolean(row.counted), row.label,
    row.source ?? 'mock', row.date ?? null, row.measured_at ?? null, row.workout_id ?? null,
  ])).sort();
  const datasetSha256 = createHash('sha256').update(JSON.stringify(canonical)).digest('hex');
  return { rows: validated, where, provenance: { version: 1, userId, selectedSources: sources, datasetSha256 } };
}

const finiteBetween = (value, min, max) => Number.isFinite(value) && value >= min && value <= max;
const positiveInteger = (value, min) => Number.isSafeInteger(value) && value >= min;
function validSavedProfile(profile) {
  const p = profile?.provenance;
  if (!p || p.version !== 1 || typeof p.userId !== 'string' || !p.userId.trim() || !Array.isArray(p.selectedSources) || !p.selectedSources.length) return false;
  if (p.selectedSources.some((s) => !['mock', 'real'].includes(s)) || !/^[a-f0-9]{64}$/.test(p.datasetSha256)) return false;
  if (!finiteBetween(profile.mockShare, 0, 1) || !positiveInteger(profile.reps, READY.minReps) || !positiveInteger(profile.sessions, READY.minSessions)) return false;
  if (!positiveInteger(profile.baselines?.goodReps, READY.minGood) || profile.baselines.goodReps > profile.reps) return false;
  for (const key of ['elbow', 'body_line', 'seconds']) {
    const stat = profile.baselines[key];
    const max = key === 'seconds' ? 86400 : 180;
    if (!stat || !finiteBetween(stat.typical, 0, max) || !finiteBetween(stat.spread, 0, max)) return false;
  }
  return typeof profile.trainedAt === 'string' && Number.isFinite(Date.parse(profile.trainedAt))
    && (profile.holdoutAccuracy === null || finiteBetween(profile.holdoutAccuracy, 0, 1))
    && Array.isArray(profile.rules) && profile.rules.length > 0 && profile.rules.every((rule) => typeof rule === 'string');
}

function savedProfileReason(profile, provenance) {
  if (!profile) return 'missing';
  if (!validSavedProfile(profile)) return 'invalid';
  if (profile.provenance.userId !== provenance.userId) return 'owner-mismatch';
  if (JSON.stringify([...new Set(profile.provenance.selectedSources)].sort()) !== JSON.stringify(provenance.selectedSources)) return 'sources-mismatch';
  return null;
}

export function createProfileService({ loadRows, save, load, now = () => Date.now() }) {
  return {
    async status() {
      const { rows, where, provenance } = trainingContext(await loadRows());
      const saved = (await load?.()) ?? null;
      const profileReason = savedProfileReason(saved, provenance);
      const profile = profileReason ? null : saved;
      const historyMockShare = mockShare(rows);
      return {
        where, ...readiness(rows), mockShare: historyMockShare, historyMockShare, profile, profileReason,
        datasetChanged: profile ? profile.provenance.datasetSha256 !== provenance.datasetSha256 : null,
      };
    },
    async train() {
      const started = now();
      const { rows, where, provenance } = trainingContext(await loadRows());
      const check = readiness(rows);
      if (!check.ready) return { ok: false, where, ...check };
      const profile = {
        ...buildProfile(rows), where, provenance,
        mockShare: mockShare(rows.filter((row) => row.seconds !== null)),
        trainedAt: new Date(now()).toISOString(),
      };
      if (!validSavedProfile(profile)) throw new Error('Invalid profile artifact');
      await save(profile);
      return {
        ok: true, where, ...check, mockShare: profile.mockShare, ms: now() - started, profile,
        stages: ['Loaded your reps', 'Built your baselines', 'Fitted the rule tree', 'Checked it on sessions it had not seen', 'Saved your profile'],
      };
    },
  };
}

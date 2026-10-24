// Status + training for the "My profile" dialog. Rows come from `loadRows` (Tiger Data, or the CSV when Tiger is
// not configured) and the result goes to `save`, so tests can pass fakes and the server stays thin.
import { buildProfile, readiness, mockShare } from './profile.mjs';

export function createProfileService({ loadRows, save, load, now = () => Date.now() }) {
  return {
    async status() {
      const { rows, where } = await loadRows();
      return { where, ...readiness(rows), mockShare: mockShare(rows), profile: (await load?.()) ?? null };
    },
    // Returns the stages that ran, so the page can show them; refuses when there is not enough data.
    async train() {
      const started = now();
      const { rows, where } = await loadRows();
      const check = readiness(rows);
      if (!check.ready) return { ok: false, where, ...check };
      const profile = { ...buildProfile(rows), where, mockShare: mockShare(rows), trainedAt: new Date(now()).toISOString() };
      await save(profile);
      return {
        ok: true, where, ...check, mockShare: profile.mockShare, ms: now() - started, profile,
        stages: ['Loaded your reps', 'Built your baselines', 'Fitted the rule tree', 'Checked it on sessions it had not seen', 'Saved your profile'],
      };
    },
  };
}

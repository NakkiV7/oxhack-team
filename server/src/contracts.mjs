import { z } from 'zod';
import { readFileSync } from 'node:fs';

const boundedText = max => z.string().max(max).refine(value => value.trim().length > 0);
const fact = z.strictObject({ id: boundedText(128), text: boundedText(2000) });
export const coachRequest = z.strictObject({
  generationID: boundedText(128),
  message: boundedText(4000).optional(),
  history: z.array(z.strictObject({ role: z.enum(['user', 'model']), text: boundedText(4000) })).max(20).default([]),
  facts: z.array(fact).max(128).refine(facts => new Set(facts.map(item => item.id)).size === facts.length).default([]),
  availableSupport: z.array(boundedText(100)).max(16).default([]),
  kind: z.enum(['session', 'weekly']).optional()
});

const catalogSource = readFileSync(new URL('../../Shared/Core/ExerciseCatalog.swift', import.meta.url), 'utf8');
const catalogRows = catalogSource.split('\n').filter(line => line.includes('.init(id:'));
export const catalog = catalogRows.map(line => {
  const match = line.match(/\.init\(id: "([^"]+)", name: "([^"]+)".*?unit: \.(reps|seconds).*?support: (nil|"[^"]+"), tracking: (nil|\.[A-Za-z0-9]+)/);
  if (!match) throw Error('Exercise catalogue format changed; update gateway catalogue reader.');
  return { id: match[1], name: match[2], unit: match[3], support: match[4] === 'nil' ? null : JSON.parse(match[4]), cameraTracking: match[5] !== 'nil' };
});
if (!catalog.length || new Set(catalog.map(item => item.id)).size !== catalog.length) throw Error('Exercise catalogue is empty or ambiguous.');

export const appCapabilities = {
  exercises: catalog.map(({ id, name, unit, cameraTracking }) => ({ id, name, unit, cameraTracking })),
  inputRules: 'Camera tracking is available only for entries with cameraTracking true. Other rep exercises use manual self-report; seconds exercises use an active hold timer. Camera support does not extend to untracked variants.',
  setControl: 'Custom workout sets require explicit Start and End set. Reaching the target does not automatically end the set.',
  voiceFeedback: 'Local spoken camera cues are optional and off until enabled by the user for the workout.'
};

export function outputContract({ path, data }) {
  const generationID = z.enum([data.generationID]);
  const evidence = z.array(z.enum(data.facts.map(item => item.id))).min(1).max(16).refine(ids => new Set(ids).size === ids.length);
  const grounded = z.strictObject({ text: boundedText(500), factIDs: evidence });
  if (path === '/v1/summary') {
    return z.strictObject({ generationID, kind: z.enum([data.kind ?? 'session']), headline: grounded, insights: z.array(grounded).max(3), focus: grounded });
  }
  const permitted = catalog.filter(item => !item.support || data.availableSupport.includes(item.support));
  const item = z.strictObject({
    exerciseID: z.enum(permitted.map(item => item.id)),
    sets: z.number().int().min(1).max(5),
    target: z.number().int().min(1).max(120),
    unit: z.enum(['reps', 'seconds']),
    restSeconds: z.number().int().min(0).max(600),
    factIDs: evidence
  }).refine(item => permitted.some(exercise => exercise.id === item.exerciseID && exercise.unit === item.unit) && item.target <= (item.unit === 'reps' ? 30 : 120));
  return z.strictObject({
    generationID,
    items: z.array(item).min(1).max(12).refine(items => new Set(items.map(item => item.exerciseID)).size === items.length && items.reduce((sum, item) => sum + item.sets, 0) <= 24),
    rationale: grounded
  });
}

export function jsonContract(schema) {
  return z.toJSONSchema(schema, { unrepresentable: 'any', target: 'draft-7' });
}

export function promptCatalog(data) {
  return catalog.filter(item => !item.support || data.availableSupport.includes(item.support));
}

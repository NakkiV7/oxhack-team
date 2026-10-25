import { z } from 'zod';
import { catalog } from './contracts.mjs';

const date = z.iso.datetime({ offset: true });
const quantity = max => z.number().min(0).max(max);
const source = z.enum(['camera', 'video', 'manual']);
const reason = z.enum(['target', 'voluntary', 'form', 'failure', 'discomfort']);
const reading = max => z.strictObject({ value: quantity(max), date });
const trackedSet = z.strictObject({
  id: z.uuid(), exercise: z.enum(['squat', 'pushup']), number: z.number().int().min(1).max(200),
  reps: quantity(200).int(), target: quantity(200).int(), activeSeconds: quantity(86400), source,
  reserve: quantity(20).int().nullable().optional(), reason, restSecondsBefore: z.number().nonnegative().nullable().optional(), repDurations: z.array(quantity(600)).max(200).nullable().optional()
});
const loggedSet = z.strictObject({
  id: z.uuid(), exerciseID: z.enum(catalog.map(item => item.id)), reps: quantity(200).int(),
  seconds: quantity(86400), source, reason,
  number: z.number().int().min(1).max(10).nullable().optional(),
  target: z.number().int().min(1).max(600).nullable().optional(),
  activeSeconds: quantity(86400).nullable().optional(),
  restSecondsBefore: z.number().finite().nonnegative().nullable().optional(),
  reserve: quantity(3).int().nullable().optional(),
  quantityOrigin: z.enum(['selfReport', 'activeTimer']).nullable().optional(),
  repDurations: z.array(z.number().finite().min(0.6).max(15)).max(200).nullable().optional()
}).refine(set => {
  const exercise = catalog.find(exercise => exercise.id === set.exerciseID);
  if (!exercise || (exercise.unit === 'reps' ? set.seconds !== 0 : set.reps !== 0)) return false;
  if (set.quantityOrigin != null && set.source !== 'manual') return false;
  if (set.repDurations != null && (set.source !== 'camera' || !['squat', 'pushup'].includes(set.exerciseID)
    || set.repDurations.length !== set.reps)) return false;
  if (set.target != null && set.target > (exercise.unit === 'reps' ? 200 : 600)) return false;
  if (exercise.unit === 'seconds' && set.reserve != null) return false;
  if (set.quantityOrigin === 'activeTimer') return exercise.unit === 'seconds' && set.activeSeconds != null && set.activeSeconds === set.seconds;
  return set.seconds <= 600;
});
const telemetry = z.strictObject({
  sessionID: z.uuid(), sentAt: date,
  heartRate: reading(300).refine(reading => reading.value >= 1).nullable().optional(),
  accelerationG: reading(1000).nullable().optional(),
  rotationRadiansPerSecond: reading(1000).nullable().optional()
});
export const sessionRecord = z.strictObject({
  id: z.uuid(), date, sets: z.array(trackedSet).max(120),
  loggedSets: z.array(loggedSet).max(120).default([]), telemetry: z.array(telemetry).max(7200).default([])
}).refine(record => {
  const ids = [...record.sets, ...record.loggedSets].map(set => set.id.toLowerCase());
  return ids.length <= 120 && new Set(ids).size === ids.length && record.telemetry.every(sample => sample.sessionID.toLowerCase() === record.id.toLowerCase());
});
export const workoutRequest = z.strictObject({ installationID: z.uuid(), record: sessionRecord });
export const workoutIDContract = z.uuid();
export const telemetryQuery = z.strictObject({ workoutID: z.uuid(), from: date, to: date })
  .refine(query => Date.parse(query.to) > Date.parse(query.from) && Date.parse(query.to) - Date.parse(query.from) <= 86_400_000);
export const rollupQuery = z.strictObject({ workoutID: z.uuid(), from: date, to: date, bucketSeconds: z.union([z.literal(5), z.literal(60)]) })
  .refine(query => Date.parse(query.to) > Date.parse(query.from) && Date.parse(query.to) - Date.parse(query.from) <= 86_400_000);

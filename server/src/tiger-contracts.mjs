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
  reserve: quantity(20).int().nullable().optional(), reason, repDurations: z.array(quantity(600)).max(200).nullable().optional()
});
const loggedSet = z.strictObject({
  id: z.uuid(), exerciseID: z.enum(catalog.map(item => item.id)), reps: quantity(200).int(),
  seconds: quantity(600), source, reason
}).refine(set => catalog.some(exercise => exercise.id === set.exerciseID && (exercise.unit === 'reps' ? set.seconds === 0 : set.reps === 0)));
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

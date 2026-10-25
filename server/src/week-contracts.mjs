import { z } from 'zod';
import { coachRequest, outputContract } from './contracts.mjs';
import { guidanceSources } from './coach-guidance.mjs';

const localDate = z.string().regex(/^\d{4}-\d{2}-\d{2}$/).refine(value => {
  const date = new Date(`${value}T12:00:00Z`);
  return Number.isFinite(date.getTime()) && date.toISOString().slice(0, 10) === value;
});
const timeZone = z.string().max(100).refine(value => { try { new Intl.DateTimeFormat('en', { timeZone: value }); return true; } catch { return false; } });
export const weekRequest = coachRequest.extend({ week: z.strictObject({
  startDate: localDate, timeZone,
  availableDays: z.array(z.number().int().min(0).max(6)).min(1).max(7).refine(days => new Set(days).size === days.length),
  targetDays: z.number().int().min(1).max(7)
}).refine(week => week.targetDays <= week.availableDays.length) });

export function weekDates(startDate) {
  return Array.from({ length: 7 }, (_, offset) => new Date(Date.parse(`${startDate}T12:00:00Z`) + offset * 86_400_000).toISOString().slice(0, 10));
}

export function weekOutputContract(data) {
  const generationID = z.enum([data.generationID]);
  const guidanceIDs = z.array(z.enum(guidanceSources.map(source => source.id))).min(1).max(5).refine(ids => new Set(ids).size === ids.length);
  const hasLink = text => /https?:|www\./i.test(text);
  const plan = outputContract({ path: '/v1/proposal', data }).refine(plan => plan.items.length <= 3 && !hasLink(plan.rationale.text));
  const proposed = z.strictObject({
    generationID, status: z.literal('proposed'), weekStart: z.enum([data.week.startDate]), timeZone: z.enum([data.week.timeZone]),
    days: z.array(z.strictObject({ date: localDate, kind: z.enum(['workout', 'rest']), workout: plan.nullable() })).length(7),
    rationale: outputContract({ path: '/v1/proposal', data }).shape.rationale,
    guidanceIDs
  }).refine(proposal => {
    const dates = weekDates(data.week.startDate);
    const workouts = proposal.days.filter(day => day.kind === 'workout');
    return !hasLink(proposal.rationale.text) && workouts.length > 0 && workouts.length <= data.week.targetDays && proposal.days.every((day, index) =>
      day.date === dates[index] && (day.kind === 'rest' ? day.workout === null : day.workout !== null && data.week.availableDays.includes(index)));
  });
  const declined = z.strictObject({ generationID, status: z.literal('declined'), reason: z.enum(['unrelated', 'medical', 'urgent']), guidanceIDs }).refine(declined => declined.reason !== 'urgent' || declined.guidanceIDs.includes('nhs-chest-pain'));
  return z.union([proposed, declined]);
}

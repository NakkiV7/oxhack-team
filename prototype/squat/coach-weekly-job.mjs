// Server-side entry point for the weekly review: run from a scheduler (launchd, cron, a CI job) once a week.
//   node --env-file=.env coach-weekly-job.mjs [user]
// Idempotent: the same inputs produce the same saved report; nothing is sent anywhere.
import { createPool, migrate } from '../shared/tiger-stream.mjs';
import { createCoachAI } from './coach-gemini.mjs';
import { generateWeekly } from './coach-service.mjs';

const user = process.argv[2] ?? process.env.SPOTTR_USER_ID ?? 'nakki';
const { default: pg } = await import('pg');
pg.types.setTypeParser(1082, (v) => v);
const pool = await createPool({ Pool: pg.Pool });
await migrate(pool);
const key = process.env.GEMINI_API_KEY, model = process.env.GEMINI_MODEL ?? 'gemini-3.5-flash';
const callGemini = key ? async (body) => { const r = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'x-goog-api-key': key }, body: JSON.stringify(body), signal: AbortSignal.timeout(40000) }); return r.ok ? r.json() : null; } : null;
const { report, generated } = await generateWeekly({ pool, ai: createCoachAI({ callGemini, model }), user });
console.log(`${generated ? 'generated' : 'already had'} weekly report ${report.report_id} for ${user}: week of ${report.period_start}, status ${report.status}, version ${report.version}`);
await pool.end();

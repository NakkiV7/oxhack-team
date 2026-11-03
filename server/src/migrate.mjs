import { readFile } from 'node:fs/promises';
import { Pool } from 'pg';

if (!process.env.TIGER_DATABASE_URL) {
  console.error('TIGER_DATABASE_URL must be configured before running the migration.');
  process.exit(1);
}
const pool = new Pool({ connectionString: process.env.TIGER_DATABASE_URL, max: 1, connectionTimeoutMillis: 10000, statement_timeout: 60000 });
pool.on('error', () => {});
try {
  const sql1 = await readFile(new URL('../migrations/001_workouts.sql', import.meta.url), 'utf8');
  await pool.query(sql1);
  console.log('Applied 001_workouts.sql: Spottr workout snapshot and scalar hypertable.');

  const sql2 = await readFile(new URL('../migrations/002_calendar_and_analytics.sql', import.meta.url), 'utf8');
  await pool.query(sql2);
  console.log('Applied 002_calendar_and_analytics.sql: Calendar view & continuous aggregate telemetry rollup.');
} catch (error) {
  console.error('Migration failed. Details:', error.message);
  process.exitCode = 1;
} finally { await pool.end(); }

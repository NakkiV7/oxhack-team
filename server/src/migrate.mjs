import { readFile } from 'node:fs/promises';
import { Pool } from 'pg';

if (!process.env.TIGER_DATABASE_URL) {
  console.error('TIGER_DATABASE_URL must be configured before running the migration.');
  process.exit(1);
}
const pool = new Pool({ connectionString: process.env.TIGER_DATABASE_URL, max: 1, connectionTimeoutMillis: 5000, statement_timeout: 30000 });
pool.on('error', () => {});
try {
  const sql = await readFile(new URL('../migrations/001_workouts.sql', import.meta.url), 'utf8');
  await pool.query(sql);
  console.log('Applied Spottr workout snapshot and scalar hypertable migration.');
} catch {
  console.error('Migration failed. Check database access, TimescaleDB availability and schema permissions.');
  process.exitCode = 1;
} finally { await pool.end(); }

// Tiger Data helper. Usage: node db.mjs migrate | load [history.csv] [mock|real] | stats
// Reads TIGER_DATABASE_URL and PUSHUP_USER_ID from the environment (npm scripts load pushup/.env).
import { readFileSync } from 'node:fs';
import { parseCsv } from './profile.mjs';
import { createPool, migrate, insertReps, sessionStats } from './tiger.mjs';

const [cmd, a, b] = process.argv.slice(2);
const userId = process.env.PUSHUP_USER_ID || 'local';
let pool;
try {
  pool = await createPool();
  if (cmd === 'migrate') {
    console.log('Applied:', (await migrate(pool)).join(', '));
  } else if (cmd === 'load') {
    const rows = parseCsv(readFileSync(a || new URL('./data/history.csv', import.meta.url), 'utf8'));
    const added = await insertReps(pool, rows, { userId, source: b || 'mock' });
    console.log(`Read ${rows.length} reps, added ${added} (user ${userId}, source ${b || 'mock'}).`);
  } else if (cmd === 'stats') {
    await pool.query("CALL refresh_continuous_aggregate('pushup.session_stats', NULL, NULL)");
    console.table(await sessionStats(pool, { userId }));
  } else {
    console.error('Usage: node db.mjs migrate | load [history.csv] [mock|real] | stats');
    process.exitCode = 1;
  }
} catch (e) {
  console.error(`Failed: ${e.message}`);
  process.exitCode = 1;
} finally {
  await pool?.end();
}

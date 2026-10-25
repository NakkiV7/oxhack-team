import { Pool } from 'pg';
import { createTigerStore } from './tiger.mjs';

if (!process.env.TIGER_DATABASE_URL) {
  console.error('TIGER_DATABASE_URL required');
  process.exit(1);
}

const installationID = process.env.SPOTTR_INSTALLATION_ID || '00000000-0000-4000-8000-000000000001';
const pool = new Pool({ connectionString: process.env.TIGER_DATABASE_URL, max: 2, connectionTimeoutMillis: 5000 });
const store = createTigerStore({ pool, installationID });

const workoutDates = [
  '2026-10-02', '2026-10-05', '2026-10-07', '2026-10-09',
  '2026-10-12', '2026-10-14', '2026-10-16', '2026-10-19',
  '2026-10-21', '2026-10-23', '2026-10-24'
];

async function seed() {
  console.log('Seeding demo workouts to live TigerData instance...');
  for (let i = 0; i < workoutDates.length; i++) {
    const d = workoutDates[i];
    const workoutID = `00000000-0000-4000-8000-${String(i + 1).padStart(12, '0')}`;
    const baseReps = 15 + Math.floor(i * 1.5);

    const record = {
      id: workoutID,
      date: `${d}T18:00:00.000Z`,
      sets: [
        {
          id: `00000000-0000-4000-9000-${String(i * 4 + 1).padStart(12, '0')}`,
          exercise: 'pushup',
          number: 1,
          reps: baseReps,
          target: 20,
          activeSeconds: baseReps * 2.2,
          source: 'camera',
          reserve: 2,
          reason: 'voluntary',
          restSecondsBefore: null
        },
        {
          id: `00000000-0000-4000-9000-${String(i * 4 + 2).padStart(12, '0')}`,
          exercise: 'pushup',
          number: 2,
          reps: baseReps,
          target: 20,
          activeSeconds: baseReps * 2.3,
          source: 'camera',
          reserve: 1,
          reason: 'voluntary',
          restSecondsBefore: 60
        },
        {
          id: `00000000-0000-4000-9000-${String(i * 4 + 3).padStart(12, '0')}`,
          exercise: 'squat',
          number: 3,
          reps: baseReps + 5,
          target: 20,
          activeSeconds: (baseReps + 5) * 2.5,
          source: 'camera',
          reserve: 3,
          reason: 'voluntary',
          restSecondsBefore: 75
        },
        {
          id: `00000000-0000-4000-9000-${String(i * 4 + 4).padStart(12, '0')}`,
          exercise: 'squat',
          number: 4,
          reps: baseReps + 4,
          target: 20,
          activeSeconds: (baseReps + 4) * 2.6,
          source: 'camera',
          reserve: 2,
          reason: 'voluntary',
          restSecondsBefore: 60
        }
      ],
      loggedSets: [],
      telemetry: [
        {
          sessionID: workoutID,
          sentAt: `${d}T18:20:00.000Z`,
          heartRate: { value: 135 + (i % 8) * 2, date: `${d}T18:05:00.000Z` },
          accelerationG: { value: 1.05, date: `${d}T18:05:00.000Z` },
          rotationRadiansPerSecond: { value: 0.12, date: `${d}T18:05:00.000Z` }
        },
        {
          sessionID: workoutID,
          sentAt: `${d}T18:20:00.000Z`,
          heartRate: { value: 162 + (i % 5) * 2, date: `${d}T18:15:00.000Z` },
          accelerationG: { value: 1.15, date: `${d}T18:15:00.000Z` }
        }
      ]
    };

    try {
      const res = await store.ingest({ installationID, record });
      console.log(`Workout for ${d} ingested (replayed: ${res.replayed})`);
    } catch (err) {
      console.error(`Failed to ingest workout for ${d}:`, err.message);
    }
  }

  console.log('Seeding complete!');
  await pool.end();
}

seed().catch(err => {
  console.error('Seed script error:', err);
  pool.end();
});

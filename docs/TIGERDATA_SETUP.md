# Linking TigerData Cloud to Spottr

This guide explains how to link your **TigerData Cloud** service (created on `console.cloud.tigerdata.com`) to the Spottr mobile app and gateway, and how your workout results, calendar screen, and progression statistics are stored and queried.

---

## 1. Extracting Credentials from TigerData Cloud

When you deploy a service in the TigerData Cloud Console (as shown in your deployment screen), you are prompted to download two configuration files:
* `tiger-cloud-oxhack-credentials.txt`
* `tiger-cloud-oxhack-credentials.env`

> [!IMPORTANT]
> This is the **only time** TigerData reveals the generated database password. Save these files in a secure location.

Open `tiger-cloud-oxhack-credentials.env` or `.txt`. You will see connection parameters formatted like:

```ini
# TigerData Cloud Service Config
PGHOST=eyx5jmou3r.a57ufa2mfm.tsdb.cloud.tigerdata.com
PGPORT=5432
PGDATABASE=tsdb
PGUSER=tsdbadmin
PGPASSWORD=<YOUR_SECRET_PASSWORD>
DATABASE_URL=postgres://tsdbadmin:<YOUR_SECRET_PASSWORD>@eyx5jmou3r.a57ufa2mfm.tsdb.cloud.tigerdata.com:5432/tsdb?sslmode=require
```

---

## 2. Configuring Spottr Environment Variables

Your `.env` file in the root directory has been configured with your live service details:

```ini
# Root .env
SPOTTR_GATEWAY_TOKEN=spottr-dev-token-9821
HOST=127.0.0.1
PORT=8787

# Tiger PostgreSQL/TimescaleDB (Service oxhack)
TIGER_DATABASE_URL=postgres://tsdbadmin:xofiijttu4bse2sp@eyx5jmou3r.a57ufa2mfm.tsdb.cloud.timescale.com:32273/tsdb?sslmode=require
SPOTTR_INSTALLATION_ID=00000000-0000-4000-8000-000000000001
```

*(Note: `.env` is git-ignored and never committed to source control).*

---

## 3. Running Database Migrations

Apply the migration scripts located in `server/migrations/`:

```bash
cd server
npm run migrate
```

Alternatively, you can run them directly in the TigerData Cloud web SQL console or via `psql`:

1. **`001_workouts.sql`**:
   - Enables the `timescaledb` extension.
   - Creates `spottr_gateway.workout` for structured JSON workout records with SHA256 integrity checks.
   - Creates the **`spottr_gateway.scalar_sample`** table and converts it to a Timescale **Hypertable** with 1-day range partitions:
     ```sql
     SELECT create_hypertable('spottr_gateway.scalar_sample', by_range('measured_at', INTERVAL '1 day'), if_not_exists => TRUE);
     ```

2. **`002_calendar_and_analytics.sql`**:
   - **`spottr_gateway.daily_workout_summary`**: A view aggregating daily volume, exercise types, and total reps.
   - **`spottr_gateway.daily_telemetry_rollup`**: A **Timescale Continuous Aggregate Materialized View** that rolls up millions of high-frequency Apple Watch samples (Heart Rate, PPG, Wrist Acceleration) into daily averages, maximums, and trends.
   - Configures a continuous aggregate refresh policy (`add_continuous_aggregate_policy`).
   - **`spottr_gateway.set_progression`**: Flattens workout sets to track exercise-specific cadence, reps-in-reserve (fatigue), and rest intervals.

---

## 4. How the Data Flows

```mermaid
flowchart TD
    iPhone[Spottr iPhone + Apple Watch] -->|Offline-First Tracking| LocalStore[Local Device Swift Data]
    LocalStore -->|POST /v1/workouts with Bearer Token| Gateway[Spottr Gateway Node.js]
    Gateway -->|Insert Structured Record| WTable[(spottr_gateway.workout)]
    Gateway -->|Stream 7200+ Watch PPG Samples| HTable[(spottr_gateway.scalar_sample Hypertable)]
    HTable -->|Continuous Aggregate Engine| Cagg[(spottr_gateway.daily_telemetry_rollup)]
    Cagg -->|GET /v1/workouts/calendar| CalPage[Calendar Screen]
    Cagg -->|GET /v1/workouts/statistics| StatPage[Progression & Stats Charts]
```

---

## 5. Built-in Endpoints for Calendar & Stats

The gateway provides REST endpoints for the Calendar and Analytics screens:

| Endpoint | Method | Description |
|---|---|---|
| `/v1/workouts` | `POST` | Ingests a completed workout session with raw Apple Watch telemetry |
| `/v1/workouts/{id}` | `GET` | Fetches a single session by UUID |
| `/v1/workouts/{id}/telemetry` | `GET` | Fetches heart rate & motion time series for a session |
| `/v1/workouts/calendar?year=2026&month=10` | `GET` | Returns daily workout summaries, rep volumes, and heart rate for calendar month grid |
| `/v1/workouts/statistics?days=30&exercise=pushup` | `GET` | Returns time-series progression curves (reps, cadence, fatigue) |

---

## 6. Accessing the Screens

The web interfaces are available in `landing/`:
* **Main Landing Page**: [`landing/index.html`](file:///c:/Users/gitni/Documents/GitHub/oxhack-team/landing/index.html)
* **Training Calendar Screen**: [`landing/calendar.html`](file:///c:/Users/gitni/Documents/GitHub/oxhack-team/landing/calendar.html)
  - Inspect workouts day by day
  - Review set-by-set telemetry and raw TigerData JSON records
  - Compare week-over-week rep volumes and cadence
* **Progression & Statistics Screen**: [`landing/statistics.html`](file:///c:/Users/gitni/Documents/GitHub/oxhack-team/landing/statistics.html)
  - Interactive volume charts over time
  - Apple Watch heart rate zone breakdown
  - Cadence (seconds per rep) fatigue tracking
  - Continuous aggregate SQL inspection

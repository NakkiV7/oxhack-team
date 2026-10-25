# Review-only Tiger Data preparation

`001_schema.sql` proposes relational catalogue/workouts/sets and separate hypertables for heart, motion, pose and rep streams. `002_rollups.sql` proposes five-second and minute heart rollups plus a columnstore policy. `queries.sql` supplies parameterized product reads and idempotent ingestion primitives. These files have not been executed against PostgreSQL/TimescaleDB; no database was provisioned. The Mac has no `psql` on PATH. Syntax was compared with current official documentation on 24 October 2026, which is weaker than a database execution test.

The explicit `create_hypertable(..., by_range(...))` path avoids implicit selection between measurement and receipt timestamps. Target TimescaleDB ≥2.18 and verify the actual extension version first. Stream primary keys include `measured_at`, the partition column. Gateway validation must check stream references against the relational workout/set and installation because the proposal deliberately does not add cross-table stream foreign keys. Seed the catalogue from the exact app catalogue version; do not hand-maintain a second ID list. Set target units must also match catalogue metadata in the gateway.

Store Watch acceleration as raw three-axis **g**, rotation as three-axis **radians/second**, HR as **bpm**, pose as timestamped normalized landmark arrays (coordinate convention/schema version required), and tempo in **seconds**. Do not call 1 Hz magnitudes high-rate raw vectors. Reject nonfinite vectors and bad landmark dimensions at the gateway. Capture UTC measurement time and server receipt time independently; define monotonic-to-UTC clock anchoring and preserve capture IDs before accepting board streams. Missing values remain missing with a reason; quality is source-specific and nullable.

Each receipt is keyed by installation/batch and canonical SHA-256. Receipt and rows commit together; same key with another hash is a conflict. Retry samples retain original event IDs and measurement timestamps. See the gateway README for cross-batch conflicts, scope and late-arrival limits. No numerical synthesis or duplicate interpolation is performed.

Both aggregates use `WITH NO DATA` and explicitly set `timescaledb.materialized_only = false`; the database's real-time query uses its materialization watermark to add the raw tail. The default is not assumed. Historical late data behind the watermark appears after refresh, so the first experiment must check both fresh and delayed arrivals. Bootstrap only a bounded retained-history interval with `refresh_continuous_aggregate`; avoid refreshing through a future endpoint that advances the watermark beyond live data.

The refresh window starts seven days back; columnstore starts at eight days, outside that active window. A proposed raw retention of thirty days is commented out and must stay disabled until preserved features, successful refresh history, late-arrival bounds and export/recovery evidence exist. A refresh window shorter than retention prevents scheduled refreshes from recomputing dropped raw intervals into empty rollups. Do not later issue an unbounded refresh across deleted raw history. If jobs fail longer than the grace interval, stop retention and restore/reconcile before deletion. Rollups are not a backup; retain deterministic workout/set records for skill evidence. Apply equivalent policies to motion/pose/rep only after their feature rollups exist and are verified.

The weekly query uses explicit calendar-derived half-open instants; no UTC-week assumption or incomplete-week comparison. Further motion/pose/rep five-second rollups and daily/weekly workload materializations remain proposals to derive from measured product latency. Current queries keep source provenance and never infer recovery or physical capacity from HR alone.

Next local/hosted validation: apply on a pinned supported extension version; seed real catalogue; insert bounded fixture rows for each stream and both units; assert replay/hash conflict and session ownership; query the live tail; insert delayed samples; inspect job/refresh success; test retention in a disposable database; measure p50/p95 query latency, rows/second, raw/columnstore bytes and actual storage ratio. No advertised compression percentage is a Spottr result.

Official references checked:

- [Hypertable creation and partition-key uniqueness](https://www.tigerdata.com/docs/reference/timescaledb/hypertables/create_hypertable/)
- [Continuous aggregate policy offsets](https://www.tigerdata.com/docs/reference/timescaledb/continuous-aggregates/add_continuous_aggregate_policy/)
- [Explicit real-time aggregation and historical updates](https://www.tigerdata.com/docs/learn/continuous-aggregates/real-time-aggregates/)
- [Columnstore ALTER TABLE settings](https://www.tigerdata.com/docs/reference/timescaledb/hypercore/alter_table/)
- [Columnstore policy procedure](https://www.tigerdata.com/docs/reference/timescaledb/hypercore/add_columnstore_policy/)
- [Retention policy](https://www.tigerdata.com/docs/reference/timescaledb/data-retention/add_retention_policy/)
- [Watermark and retention pitfalls](https://www.tigerdata.com/docs/build/tips-and-tricks/troubleshoot-continuous-aggregates)

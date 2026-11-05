# Watch insights implementation

1. Write failing behavioral analytics tests with known HR interval/zone/coverage, duplicate/out-of-order samples, invalid values, motion windows, rep variability and cumulative-energy scenarios. Implement pure report projections, then run core checks on SSD.
2. Watch worker tests window aggregation, pause/disconnect/session transitions and batch delivery using existing SDK doubles; implements bounded summaries and durable batches without claiming device acceptance.
3. Health/setup worker tests optional snapshot and zone-settings behavior, denied/empty/stale results and onboarding save. Implement HealthKit boundary, installation guide, optional setup and repeatable settings entry.
4. Page worker improves Today/report/Insights using real history and the shared contracts, explicit empty states and visible primary actions; add focused UI/model tests.
5. Root integrates record end timestamps and validated delayed batches into live and saved history. Test foreign/duplicate/out-of-range/finished and persistence failure cases. Register new source files without UUID churn; build20.
6. Run integrated core/native/Watch boundary/replay checks, coordinated existing iPhone UI/screenshot checks and independent source review. Record any StoreKit environment-only exclusions separately. Verify protected build17/Vendor metadata.
7. Archive/export/audit signed phone+Watch candidate on SSD, validate/upload to Apple, verify actual TestFlight state before claiming availability. Update documentation, privacy notice if Health reads changed, feature evidence and source branch. Preserve all original untracked evidence.

## Completed checkpoint

All seven steps are implemented and verified for the documented software scope. Build 20 is VALID and IN_BETA_TESTING internally and externally with APPROVED beta review. Core checks 385, selected native checks 220 and selected UI journeys 13 passed across the integrated/correction runs; Watch doubles and delivery replay passed. Four StoreKit framework cases remain explicitly setup-blocked. Build17/Vendor were unchanged. Physical sensor/battery acceptance and the limitations in `docs/evidence/watch-insights-2026-11-05.md` remain separate.

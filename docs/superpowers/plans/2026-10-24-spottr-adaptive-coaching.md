# Spottr adaptive coaching delivery

Goal: decide when to communicate from observed form, personal rep timing, real rest and fresh Watch summaries; prepare the replacement Pi camera without touching its existing services.

Architecture: local deterministic one-second/rep-boundary policy → expiring generation-scoped event → current text display, later ElevenLabs audio consumer. Gemini receives bounded derived facts only for explicit conversation/report/plan requests. No provider polling in the live loop.

- [x] Public coaching policy and tests: previous five valid reps minimum; mean + max(sample SD, .25s); personal camera-history seed; separate exercise baselines; dedup/cooldowns/priorities.
- [x] Actual monotonic endSet→nextSet rest storage and report projection, legacy unknowns preserved; Tiger contract accepts new optional field.
- [x] Native event timing, pause/source/session cancellation and latched discomfort; clock-jump and history-seed regressions observed red before fixes.
- [x] Grounded Gemini facts include complete totals, actual tempo/rest and observed Watch aggregates, without raw streams or recovery/capacity inference.
- [x] Pi USB capture/forwarding adapter with explicit control, bearer authentication, capture IDs, freshness and lease tests. No deployment/camera claimed.
- [x] Combined core/server/Pi and native checks, independent immutable-tree review, fix important findings.
- [ ] Publish feature branch/PR and update issues #13/#22. Main foundation is already usable through PR #16.

Physical CV/Watch calibration, actual Pi camera/phone ingestion, provider cost/latency tuning and voice playback remain separate acceptance. ElevenLabs supplied value was rejected as api_key_id_used_as_api_key; actual secret value is still needed.

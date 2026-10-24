# Integration readiness — 24 October 2026

The single-owner native hackathon app keeps local history and deterministic reports. Provider adapters are implemented where listed below; live checks remain gated by actual configuration and explicit requests. There is no sign-in or cross-device cloud sync in this milestone.

Implemented: native Gemini chat, grounded summary/proposal UI, semantic validation, explicit plan selection, Keychain gateway settings and optional explicit workout sync. The runnable Node gateway includes actual Gemini REST and Tiger pg adapters, scoped snapshot/readback/observed scalar telemetry routes, and a bounded Snowflake SQL API check. All routine tests use offline provider/database doubles. Tiger migrations have not been executed, no paid request has succeeded and no gateway is deployed. The local gateway migration under server/migrations is the implemented narrow schema; integrations/tiger contains the broader analytics proposal.

| Track | Distinct later role | Next evidence needed |
|---|---|---|
| Gemini | Explain computed session/week facts; propose editable catalogue-only sessions | Actual grounded outputs for all three jobs; wrong-evidence/refusal/timeout cases; user-selected plan application and measured cost |
| Tiger Data | Operational workouts, native-cadence sensor/rep history and live queries | Executed pinned-version migrations, committed sample rows, replay/conflict checks, live-tail/delayed-refresh chart, query timings and measured storage ratio |
| Vultr | Small authenticated API and server-held provider credentials | Actual health/version + scoped request, failure/retry behavior, latency and cost; reuse one gateway rather than per-provider services |
| Snowflake API | Batch public-data/feature evaluation and reproducible benchmark tables | Actual SQL API statement/results with dataset/version and held-out evaluation lineage; consume Tiger exports rather than duplicate live ingestion |
| HRT | Short-horizon HR/recovery trend research | Confirm what HRT service/model actually supplies; participant/session-held-out baselines, error/coverage and abstention; no clinical capacity or scale claims |
| Presage | Explicit brief still-camera recovery check, distinct from Watch | One bounded physical measurement with quality/source and permission evidence; preserve the remaining service budget, currently described as roughly 50 minutes in the design |
| ElevenLabs | Cached short spoken cues with priorities | Actual audible synthesis, latency and interruption/stop behavior; deterministic local cue selection, no model request each frame |
| Delta | Development/prompt evaluation collaboration | Installed service, actual collaboration threads and judge cases; Codex work does not establish Delta use |
| UNO Q | Local side-camera preview and timestamped landmarks; edge inference if feasible | Actual board/phone transport, capture alignment, measured ARM/Linux inference runtime and disconnect behavior; frame forwarding is separately labelled |
| DEV / slides | Factual demonstration story | Verified feature/integration ledger, measured results and limitations; draft first, publication later |

See [Gemini boundary](../integrations/gemini/README.md), [Tiger proposal and sources](../integrations/tiger/README.md) and [gateway interface](../integrations/gateway/README.md). Text citing a valid fact ID still requires factual entailment review. Attribute points remain deterministic game progress, not measured physiology.

# Delta synthetic review packet

Status: **prepared, not run**. On 24 October 2026 at 20:34:01 UTC, Delta appeared in the CUA inventory but could not launch. No provider request, judge output, numerical result, thread, or collaboration evidence exists yet.

- `judge-request.md`: paste this complete self-contained packet into one Delta thread. Do not also send separate generation requests.
- `fixtures.json`: five synthetic cases; cues are hand-authored controls.
- `expected-controls.json`: author expectations. Keep out of the judge input.
- `run-record.json`: observed blocker, zero request count, input hashes, and offline structural preflight. Unknown evidence and stale generations in negative controls are intentional.

The preflight counts words and checks references/generation equality; it does not judge the meaning of a cue. After a real review, save the verbatim final response and actual UTC/model/provider/thread metadata in a new run record. Retain this blocked record. A human must review the judge against the expected controls. Do not turn this tiny fixture set into a blanket product-safety or superiority claim.

See ../../../docs/delta-workflow.md for the run procedure and evidence boundary.

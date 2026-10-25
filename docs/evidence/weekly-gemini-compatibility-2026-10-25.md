# Live weekly Gemini compatibility — 25 October 2026

**One synthetic weekly request completed against the real Gemini provider and passed the existing output contract.** This was a local CLI → authenticated loopback gateway (`127.0.0.1:8847`) → Google check, separate from the [native fixture approval interaction](coach-week-approval-ui-2026-10-25.md). It was not public HTTPS or a live native weekly UI test.

The request began at **03:58:45.889 UTC** and completed at **03:58:49.249 UTC**. It used model `gemini-3.5-flash-lite`, a 20-second provider timeout, 4,096-token output ceiling and a one-attempt limit. Both provider and client returned **HTTP 200**, with provider finish reason **STOP** and no schema validation issues. Provider latency was **3,235 ms**; client elapsed time was **3,360 ms**. Reported usage was **1,399 prompt +1,144 candidate =2,543 total tokens**. No monetary cost was calculated.

Input was synthetic: “A short week please,” empty conversation, no support equipment and one fact, “No recorded capacity.” The calendar requested three available offsets (0, 2, 4), starting 25 October in `Europe/London`. Output contained seven ordered dates: workouts on **25, 27 and 29 October**, four rest days, three canonical exercises per workout, matching units/limits and only the supplied fact ID. Guidance IDs were `nhs-adults-19-64`, `nhs-strength` and `uk-cmo-activity`.

This demonstrates schema compatibility for this packet. Fact-ID membership does not establish appropriate quantities or measured ability. Generated language about gradual activity and general guidance is not evidence of progression, recovery, clinical suitability or personalised safety. No plan was approved, executed or saved by this CLI check; physical acceptance and broader output-quality evaluation remain separate.

The original local setup failed its PID-identity guard **before sending any provider request**. Corrected packet v2 made **one** actual provider call, with no retry. Tiger was disabled. `stopped.json` records operator cleanup at **03:59:07.474 UTC** and `providerCalls: 1`; subsequent read-only inspection found no recorded PID or listener on 8847. Offline contract revalidation also passed; retained source hashes still matched.

Sanitized provenance (SHA-256; private raw receipts retained, not published):

| Artifact | SHA-256 |
| --- | --- |
| Synthetic request | `863d112e13fb9436dffbc561c0514518eae6b0e405efe4230041a90e1235b54d` |
| Provider receipt | `1682adfcd9794d7902f4c725aa1d121ea408415cbe3b527d4422c3a5e768dba2` |
| Client receipt | `f1f8314653b93c754fb8bf7eb4f04bc754f355a7733484e0da1f423f2dadef10` |
| Cleanup receipt | `df445f53a03cee94ce34d79d6a47c23677713228d3a19d9621b10c826359d2f8` |

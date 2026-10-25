# After the hackathon

Deferred scope requested on 25 October 2026. These are ideas and follow-up gates, not completed features or release promises. The immediate priority is the reported TestFlight build-5 onboarding crash and a stable demo of the existing workout flow.

| Follow-up | Current boundary and next step |
| --- | --- |
| Running | Not an implemented running tracker. Design recording, pause/resume, distance/pace and permission behavior separately from the existing strength/manual workout flow. |
| Workout zones | Zone definitions and presentation remain to be designed and tested against valid sensor inputs. Missing readings stay missing; no inferred medical readiness or unvalidated capacity claims. |
| Watch complications ([#122](https://github.com/NakkiV7/oxhack-team/issues/122)) | Deferred. Any widget/source/signing drafts need root review before integration, App Group/profile changes, archive auditing and actual Watch installation. A draft does not establish a working complication. |
| Full cloud accounts ([#116](https://github.com/NakkiV7/oxhack-team/issues/116)) | The MVP has an optional local display name, not a cloud account. Authentication, per-user data isolation, account deletion, recovery, retention and spending controls need a separate design. Existing single-owner gateway access is not multi-user identity. |
| Delta evaluation | Prepared rubrics/authored controls are evaluation inputs, not generated results or evidence of Delta use. Run the actual review later and retain its raw outputs and limitations. |
| Physical Watch verification ([#7](https://github.com/NakkiV7/oxhack-team/issues/7)) | Human verification is deferred: real pairing, permissions, sensor freshness, controls and saved reports must be checked independently of simulator/software tests. |
| Extended Watch sensors ([#102](https://github.com/NakkiV7/oxhack-team/issues/102)) | Prefer the separately scoped Presage route for the next physiology investigation. Extended Watch capture remains follow-up work; existing sensor software does not establish physical acceptance. Presage still needs explicit opt-in, verified data/egress boundaries and actual acceptance; it is not a substitute for missing readings. |
| Real exercise lesson clips ([#53](https://github.com/NakkiV7/oxhack-team/issues/53)) | Await the user’s recordings for all 19 exercises. Existing guide graphics, filming instructions and local import support do not mean real demonstrations have been filmed or validated. |

The deferred Watch drafts are preserved with a hash manifest in ignored `.local/deferred-watch-complications-20261025/`; they are absent from the active MVP project. Retain other unmerged draft sources and private implementation plans for root’s review. Do not discard them or present them as enabled features. Resume each slice with a narrow agreed contract, behavior-first tests and separate software, provider and physical acceptance evidence.

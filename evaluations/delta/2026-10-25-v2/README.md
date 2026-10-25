# Cue contract v2 — prepared, not run

Prepared 25 October 2026 after the [v1 Codex review](../../codex/2026-10-24-cue-review/) disagreed about “Stop now and rest.” At preparation, zero v2 review requests had run; all candidates remain authored controls. A subsequent separate [Codex bootstrap calibration](../../codex/2026-10-25-cue-calibration/) reviewed only the six development pairs. Delta requests and held-out judge requests remain zero. No runtime prompt, policy, voice behavior, model or provider configuration changed. The original five cases, raw review, expected answers and recorded hashes remain immutable.

## What changed

The [action contract](action-contract.md) makes Stop and rest separate instructions. Under `stop`, the positive cue is Stop only; adding rest is rejected. Rest cannot add Stop or a mandatory restart. A single Stop action may be expressed negatively (“Do not continue”) without becoming two actions. The contract also specifies delivery-before-wording, unsupported evidence, note injection, expiry and caller cancellation limits. It describes a deliberately narrow evaluation subset; it is not a claim that all deployed cues meet this text template.

| Split | Pairs | Decisive preferred A / B | Identical tie | Neither deliverable |
| --- | --- | --- | --- | --- |
| Calibration (`development.json`) | 6 | 2 / 2 | 1 | 1 |
| Held-out (`held-out.json`) | 10 | 2 / 2 | 1 | 5 |

A/B is a fixed counterbalanced placement of authored valid/invalid controls, **not two prompt versions**, random allocation or a positional-bias estimate. The independent unit is the case; its two candidates are paired alternatives, not independent replications. The packet has 16 pairs / 32 candidate verdicts. It is curated and too small for population accuracy, confidence intervals or safety claims. Extra neither-deliverable held-out pairs check distinct delivery states rather than inflate the positive-side balance.

“Held-out” means distinct from calibration and never submitted to a judge or used to select/revise a prompt. The same author prepared both sets, and repository readers can see them; they are not a secret independent test sample. Keep the held-out request and answer key away from the calibration judge. If a future judge/author already inspected the held-out cases, record that exposure and call the next use a regression check, not unseen evaluation. Consuming them prevents reuse as an untouched holdout after revisions.

## Operator handoff

1. Read the contract and verify `manifest.json` and `preflight.json`. Keep [author expectations](expected-controls.json) out of judge input. Resolve any human objection **before** sending; create a new version for contract changes rather than rewriting historical results.
2. After the separate [Delta availability/agreement/account/provider gates](../../../docs/delta-workflow.md), use one explicitly authorized thread/turn with [the calibration request](judge-request-development.md). It is self-contained and prohibits tools, files, agents and follow-up calls. Capability restriction is an instruction, not an enforced sandbox; record any observed tool access or leakage and invalidate that run as blinded review.
3. Save the verbatim response first, plus actual UTC send/completion times, provider/model/settings (or `not exposed`), thread ID/link, errors and observed tool use. Retain the current prepared record; add a separate uniquely named result. A blocked attempt records zero successful reviews, not a judge score. Do not switch models, retry, expose credentials or share publicly automatically.
4. Compare all 12 calibration verdicts and six pair choices with the key. Human-review every disagreement, false delivery and apparent pass. Preserve both judge and author readings; do not silently correct the answer key to improve agreement. No runtime prompt revision is requested by this packet.
5. Freeze the rubric/instructions and the human calibration decision before any separately authorized [held-out request](judge-request-held-out.md), in a fresh thread without calibration history/key. That later run has 20 verdicts and ten pair choices. Do not send both requests in the current bounded calibration turn, tune on held-out results or count another viewing of the same case as independent validation. If calibration causes a contract revision, version it and record the change before exposing holdout data.
6. Report raw counts by split: expected-deliver disagreements, expected-reject/discard false deliveries, discard/reject confusions, pair disagreements and invalid/missing results. Missing or malformed outputs remain missing, never implicit passes. Separate author-key agreement from human-adjudicated results. No average style score or “safer/better” headline is justified by these authored controls.

## Files and source boundary

- `development.json`, `held-out.json`: fictional caller state, observed/policy facts, deliberate untrusted notes and authored A/B text.
- `action-contract.md`: frozen action, delivery and evidence rubric.
- `judge-request-*.md`: exact self-contained inputs; no expected verdicts.
- `expected-controls.json`: human-review starting key, not ground truth or judge output.
- `run-record.json`: prepared status only; unknown model/account/thread fields remain null.
- `preflight.json`, `manifest.json`: structural checks and exact input/source/historical-file hashes. Structural checks cannot decide semantic action preservation or entailment.

Source inspection: [CoachingPolicy](../../../Shared/Core/CoachingPolicy.swift) separates discomfort Stop from rest reminders and form/pacing; [TrainingStore](../../../Native/iOS/TrainingStore.swift) creates six-second ordinary events and non-expiring Stop events, cancels on inactivity and starts voice off for a new workout. [VoiceCuePlayback](../../../Shared/Core/VoiceCuePlayback.swift) gates session/generation, active/rest, mute, issuance/expiry, duplicates and priority; [bridge](../../../Native/iOS/CoachingVoiceBridge.swift) and [local playback](../../../Native/iOS/LocalVoicePlayback.swift) preserve that identity and cancel the current utterance. Exact inspected bytes are in the manifest. Source inspection is not a new runtime test result.

Runtime gates still require actual pause/mute/new-workout/source-change/foreground and late-callback tests, plus physical audio-route/overlap acceptance. These fixture probes cover stale session/generation, expiry equality, mute, paused/inactive context and lower-priority interruption. They do not exhaust future timestamps, replayed IDs, every cancellation race or real sensor validity. Stop remains visible in the app when appropriate even if audio is suppressed. No physiology, readiness, clinical or exercise-accuracy promise is authorized.

Design assistance used the local experimental-design skill for paired units, counterbalancing and holdout separation. This is a review packet, not a randomized study, power calculation or scientific result. No new framework, production validator or provider call was added. No real Delta usage or prize eligibility is established.

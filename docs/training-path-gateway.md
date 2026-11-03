# Training path: gateway routes

Three authenticated routes on the team gateway let the iPhone app use Gemini for the training path and camera coaching
without trusting it. The app builds every request from its own rules, the gateway constrains Gemini's JSON to that
request, and the app validates the reply again before using it. Builds on the Core logic in
[training-path-core.md](training-path-core.md).

| Route | Request (built by the app) | Gemini returns | Checked on the gateway | Checked again in the app |
| --- | --- | --- | --- | --- |
| `POST /v1/path-proposal` | `PathProposalRequest`: goal, survey answers, the usable exercises with their capability, allowed prerequisites and maximum target, the allowed starts and the rule's start, and optional repair errors | 4–6 nodes, start, goal node, route, wording | ids are usable exercises, links are allowed, start is allowed, the goal movement is included, the goal node is the top of the main chain, at most one optional node, targets within bounds, no links in text | `PathProposalContracts.path` bounds the start by placement, marks earlier steps "not required", replaces a broken route, then runs `TrainingPathRules.validate` |
| `POST /v1/attempt-cue` | `AttemptCueRequest`: the frozen contract, the baseline median and count, the coaching style, and facts with ids | action, one sentence, cited fact ids | the exercise has a camera tracker; `maintain_target` only when the baseline already meets the target and `cue_target` only when it does not; only numbers that appear in the facts (and counting words up to five); cited ids exist | the same rules in `AttemptCueContracts.cue`; on any failure the loop uses its deterministic cue |
| `POST /v1/attempt-explanation` | `AttemptExplanationRequest`: the contract, the computed classification, and facts about the result | two or three sentences, cited fact ids | grounded numbers, cited ids, no links | the same rules in `AttemptCueContracts.explanation`; it never changes the result |

## Exercise-generic

The gateway reads exercises from `Shared/Core/ExerciseCatalog.swift`, the file the app ships, so a new catalogue entry needs no
server change. Cues and explanations accept any exercise with a camera tracker; today that is squats and push-ups. An
exercise without a tracker is refused before Gemini is called.

## No automatic paid retries

`PathGenerator.generate` makes one Gemini call. If the reply fails validation it returns the catalogue path for the same
answers, labelled as the catalogue path, together with the reasons in `repairable`. The Skills screen can offer the
person one "Ask Gemini to fix it" request that sends those reasons back. Provider errors also return the catalogue path,
with nothing to repair.

## Live check

One live `gemini-3.5-flash` path proposal through a local gateway on 25 October 2026 returned 200 in about 19 s. It
passed the structural checks but ended the path at squats with two steps after it. That exposed a missing rule: the goal
node must be the top of the main chain. The rule is now enforced on the gateway and in the app, and the recorded plan is a
regression test (`aRecordedGeminiPlanThatStoppedEarlyFallsBackWithARepairableReason`). The follow-up live calls were
refused with 429: the local key is on Gemini's free tier, which allows 20 requests per model per day. No live cue or
explanation has run yet; both are covered by tests with a fake provider.

## Deployment

Merging does not deploy. The hosted gateway picks up the routes when the primary chat redeploys it. The app does not call
these routes until the Skills screens and the camera hook-up land.

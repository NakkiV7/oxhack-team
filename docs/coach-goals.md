# Goals in Coach and reports

The profile’s selected training goals and desired weekly training days now reach Coach chat, workout proposals, session summaries and weekly summaries. The visible context line, for example **Mobility · 4 days/week**, shows the preferences being supplied. These are self-selected intentions; game points and challenges remain game progress, not physical capability measurements.

## Explicit context

`SpottrRoot` passes the optional profile to `CoachView` and `WeeklyProgressView`. Progress passes it through `SessionReportView` and both `CoachSummaryCard` initializers. Each Coach model receives the profile on appearance; no Coach view or model loads a separate profile store.

`CoachGrounding.facts(history:profile:)` adds one deterministic `training-goals` fact, with sorted goal names and the weekly target. A missing profile adds no preference fact, preserving existing callers. The request schema and exercise catalogue are unchanged.

Changing goals or the weekly target cancels the view’s pending task and invalidates the model generation, proposal and summary. Coach also clears the proposal selection. Late replies from the previous preferences are discarded. A name-only change does not trigger this cancellation. Previously approved plans remain user-approved plans; changing preferences does not automatically replace them.

## Sharing

Opening Coach, viewing reports and editing a profile do not start a provider request. Send, Propose and Generate summary remain explicit actions. Their disclosures include selected goals and the weekly target when a profile is supplied. The optional profile name is omitted from the derived facts and automatic request context. A person can still choose what to write in their message.

**Propose a workout** also supplies the current composer draft and up to the 20 most recent conversation turns. The draft is captured on the explicit tap, trimmed and limited to 4,000 characters; an oversized draft produces an instruction to shorten it before any transport call. An empty draft preserves the existing proposal action. The gateway client's existing byte budget may trim older conversation further. Editing the composer sends nothing, and requesting a proposal neither appends the draft to chat nor replaces an approved workout. Selection, approval, saving and starting remain separate user actions.

Conversation and draft text remain untrusted user/provider context. Self-reported statements do not become recorded sets, Watch readings or additional verified facts. Existing generation, support and fact-ID validation still applies. Cancellation before a scheduled proposal begins prevents transport; cancellation or context changes after dispatch reject a late response.

Existing recorded-set, source and Watch-summary boundaries remain in place. This integration does not send raw video or sensor streams, establish health status, or infer physical capacity from game scores.

## Verification — 24 October 2026

- Core API RED demonstrated the missing profile input. The Core grounding suite then passed all 9 tests, and the full Core suite passed.
- Native `CoachFlowTests` passed all 6 methods. New offline cases inspect synthetic request bodies for chat, proposals and both report kinds; verify that goals/weekly target are included and the optional name is absent; reject late responses after either preference changes; and preserve a valid response after a name-only change.
- UI behavior RED reached the saved profile and failed on the missing Coach context. The initial Stepper selector issue was corrected before that behavior RED.
- Final simulator run passed **8/8: 6 native tests and 2 Coach UI tests**, with no warnings, in 44.9 seconds. The UI flow saves Mobility and four days through Profile, then verifies the context in Coach and the weekly report without sending a request. Evidence: root-run result `20-19-26…1393a173`.

All request tests use injected offline responses. This evidence does not establish live Gemini output quality, deployment, device acceptance or TestFlight availability.

The exact staged source snapshot also passed the same eight native/UI cases (result `test_sim_2026-10-24T20-22-53-235Z_pid4129_9ac7e7e9.xcresult`) and its full shared-core suite; no provider calls were made.

## Draft and conversation proposal check — 25 October 2026

The combined native RED at 01:48:44 UTC failed on the missing `propose(message:history:support:)` API (`test_sim_2026-10-25T01-48-44-900Z_pid4129_c969a536.log`). Offline request-boundary cases cover trimmed draft plus prior conversation without replacing the saved workout, rejecting 4,001 characters before transport, accepting 4,000 trimmed characters with only the latest 20 turns, rejecting a late cancelled proposal, and preventing an already-cancelled scheduled request. The final native run passed all 16 Coach cases within 37 focused app checks, without warnings (`test_sim_2026-10-25T01-58-05-394Z_pid4129_253efbf1.log`). Actual composer-button acceptance remains pending; no new provider request is part of this change.

# Delta coaching review workflow

Checked 24 October 2026, 20:35 UTC. **Preparation is ready; actual Delta use is blocked.** No model request, account/provider verification, agent thread, judge score, or collaboration result is claimed.

## Observed availability

CUA listed Delta (`com.zed-industries.delta`) as not running, but attempts to open it by name and bundle ID returned `Invalid app`. Finder showed no Delta in either Applications folder. A bounded filesystem check at 20:34:01 UTC found no Delta-named entry in `/Applications`, `~/Applications`, or `~/Downloads`; `/Volumes` contained only Macintosh HD. This establishes the checked local state, not whether Delta was previously installed elsewhere. Safari and Chrome tabs were preserved.

The official [download page](https://delta.dev/download) offers an Apple Silicon ZIP. It explicitly makes downloading agreement to both the [Zed Terms of Service](https://zed.dev/terms) and [Delta Early Access Agreement](https://delta.dev/early-access). The task forbids agreement acceptance without the user's action-time confirmation, so no download began. The next step is the user's review/confirmation or restoration of an already available official app. No new credentials, grants, subscriptions, or login were created.

## Published terms relevant to the prize plan

The Early Access Agreement, updated 5 August 2026, limits use to testing/feedback and excludes product-development research/commercial use (§3); requires written approval for public announcements (§4); assigns Feedback to Zed (§5); retains tester-data ownership while licensing service processing (§6); and caps liability at $100 (§13). It says no training without opt-in; external-provider connections follow that provider's agreement. The general Terms, updated 2 March 2026, address output ownership, data processing, activated subscription/metered charges, and arbitration with a 30-day opt-out.

These are factual clause summaries, not a determination of prize eligibility or how separate organizer/vendor permissions apply. Resolve any specific prize permission before publishing Delta evidence.

## One bounded review when available

1. Open the official Delta app. Check the existing account and Settings > LLM Providers; record the actual provider/model label without copying credentials or account identifiers. An unavailable app does not establish that a provider key is missing. Stop if an agreement, new permission, credential, upgrade, or CAPTCHA is required. [Provider documentation](https://delta.dev/docs/agents/models-and-providers)
2. Open `/Users/scsoc/dev/AI PT` as the Spottr project. Confirm the selected checkout and branch in the UI. Delta's isolated project threads may fetch the remote and start from the configured/default branch; they do not automatically include dirty primary-checkout work. This review is self-contained and must not modify either checkout. [Thread documentation](https://delta.dev/docs/agents/threads)
3. Create **one** thread named `Spottr synthetic coaching review v1`. Use an already configured model. Paste the complete [judge request](../evaluations/delta/2026-10-24/judge-request.md) once. It prohibits tools, repository reads, edits, commands, spawned threads, and follow-up calls. Do not attach `.env`, real workout records, personal details, or biometrics. The input includes only authored synthetic workout facts and deliberate bad responses.
4. Record UTC send/completion times, exact UI model/provider, exposed settings (or `not exposed`), the full final response, errors/fallback notices, and thread ID. One user-submitted turn is the limit; do not retry or change models automatically. If the provider cannot run, record that outcome and leave it pending.
5. Compare its per-candidate verdicts against [author expectations](../evaluations/delta/2026-10-24/expected-controls.json). Review stop priority, rejection of stale generations, missing evidence, instruction injection, and an identical-answer tie. The automated preflight checks only word counts, reference membership, and generation equality. No judge result exists yet.
6. Keep thread visibility private. Copy an existing private position/thread link if available without changing access; do not enable Anyone with the link or invite others. Delta documents that copying a private link does not itself grant access. [Collaboration documentation](https://delta.dev/docs/collaboration/collaborate-thread)

## Evidence and limits

The [packet directory](../evaluations/delta/2026-10-24/) contains the wording prompt, five synthetic cases, blinded A/B controls, expected outcomes, and a retained blocked-attempt record with SHA-256 input hashes. Cues are hand-authored fixtures, not Spottr/Delta generations. The packet was prepared in Codex; it is not proof of Delta collaboration.

After a real run, save a new result alongside the blocked record. Preserve the raw answer before adding human verdicts or revisions. A successful single review would establish that one Delta-assisted prompt review happened. It would not establish better coaching, medical safety, deployment, accurate sensors, or runtime freshness/cancellation/playback behavior. More extensive evaluation requires separately authorized runs with counterbalanced order, held-out cases, and human review as described in [the evaluation plan](delta-prompt-evaluation.md).

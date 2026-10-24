# Spottr team delivery plan

**Goal:** Publish a reproducible native app foundation to NakkiV7/oxhack-team and complete the shared app/integration work while teammates refine voice, landing and exercise CV.

**Architecture:** Local SwiftUI/Watch session and reporting remain independent of the network. One Node gateway holds provider credentials and supplies grounded Gemini conversation, summaries and catalogue proposals; explicit selection precedes saving a plan.

**Constraints:** No new images. No CI/CD. Never commit credentials, local histories or build products. Preserve existing remote history. Use feature branches and PRs. Reuse existing simulators. Provider calls are bounded smoke tests after offline checks.

## Delivery

1. [x] Inspect remote access/history and native verification. Existing main contains only .DS_Store; authenticated CLI has WRITE permission. Connected GitHub plugin lacks access, so use gh fallback. Native baseline: 12 tests pass.
2. [x] Finish recorded rep tempo; retest shared core. Keep teammate CV ownership explicit.
3. [x] In parallel build Gemini gateway, native coach UI/client and collaborator documentation/bootstrap. Verify timeout, cancellation, missing config, structured rejection and explicit plan selection without paid calls.
4. [ ] Add ignored local config and setup helpers; inspect already signed-in provider dashboards and use existing credits where available. One bounded live Gemini test when configured. Tiger quickstart is the account/service entry point; actual connection and migrations are separate evidence.
5. [ ] Inspect/install downloaded Delta and prepare a real prompt/evaluation collaboration workflow. Never claim Codex work as Delta evidence.
6. [x] Create assigned GitHub issues with scope, branch/files, dependencies and acceptance. Voice+landing MishaGitnik; push-up azhar-rafiq; squat NakkiV7; everything else omariosc.
7. [x] Run combined core/server/native checks, review immutable patch, fix important findings. Preserve original remote history when integrating foundation branch.
8. [ ] Push feature branch, open PR, attach it to this chat and publish exact status/remaining issue links. Make getting-started path immediately usable by collaborators.

## Remaining ownership

Teammates: David Goggins ElevenLabs voice and cue integration; landing page; push-up CV validation/refinement; squat CV validation/refinement.

Omar: Gemini chat/reports/plans; shared app/progression/reporting; Watch physical sensor validation; Tiger ingestion/analytics; Vultr deployment; Snowflake batch analytics; HRT adaptive prediction and public-data evaluation; Presage final recovery check; Arduino transport/display; Delta judge workflow; demo/deck/DEV. Each gets an open issue until its acceptance evidence exists. No integration is called live solely because a schema or adapter exists.

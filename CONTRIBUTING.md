# Contributing to Spottr

Work in [NakkiV7/oxhack-team](https://github.com/NakkiV7/oxhack-team). Use a feature branch and a focused PR for every change. There are no GitHub Actions, deploy workflows or other CI/CD in this project; each author records local validation in the PR.

## Before editing

1. Read [README](README.md), [ownership](docs/TEAM.md) and the [current evidence ledger](docs/integration-readiness.md). Use the roadmap for acceptance criteria; historical status text may predate merged features. Claim the relevant issue or agree the scope with its owner.
2. Inspect `git status` and preserve other work. Start from the agreed integration branch, then `git switch -c feat/short-description` (or `fix/short-description`). Do not assume an in-progress branch is merged into `main`.
3. Agree file boundaries. Push-up and squat work both touch shared pose/counter code; one owner edits shared files at a time. Prefer exercise-specific fixtures and small changes over duplicating the model pipeline.
4. Use behavior-first development: reproduce the missing behavior with a failing test, implement the smallest fix, then run the relevant checks. On Omar's Mac, application work follows `/Users/scsoc/.claude/TDD.md`; model training/evaluation also follows `/Users/scsoc/.claude/AI.md`. Those personal files are not prerequisites for teammates cloning this repository.

## Local verification

```bash
./scripts/bootstrap.sh
cd server && npm ci && cd ..
./scripts/check.sh
```

`check.sh --static` checks shell/Ruby/JSON/JavaScript and Pi Python syntax. `check.sh` also runs SwiftPM, offline gateway and Python companion tests. Neither command builds the native app, contacts a provider, proves physical sensor behavior or deploys anything. Run the relevant native tests with Xcode on an existing simulator. Use fixtures/fake adapters for routine tests; explicitly label any opt-in live request and its usage.

For a PR, record the command, result and exercised path. State unavailable checks plainly. A simulator model test is distinct from hand-labelled video rep accuracy; a Watch transport test is distinct from physical HealthKit/Core Motion recording; configured secrets are distinct from a successful live request.

## Generated project and assets

`scripts/generate-project.rb` owns `Spottr.xcodeproj`. Regenerate locally after adding/removing Swift or resource files. Omit unrelated generated project/signing changes from feature PRs; Omar regenerates the final project after integrating source changes. If the generator itself must change, assign one owner and describe it in the PR. Never resolve generated project conflicts by deleting another feature's source/resource references.

Use the merged 19 exercise icons, six phase illustrations and system icons. Coordinate additional assets with the integration owner; illustrations do not replace user-filmed demonstration videos. Preserve the pinned MediaPipe URLs/hashes and bundled model provenance. Do not commit `Native/Vendor`, build output, simulator data, local history, private video imports, `.env` or credentials. Release privacy manifests and provisioning are separate from an accepted TestFlight build.

## Manual smoke test

Run the affected subset and note simulator versus physical device:

- Launch with no provider credentials; open Today, Progress, Skills and Coach without an invented history or reading.
- Start a push-up or squat session. Deny/unavailable camera should leave manual/import controls usable. Import an eligible test clip; verify pause/resume, tracking loss and end-set cancellation. Counts require a complete valid cycle.
- End a set; choose or skip reps-in-reserve and a stop reason. Finish, reopen the app and find the saved session/report. Discomfort must not prompt continued effort.
- Log a non-camera exercise manually; confirm reps versus seconds. Time a hold, pause, finish and save; progress must use the appropriate unit and source.
- Save profile goals/weekly target and verify the Coach/report context line. Name-only edits must not share the optional name; goal changes must invalidate stale coaching. Test unavailable gateway, timeout, malformed evidence and cancellation. Keep the current plan unless a user explicitly selects and applies a valid proposal; run saved plans with manual reps/hold timing.
- For Watch changes, test the paired simulator transport first, then explicitly start a physical recording with permission. Missing/stale data stays missing; do not manufacture HR or motion on a simulator.
- For voice, first verify opt-in/mute/lifecycle behavior with fake playback, then audible playback and interruption on the phone. No audio acceptance is implied by fake synthesizer tests. For Pi hardware, test disconnection and lease expiry; the recorded USB disconnect remains a physical blocker.

## PR checklist

- One behavior/scope, linked issue, owner and clear test evidence.
- No secrets, private biometric data or token-bearing screenshots/logs. Inspect the diff before pushing.
- No automatic plan changes, hidden paid fallbacks or per-frame provider calls.
- Public claims match the [current evidence ledger](docs/integration-readiness.md); distinguish synthetic provider checks from native/network and physical acceptance.
- README/setup instructions updated if the contributor path changes.
- No CI/CD or unapproved external deployment. Deployment packaging exists under `deploy/`; creating resources, spending credits and publication require their separately agreed scope. Coordinate shared contracts, generator and dependency versions with the integration owner.

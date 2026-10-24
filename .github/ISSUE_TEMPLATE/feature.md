---
name: Feature / integration
about: Claim a focused feature with an owner, file boundary and verifiable acceptance
title: ""
labels: ""
assignees: ""
---

## User behavior

What should the person be able to do, and what happens today?

## Owner and branch

Owner: @
Branch: `feat/`
Roadmap track:

## File boundary and dependencies

List files/contracts you expect to edit and any other owner you must coordinate with. Omar integrates shared generator/project changes. Keep landing-page work separate from native source.

## Acceptance

- [ ] A focused failing behavior test exists before implementation.
- [ ] Relevant offline checks pass; command/result recorded in the PR.
- [ ] Affected manual smoke test passes, with simulator/physical/live/replay stated.
- [ ] Failure, cancellation and missing-data behavior are covered where relevant.
- [ ] Evidence supports any provider/device claim; configured secrets alone are insufficient.
- [ ] No CI/CD, secrets, personal biometric data or new generated images included.

## Evidence needed

Describe the exact device/request/fixture and the expected observable result. Do not include keys, private data or token-bearing screenshots.

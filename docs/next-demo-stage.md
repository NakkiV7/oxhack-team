# Next demo stage

Build **0.1 (5)** is the current TestFlight release. A teammate confirmed a crash after onboarding in this build; the cause remains unresolved. The exact frozen build-5 source passed one Release-optimized simulator onboarding case (`06:25:01_f38611e1`), which does not establish physical-device acceptance. App Store Connect feedback was empty at 06:23 UTC. Investigate the actual device termination before claiming demo readiness.

Later source changes need a new reviewed archive and distribution check before TestFlight testing. No build 6 is distributed. See [the issue map](ISSUES.md) for service and teammate ownership.

## Work in parallel

| Slice | Owner | Acceptance before release |
| --- | --- | --- |
| Chat and form keyboard dismissal [#119](https://github.com/NakkiV7/oxhack-team/issues/119), [#120](https://github.com/NakkiV7/oxhack-team/issues/120) | Omar | Merged through `66ed039`, unreleased. Simulator Done/drag checks preserve drafts and keep Save/Send explicit; physical iPhone acceptance remains. [Evidence](evidence/form-keyboard-dismissal-2026-10-25.md). |
| Goal icons and rewards [#121](https://github.com/NakkiV7/oxhack-team/issues/121) | Omar | Current uncommitted/unreleased work: four bitmap goals, protected versus actual training days, two freezes and next-day two-hour bonus windows. Focused core/native checks and explicit Save/Cancel UI passed; physical acceptance and a reviewed release remain. [Evidence](evidence/training-rewards-2026-10-25.md). |
| Watch complications [#122](https://github.com/NakkiV7/oxhack-team/issues/122) | Omar | Three WidgetKit families; minimal progress transport; App Group, target embedding and matching signing profiles; native rendering and Watch installation. |
| Voice [#1](https://github.com/NakkiV7/oxhack-team/issues/1), landing [#2](https://github.com/NakkiV7/oxhack-team/issues/2), squat [#4](https://github.com/NakkiV7/oxhack-team/issues/4) | Assigned teammates | Integrate scoped reviewed changes; preserve opt-in capture, bounded provider use and cancellation. See [team boundaries](TEAM.md). |

## External and physical gates

- **Pi:** the replacement LifeCam delivered **600 frames over 60 seconds** in a bounded capture check, then capture stopped. Companion migration with fresh per-device TLS is in progress; phone re-pairing, ingestion and exercise accuracy remain unaccepted. Elgato work was cancelled after repeated USB disconnects; their physical cause is unproven. The private migration backup and other Pi services are preserved. [Earlier Elgato evidence](../hardware/pi/EVIDENCE-2026-10-24.md) is historical.
- **Phone networking:** finish the prepared Vultr deployment after the pending spend/SSH confirmation. No Cloudflare relay is authorized. The existing domain needs no new purchase. No public gateway is live yet.
- **Watch:** actual pairing, HealthKit permission, fresh heart rate/energy/motion, controls and save acceptance remain distinct from simulator tests. Missing sensor data stays missing.
- **Providers:** Gemini has bounded synthetic live responses; physical HTTPS remains. Tiger strict-TLS persistence, Snowflake live SQL, Presage measurement/egress and ElevenLabs synthesis need their recorded service gates. Delta evaluation and SDK provenance remain open. Do not describe planned or fixture-only integrations as live use.
- **Release:** freeze a coherent commit; test both existing simulators; audit the archive, resources, nested executables, entitlements and profiles; validate/upload and read back TestFlight processing. A Widget extension changes the old build-6 audit assumptions and must be explicitly accounted for.

Contributors should take one issue, use a feature branch, and include concise behavior and validation evidence in its PR. No CI/CD is needed. Use [the architecture and quick start](../README.md), [setup](SETUP.md) and [gateway configuration](../integrations/gateway/README.md); keep local keys out of commits.

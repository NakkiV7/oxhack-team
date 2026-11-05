# Spottr feature and release priorities

## Added in this foundation

- 32 distinct exercise entries, including 13 camera-supported styles. New camera choices check three-second lowering or a two-second pause. Six further movements use explicit manual/timed logging. Labels do not claim the camera verifies support stability, hand width or stance width.
- Faceless vector guides with highlighted joints, preserving existing skill-path identities and earned progress.
- Optional verified StoreKit membership infrastructure, restore and Apple redemption UI. Full beta access remains available. Requested prices are £10/month with an eligible 14-day trial and £200 lifetime; production activation and `SPOTTRTESTERS` are separate Apple gates.
- An accessible Cloudflare landing site with current local-candidate screenshots, abstract generated icons, support, privacy, terms and deletion instructions.
- Optional passwordless website accounts with a passkey plus mandatory Authenticator or single-use backup-code second factor. Training and Health data remain local to the app.

## Watch and reporting added in build 20

- Today now prioritises a real session action, weekly recorded work, a recent session report and optional Watch/Health setup.
- Reports calculate time-weighted heart rate, observed coverage and gaps, five optional maximum-HR zones, cumulative active energy, recorded work/rest and camera rep-duration variability. Pauses and restarted Watch recordings break chart lines.
- The Watch records windowed wrist acceleration/rotation summaries and persists bounded telemetry until the phone acknowledges saving it. An established workout keeps recording through a stale phone link; controls still require a current phone session.
- Optional read-only Health history includes resting/walking heart rate, SDNN HRV, VO₂ max, one-minute recovery, oxygen saturation, respiratory rate and current-day steps/distance. Every reading has a date/source; old readings remain separate from workout metrics.
- Onboarding and settings explain Watch installation and optional Health access. No age/max-HR default is invented and the user can enter a maximum or explicitly choose an adult age estimate.

## UI and Watch setup added in build 21

- Reused workout-style figures across onboarding and exercise previews, with a visible stable support for supported squats.
- Shared headings, action feedback, restrained transitions and a lifecycle-aware onboarding demonstration which stops for Reduce Motion or inactive/off-screen views.
- Clearer Today/Coach/Skills hierarchy, selected coach choices, adaptive report grids and an accessibility-size Insights menu.
- Optional local Watch-family question, phone-only exit and real pairing/install/reachability/companion-response milestones.
- Fresh nonce checks, bounded active polling, queue snapshots, separate data-arrival time and actual motion availability. Cached launch context cannot pretend to be new data.
- Shorter consumer copy and optional measurement/installation details, while retaining provenance, gaps and errors.

## Next quick wins

1. Favourites, repeat the last actual workout and a recent-exercises list to shorten setup.
2. Optional framing countdown, camera-position guidance and visible tracking-confidence recovery without repeating audio over itself.
3. An explicit post-set count correction that preserves original camera evidence and marks corrected totals as self-report.
4. Local workout checkpoints and a clear resume/discard choice after process termination.
5. Chosen training days, quiet-hours reminders and Watch rest-completion haptics.
6. A compact PDF report and richer CSV export chosen by the user, with observed coverage, zones and manual/camera provenance.
7. Optional dated weight entries with a rolling trend, keeping weight change separate from exercise-energy estimates.
8. Offline audio previews and more reviewed, normalized recordings for each original coach/style/event. Authoring credentials must work before promising ElevenLabs audio.
9. Accessibility presets for larger controls, reduced motion, stronger contrast and fewer simultaneous instructions.
10. An optional feedback bundle containing build/device, exercise and expected/recorded counts. Attachments must be explicitly chosen; no automatic health/video uploads.

## Watch priorities for the next device-testing pass

1. Compare simultaneous Watch and report readings, elapsed time, energy and pause behavior on hardware.
2. Exercise offline delivery, app restarts, queue overflow and denied permissions. The durable queue does not restore an unfinished phone workout after process termination.
3. Profile battery and storage during a long offline workout before changing telemetry sampling or persistence frequency.
4. Validate motion repeatability across wrists, Watch fits and exercises. Wrist acceleration is not body speed, range of motion or a form score.
5. Consider an observed post-set heart-rate recovery calculation only with sufficient timestamped readings and an explicit stationary recovery period. Existing Health recovery history is a separate Apple measurement.

## Measurement before more models

Use a consented, varied video set covering exercise, angle, clothing, lighting, mobility aids and temporary occlusion. Measure overcounts, undercounts, recovery time, observation coverage, latency, energy and thermal behavior. Keep a separate held-out acceptance set. A script passing synthetic landmarks does not establish physical accuracy.

Potential later on-device models include lunge, calf raise, bridge and hold-specific tracking. No HPC job or new training was started. Before training on AIRE, propose the exact model, data/permissions, evaluation protocol, expected benefit, deployment size and compute budget to Omar.

## Commercial and clinical gates

Create and verify App Store products, eligibility, subscription management and offer-code redemption; review device purchase/restore and refunds. App Store notices and a signed archive do not establish Apple approval. The beta must remain usable if products are unavailable.

Complete real phone/Watch movement and audio acceptance, airplane-mode tests, denied-permission flows, accessibility checks, long sessions and crash-resume tests. Validate passkeys/QR/recovery on real Safari devices and perform an independent security review before a broader account rollout.

For GP/social-prescribing use, obtain clinician-reviewed programmes, clear intended use, information governance and prospective evaluation. Pitch materials should separate implemented tracking from planned outcomes and clinical-effectiveness claims.

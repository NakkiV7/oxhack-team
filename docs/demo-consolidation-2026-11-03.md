# Spottr demo consolidation — 3 November 2026

Follow-up: [iPhone tracking recovery and complete side-camera removal](tracking-recovery-2026-11-03.md) supersedes the initial delivery's camera options and records the response to physical build-16 feedback.

## Current delivery branch

`codex/spottr-demo-consolidation` in `/Users/scsoc/dev/AI PT`.

The original tracked local work was preserved in `66d8075` before integration. The original binary diff and status inventory are in the ignored `.local/demo-consolidation-20261103/` folder. Unrelated screenshots, Playwright output and Finder metadata were not added to the application commits. Finder metadata was preserved in a named Git stash before the teammate branch removed its tracked copy.

Integrated sources:

- `origin/main` through `a016014`, retaining the newer local Full-pose, camera-recovery, preview/report and physiology-isolation work.
- `origin/nakki/app-demo` through `b8fdd2c`: personalised paths, path contracts, Insights and both offline rep-voice banks.
- `origin/nakki-squat-model` through `20f61e0`: squat web tool, later push-up feedback and supporting source.
- `origin/nakki/app-insights` was reviewed. Its final `c90c743` explicitly describes an uncompiled alternative UI reference and says not to merge the branch wholesale. The working Insights implementation from app-demo is retained; duplicate view/type definitions were not compiled into the app.

## User-visible changes

- Three-step guest onboarding now introduces achievable movement practice, with a direct Today → personal path entry.
- The personalised path works from the local catalogue without a gateway, retains its full challenge tree, and shows prerequisites and the current practice step. The step sheet keeps its primary next action visible.
- Path writes publish only after disk success. Failed autosaves preserve saved answers; unread original files survive survey edits until explicit path acceptance. Weekly quests refresh after changing the path elsewhere.
- Normal calendars show actual history only. Additional calendar samples are available only in explicit preview mode, with an example-history label.
- Native Arnold/Goggins rep recordings work offline. Rep audio yields throughout an active coaching cue, and retains mute/pause/background cancellation.
- Today → Demo studio offers the supplied squat and push-up movies inside the app. They are clearly prepared examples with their original overlays/narration, attribution and no training rewards. Example audio is off until enabled.
- Both web tools expose the same bundled Arnold/Goggins recordings without ElevenLabs requests. Unknown spoken feedback uses browser speech rather than synthesising paid audio. Counts expire; mute, pause, source changes and page exit cancel playback.
- Uploaded web videos play once and end with a summary. Replay stays distinct from live training. The squat/push-up counting thresholds were not retuned on the supplied annotated tutorials.

## Run the web tools locally

Dependencies were installed from each existing lockfile. The native Full-model resource was copied to each ignored `models/` folder.

```sh
cd '/Users/scsoc/dev/AI PT'
env -u GEMINI_API_KEY -u ELEVENLABS_API_KEY -u TIGER_DATABASE_URL -u TIGER_DB_ADDRESS PORT=3001 node prototype/pushup/server.mjs
```

In a separate terminal, use the same command with `PORT=3002` and `prototype/squat/server.mjs`. Open `http://localhost:3001` or `http://localhost:3002`. This explicit local demo command does not load old `.env` provider settings. The test servers were stopped after browser checks. No further Chrome testing is authorised in this run.

The browser interfaces remain local prototypes. The native iPhone app is the presentation's main experience. No new cloud deployment, paid-provider activation, private-data migration, Git push or TestFlight submission was performed.

## Verification evidence

Evidence is retained privately under `.local/demo-consolidation-20261103/`:

| Check | Result |
| --- | --- |
| Shared Swift core after branch consolidation | 104 XCTest and 202 Swift Testing cases passed |
| Gateway suite | 98 passed |
| Push-up web suite | 92 passed |
| Squat web suite | 66 passed |
| Shared web contracts/offline audio/cancellation | 15 passed |
| Native regression | 243 passed, `native-regression.xcresult` |
| Static checks | Passed: shell/Ruby/JSON/gateway/Pi syntax |
| Browser model/replay/audio checks | Both real models loaded; push-up one-pass summary and squat pause/resume exercised; bundled Goggins MP3 decoded in browser. Chrome testing then stopped at Omar's request. |
| Final native UI on the existing shared iPhone simulator | 4 passed: guest onboarding-to-path, Demo studio playback entry, calendar/report/weekly/research and the complete saved-path/map/prerequisite/list/tree workflow. `existing-iphone-ui.xcresult` |
| Signed phone build and install | 0.1 (16) built, signature verified, installed and launched on Omar’s paired iPhone. App/Watch versions match; Full model checksum matches; 99 MP3 clips and both example movies are bundled; SmartSpectra is excluded. |

RED evidence is retained for path write failures, unread-file protection, audio arbitration, missing bundled examples, guest navigation and ordinary-calendar samples. These checks validate software behaviour, not clinical outcomes or real-person counting accuracy.

## Simulator policy and coordination

Omar requested reuse of existing simulators. The temporary Spottr Demo QA device was shut down and deleted. The existing `Musalli-Test` device is now named `iPhone`, keeping UDID `BF27AFBA-FF1E-4484-A3BD-42916CEB1170`. Musallī was notified. The global and shared development instructions now prohibit new simulators except a temporary device strictly needed for specific-device screenshots, removed immediately after capture. Preserve shared apps/data and coordinate concurrent UI testing.

## Presentation

The [OneMedicalGroup storyboard](../presentation/one-medical-group-storyboard.md) covers the £125,000-for-30% proposal, a compact in-app demonstration and a proposed GP-practice pilot. It keeps the current movement-practice prototype separate from future referral/clinician workflows and untested patient outcomes. The historical hackathon deck is preserved.

Four unchanged native screenshots and their provenance are in [the dated captures folder](../presentation/captures/2026-11-03/README.md).

## Remaining physical acceptance

Rehearse squat and push-up sessions on the actual phone, with the intended framing and audible output. Confirm camera tracking, controls, counting and a saved report with an observer. Demonstration movies and automated fixtures are not substitutes for that acceptance. Watch physiology and live external providers remain optional, separate acceptance tasks.

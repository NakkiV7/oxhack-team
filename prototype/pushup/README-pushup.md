# Push-up Coach (prototype)

Counts push-up reps and checks posture from a webcam or a video, in the browser, with no training: Google's MediaPipe Pose Landmarker finds 33 body landmarks and simple angle rules do the rest. Easier variations (wall, incline, knee, standard) are included.

Optional extras:

- **Tutorial**: a how-to guide on the page with an example set (side view) run through this app's coaching overlay and spoken count. Footage: Cavemantraining, CC BY-SA 4.0, in `assets/`.
- **iPhone display**: the Mac is the camera, an iPhone in front of you shows the count, live video with the body-line drawing, gauges and history, and speaks the reps.
- **Workout timer and summary**: total workout time (frozen while paused), time per rep with the average and a slowing-down warning, a confirm step before **Stop**, and a summary over the video when you end the workout. Standard push-up is the default variation.
- **Phone remote control**: pause, resume and stop from the iPhone using a control code shown on the Mac page.
- **AI coach (Gemini)**: a short pep talk or tip every few reps, plus a Q&A box that answers only from official health pages (WHO, CDC, NHS, NIH) with citations. Questions and answers are shared between the Mac page and the iPhone.

Not a medical or form-certified tool: a 2D side view cannot judge elbow flare or scapular issues.

## Quick start (Mac only, about 3 minutes)

Needs Node 20.17+ and a Mac webcam (or any video of a push-up filmed from the side).

```bash
cd prototype/pushup
npm ci
npm run setup      # downloads the 9 MB pose model into models/
npm test           # offline behavior checks; no model download or provider calls
npm run ui         # open http://localhost:3001
```

Pick a variation, click **Start camera**, put the camera at your **side** 2 to 3 m away so your whole body is in frame. Step-by-step with the iPhone app and the coach: [docs/TUTORIAL.md](docs/TUTORIAL.md).

## Layout

```
pushup.mjs        pure logic: angles, variation thresholds, RepCounter (no DOM, tested in node)
client-workout.mjs owner-bound workout snapshots and explicit durable upload/retry
index.html        camera/video input, pose loop, overlay, feedback UI, coach panel
server.mjs        local server: static files, state/frames to the phone (SSE), coach, /ask
ask.mjs           guarded Q&A (official-source grounding, injection and leak filters)
profile.mjs       personal profile: baselines + small decision tree from past reps (pure, tested)
train.mjs         builds data/profile.json from data/history.csv (npm run train)
data/             history.csv (mock past workouts, committed), make-history.mjs (npm run history)
tiger.mjs         Tiger Data access: migrate, insert reps, read reps, session stats
db.mjs            CLI: migrate | load | stats (SQL in db/)
ios/              SwiftUI iPhone app (Xcode project)
scripts/          fetch-model.sh
assets/           tutorial video (Creative Commons footage with the coaching overlay)
test/             node:test unit tests
docs/             TUTORIAL, ALGORITHM (how it works + guardrails), TEST_PLAN
.env.example      optional GEMINI_API_KEY
```

## Personal profile (mock history)

`data/history.csv` is mock past workout data (300 reps, 10 sessions, labels good / shallow / sagging / fatigued) for developing and testing the training. `npm run train` writes `data/profile.json` (gitignored): usual elbow angle, body line and rep time, plus a small decision tree as if/then rules. This is the standalone browser prototype, separate from native Spottr. Its optional personal baseline rule only tightens the default form limits; counting keeps the default thresholds. The fitted tree is explanatory and is not used by the live counter.

`data/history-demo.csv` is a bigger mock history (3000 reps, 100 sessions) for demoing "enough data, training now". Regenerate with `npm run history:demo`; load it with `npm run db:load data/history-demo.csv`. It is mock: accuracy on it (about 100%) only shows the code works, because the generator wrote the labels.

### Tiger Data (your own database)

Rep history can live in Tiger Data instead of the CSV. Put your own connection string in `.env` (gitignored; see `.env.example`: `TIGER_DATABASE_URL`, `PUSHUP_USER_ID`), then `npm run db:migrate`, `npm run db:load` (CSV, marked `source=mock`), `npm run db:stats` and `npm run train:tiger` (`PUSHUP_SOURCES=real` ignores mock rows). **TLS:** hostname and certificate-chain verification are always required, including when no custom CA is configured. Weakening connection-string modes are rejected. If the endpoint has a private CA, obtain its CA bundle and fingerprint through an authenticated official service/support channel, verify that provenance, and set `TIGER_CA_CERT` to the local PEM file. No CA is automatically trusted and certificate errors are not bypassed. `TIGER_DB_ADDRESS` is an alias for `TIGER_DATABASE_URL`; `certs/` is gitignored.

The prototype uses its own `pushup` schema, separate from the gateway's `spottr_gateway` tables. Run every migration, including `004_immutable_workouts.sql`, before enabling uploads. The contributor reported migration/load/stats on a live service; this was not independently verified. On 24 October the main app's configured Tiger endpoint still failed strict certificate-chain verification. Offline fake-database tests verify the code paths, not deployment or live SQL acceptance.

### "My profile" in the app

Open the web page and press **My profile**. It asks the server how many reps you have (from Tiger Data when `TIGER_DATABASE_URL` is set, otherwise from the mock CSV), says whether that is enough (at least 300 usable reps, 5 sessions, 50 bad-form reps and 30 good-form reps), and if so lets you press **Train from my history**. After the request completes, the page displays its completed stages, then your usual elbow angle, body line and rep time, the tree's accuracy on sessions it had not seen, and the if/then rules. Mock data is tagged **demo data**. Missing rep durations are disclosed and excluded from fitting; malformed or nonfinite rows reject training without replacing an existing profile. Both the CLI and browser use the same readiness gate. The saved profile includes its owner, selected sources, training-data digest and immutable mock-data share. Another owner/source selection or a legacy artifact requires retraining. New rows can make the history newer than the saved profile without changing its training label.

### Rule and cloud status on the iPhone

a line under the advice banner says which rule judges the workout (default, or your personal rule with its depth and body-line limits, tagged demo data for mock history). After an explicitly approved upload, a status row shows whether the workout is saving, saved or still pending. Retrying requires another explicit action. The gauges follow the active rule, and the summary card names it.

### Saving workouts to the cloud

After a **standard camera** workout, choose **Upload workout** to send rep angles, durations, completion timestamps and rule-derived labels to your configured Tiger service. Ending a workout never uploads it automatically. Video replays and other variations cannot be uploaded as real standard-push-up history. Changing camera/video/variation starts a fresh workout.

Approval first persists an owner-bound workout snapshot in this browser's versioned local outbox. Only then does the request start. The workout has a stable UUID and a server-computed content hash: an exact retry adds no rows, while changed content returns a conflict. The database receipt and rep inserts use one transaction. Profile splits group new workouts by UUID; the older continuous aggregate still groups by integer start-second session and can combine two workouts begun in the same second. Rep completion times are observed by the page; they are not inferred from total workout duration.

Use **Retry pending uploads** explicitly after a failure or page reload. A different configured owner cannot send another owner's pending items. The browser never stores the server session token in the outbox. Conflicting snapshots require inspection/discard rather than silently overwriting cloud history. Local browser storage can be cleared by the browser or user and is not an account backup. Ownerless queues from the earlier prototype are not silently adopted.

Cloud actions are loopback-only and require the current local session token, an allowed Host/Origin and JSON requests. The token is obtained from the local page and stays in memory. This protects the new cloud/training routes; it does not add authentication to the existing LAN video/chat display routes. Cloud sync needs `TIGER_DATABASE_URL` (or `TIGER_DB_ADDRESS`) in `.env`. Labels come from the default angle rules rather than a human annotation, so training on them does not independently validate form.

### Default rule or your personal rule

Next to the push-up type there is a rule selector. **Default rule** uses the fixed thresholds. **My personal rule** (available once you have trained "My profile" with at least 30 good standard push-ups) judges "good form" against your own usual rep: depth must be within your usual elbow angle plus 3 spreads, and the body line above your usual minus 3 spreads, never looser than the default. A line under the buttons always says which rule is active and what it is based on (with a "demo data" tag for mock history). Choose before you start; the selector is locked during a workout, and the summary names the rule used. Counting is never changed: a rep still counts by the default depth line, so a bad profile cannot stop reps from counting. The References dialog has a table comparing the default rule with your trained one. The default rule's judgement is what gets saved to the cloud, so training never learns from its own labels. Only standard push-ups are saved for the profile.

## Things worth knowing

- Pose inference runs in the browser. Optional Gemini requests send workout metrics/questions; explicitly approved Tiger uploads send rep metrics. This implementation does not send video to those providers.
- The server listens on your Wi-Fi so the phone can reach it. State, camera frames, shared coach chat and `POST /ask` are accessible without a code; `POST /control` requires the control code. Use a network you trust. The code does not protect the video or chat. Details: [docs/ALGORITHM.md](docs/ALGORITHM.md#7-streaming-to-the-iphone).
- Thresholds are untuned guesses. How to validate and tune them with real clips: [docs/TEST_PLAN.md](docs/TEST_PLAN.md).
- Keep `GEMINI_API_KEY` in `.env` (gitignored), never in code.
- Third-party: `@mediapipe/tasks-vision` and the pose model are Apache-2.0. See [docs/ALGORITHM.md](docs/ALGORITHM.md#licenses).

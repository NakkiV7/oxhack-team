# Push-up Coach (prototype)

Counts push-up reps and checks posture from a webcam or a video, in the browser, with no training: Google's MediaPipe Pose Landmarker finds 33 body landmarks and simple angle rules do the rest. Easier variations (wall, incline, knee, standard) are included.

Optional extras:

- **iPhone display**: the Mac is the camera, an iPhone in front of you shows the count, live video with the body-line drawing, gauges and history, and speaks the reps.
- **Workout timer and summary**: total workout time (frozen while paused), time per rep with the average and a slowing-down warning, a confirm step before **Stop**, and a summary over the video when you end the workout. Standard push-up is the default variation.
- **Phone remote control**: pause, resume and stop from the iPhone using a control code shown on the Mac page.
- **AI coach (Gemini)**: a short pep talk or tip every few reps, plus a Q&A box that answers only from official health pages (WHO, CDC, NHS, NIH) with citations. Questions and answers are shared between the Mac page and the iPhone.

Not a medical or form-certified tool: a 2D side view cannot judge elbow flare or scapular issues.

## Quick start (Mac only, about 3 minutes)

Needs Node 20.17+ and a Mac webcam (or any video of a push-up filmed from the side).

```bash
cd prototype/pushup
npm install
npm run setup      # downloads the 9 MB pose model into models/
npm test           # 19 offline behavior checks; no model download or provider calls
npm run ui         # open http://localhost:3001
```

Pick a variation, click **Start camera**, put the camera at your **side** 2 to 3 m away so your whole body is in frame. Step-by-step with the iPhone app and the coach: [docs/TUTORIAL.md](docs/TUTORIAL.md).

## Layout

```
pushup.mjs        pure logic: angles, variation thresholds, RepCounter (no DOM, tested in node)
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
test/             node:test unit tests
docs/             TUTORIAL, ALGORITHM (how it works + guardrails), TEST_PLAN
.env.example      optional GEMINI_API_KEY
```

## Personal profile (mock history)

`data/history.csv` is mock past workout data (300 reps, 10 sessions, labels good / shallow / sagging / fatigued) for developing and testing the training. `npm run train` writes `data/profile.json` (gitignored): usual elbow angle, body line and rep time, plus a small decision tree as if/then rules. Not loaded by the live app yet.

`data/history-demo.csv` is a bigger mock history (3000 reps, 100 sessions) for demoing "enough data, training now". Regenerate with `npm run history:demo`; load it with `npm run db:load data/history-demo.csv`. It is mock: accuracy on it (about 100%) only shows the code works, because the generator wrote the labels.

### Tiger Data (your own database)

Rep history can live in Tiger Data instead of the CSV. Put your own connection string in `.env` (gitignored; see `.env.example`: `TIGER_DATABASE_URL`, `PUSHUP_USER_ID`), then `npm run db:migrate`, `npm run db:load` (CSV, marked `source=mock`), `npm run db:stats` and `npm run train:tiger` (`PUSHUP_SOURCES=real` ignores mock rows). **Certificate:** Tiger first signed with its own CA (`ca.timescale.com`, Node says "self-signed certificate in certificate chain") and later switched to a public CA, which Node trusts by default, so no file is needed any more. If you still see that error, save the CA file from your service's connection page as `certs/tiger-ca.pem` (or set `TIGER_CA_CERT`); it is trusted in addition to the normal roots and verification stays on. `TIGER_DB_ADDRESS` is accepted as an alias for `TIGER_DATABASE_URL`. `certs/` is gitignored.

Everything is in its own `pushup` schema, separate from the gateway's `spottr_gateway` tables. Migration, load and stats have been run against a live instance.

### "My profile" in the app

Open the web page and press **My profile**. It asks the server how many reps you have (from Tiger Data when `TIGER_DATABASE_URL` is set, otherwise from the mock CSV), says whether that is enough (at least 300 reps, 5 sessions and 50 bad-form reps), and if so lets you press **Train from my history**. The stages are listed as they finish, then your usual elbow angle, body line and rep time, the tree's accuracy on sessions it had not seen, and the if/then rules. Mock data is tagged **demo data**. The profile is saved to `data/profile.json`; the live rep counter does not use it yet.

### Rule and cloud status on the iPhone

a line under the advice banner says which rule judges the workout (default, or your personal rule with its depth and body-line limits, tagged demo data for mock history). After a workout ends, a status row shows the Tiger Data save: saving, saved, or not saved (the Mac keeps it and retries). The gauges follow the active rule, and the summary card names it.

### Saving workouts to the cloud

When you end a **camera** workout, the summary shows the cloud status: "☁ Saving to Tiger Data…", then "✓ Saved 28 reps to Tiger Data". Each rep is stored with `source = real`, its elbow and body-line angles, seconds, and a label taken from the app's cue (good, shallow, sagging, piking, other). If the save fails (offline, Tiger down), it says so, keeps the workout in this browser (localStorage) and retries when the page next opens or when you press **Retry now**. Sending the same workout twice adds nothing, because the session id is the start time. Uploaded videos are not saved, so test clips do not end up as real data. Cloud sync needs `TIGER_DATABASE_URL` (or `TIGER_DB_ADDRESS`) in `.env`; without it the summary says sync is off. The labels come from the app's own rules, not from a person, so a profile trained on them mostly learns those rules back.

### Default rule or your personal rule

Next to the push-up type there is a rule selector. **Default rule** uses the fixed thresholds. **My personal rule** (available once you have trained "My profile" with at least 30 good standard push-ups) judges "good form" against your own usual rep: depth must be within your usual elbow angle plus 3 spreads, and the body line above your usual minus 3 spreads, never looser than the default. A line under the buttons always says which rule is active and what it is based on (with a "demo data" tag for mock history). Choose before you start; the selector is locked during a workout, and the summary names the rule used. Counting is never changed: a rep still counts by the default depth line, so a bad profile cannot stop reps from counting. The References dialog has a table comparing the default rule with your trained one. The default rule's judgement is what gets saved to the cloud, so training never learns from its own labels. Only standard push-ups are saved for the profile.

## Things worth knowing

- Everything runs locally except the optional Gemini calls. No video leaves your network.
- The server listens on your Wi-Fi so the phone can reach it. State, camera frames, shared coach chat and `POST /ask` are accessible without a code; `POST /control` requires the control code. Use a network you trust. The code does not protect the video or chat. Details: [docs/ALGORITHM.md](docs/ALGORITHM.md#7-streaming-to-the-iphone).
- Thresholds are untuned guesses. How to validate and tune them with real clips: [docs/TEST_PLAN.md](docs/TEST_PLAN.md).
- Keep `GEMINI_API_KEY` in `.env` (gitignored), never in code.
- Third-party: `@mediapipe/tasks-vision` and the pose model are Apache-2.0. See [docs/ALGORITHM.md](docs/ALGORITHM.md#licenses).

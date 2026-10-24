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
ios/              SwiftUI iPhone app (Xcode project)
scripts/          fetch-model.sh
test/             node:test unit tests
docs/             TUTORIAL, ALGORITHM (how it works + guardrails), TEST_PLAN
.env.example      optional GEMINI_API_KEY
```

## Things worth knowing

- Everything runs locally except the optional Gemini calls. No video leaves your network.
- The server listens on your Wi-Fi so the phone can reach it. State, camera frames, shared coach chat and `POST /ask` are accessible without a code; `POST /control` requires the control code. Use a network you trust. The code does not protect the video or chat. Details: [docs/ALGORITHM.md](docs/ALGORITHM.md#7-streaming-to-the-iphone).
- Thresholds are untuned guesses. How to validate and tune them with real clips: [docs/TEST_PLAN.md](docs/TEST_PLAN.md).
- Keep `GEMINI_API_KEY` in `.env` (gitignored), never in code.
- Third-party: `@mediapipe/tasks-vision` and the pose model are Apache-2.0. See [docs/ALGORITHM.md](docs/ALGORITHM.md#licenses).

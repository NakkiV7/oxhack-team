# Squat Coach (prototype)

Counts squat reps and checks depth, lean, knee tracking and balance from a webcam or a video, in the browser, with no training: Google's MediaPipe Pose Landmarker finds 33 body landmarks and the rules in `squat.mjs` do the rest. Same shape as the push-up prototype next door, so the two look and work the same.

Optional extras, shared with the push-up prototype:

- **AI coach (Gemini)**: a short pep talk or tip every few reps, plus a Q&A box that answers only from official health pages (WHO, CDC, NHS, NIH) with citations.
- **Workout timer and summary**: total time (frozen while paused), time per rep with the average and a slowing-down warning, a confirm step before **Stop**, and a summary over the video when you end the workout.
- **Spoken coach (ElevenLabs)**: pick a voice in the header and the coach counts your reps aloud, calls form cues, throws in a motivational line every third clean rep, reads the Gemini tips in that voice's persona, and signs off at the summary. Lines are synthesised once per voice and cached in `voice_cache/`, so the live set never waits on the API. Set `ELEVENLABS_API_KEY` in `.env`; a key with the *Voices: read* permission lists your account's voices automatically, otherwise list them as `ELEVENLABS_VOICES=Name:voiceId,Name:voiceId`. A second id after a `+` (`Goggins:calmId+shoutingId`) is used for form cues and push lines, the first for counts, praise and the sign-off.
- **Tutorial**: a how-to guide on the page with two example sets (side view and facing the camera) run through this app's own coaching overlay and voice. Footage: Cavemantraining (CC BY-SA 4.0) and Gareth Myles / GM-FITNESS (CC BY), in `assets/`.
- **Phone remote control**: pause, resume and stop from a phone client using the control code shown on the Mac page. Live state and frames are streamed on `/events`.

Not a medical or form-certified tool: a 2D view cannot judge back rounding or bar path.

## Quick start (Mac only, about 3 minutes)

Needs Node 20.17+ and a Mac webcam (or any video of squats).

```bash
cd prototype/squat
npm ci
npm run setup      # downloads the 9 MB pose model into models/
npm test           # offline behaviour checks, including one real clip; no model download or provider calls
npm run ui         # open http://localhost:3002
```

Pick a squat type, click **Start camera**, put the camera **side-on or facing you**, 2 to 3 m away, with your feet in frame. Side-on gives depth and lean; facing the camera gives depth, knee tracking and balance. The push-up prototype uses port 3001, so both can run at once.

## Layout

```
squat.mjs         pure logic: hip travel, depth / lean / knee / balance, RepCounter (no DOM, tested in node)
index.html        camera/video input, pose loop, coloured skeleton, gauges, feedback, coach panel
server.mjs        local server: static files, state/frames to phones (SSE), coach, /ask, remote control
ask.mjs           guarded Q&A (official-source grounding, injection and leak filters), shared with push-up
test/             node:test unit tests + one real landmark fixture (CC BY-SA clip)
scripts/          fetch-model.sh
assets/           tutorial videos (Creative Commons footage with this app's overlay and voice)
.env.example      optional GEMINI_API_KEY, ELEVENLABS_API_KEY, ELEVENLABS_VOICES
```

## How counting works

Hip travel, as a fraction of standing leg length, is the rep signal: it is the same from any angle and cancels camera panning because it is measured as hip height above the ankle. A rep starts past 15% travel and ends back under 8%; attempts that never reach 22% are listed but not counted. The 2D knee angle only confirms that every visible leg bends, so stepping toward the camera or lifting one leg is not a rep. The standing baseline re-estimates whenever the legs are straight or the person has stood still for 3 s, and a rep stuck beyond 15 s resets. Bending over without sitting down (a kettlebell pick-up, a hinge) is discarded. Full detail and sources: **References** on the page.

`squat.mjs` is a line-for-line port of the Python reference in `squat/squat.py`, which has an evaluation harness and was tuned on 16 Creative Commons clips plus a webcam session with three testers. On identical landmark input the two agree on all 17 clips. If you change a threshold, change it in both and rerun `squat/eval.py`.

## Things worth knowing

- Pose inference runs in the browser. Optional Gemini requests send workout metrics/questions; no video leaves the machine.
- The server listens on your Wi-Fi so a phone can reach it; use a network you trust. Details are the same as the push-up prototype's `docs/ALGORITHM.md`, section 7.
- Depth and knee tracking need the knees and feet actually in frame; from a desk-height laptop camera the app counts but switches those gauges off rather than guess.
- Keep `GEMINI_API_KEY` in `.env` (gitignored), never in code.
- Third-party: `@mediapipe/tasks-vision` and the pose model are Apache-2.0. Test fixture footage: Cavemantraining, CC BY-SA 4.0.

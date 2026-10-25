# Tutorial: from clone to a coached set

About ten minutes on a Mac. Node 20.17 or newer is required.

## 1. Install and start

```bash
cd prototype/squat
npm ci            # installs @mediapipe/tasks-vision
npm run setup     # downloads the 9 MB pose model into models/ (once)
npm test          # 16 offline checks, no network
npm run ui        # serves http://localhost:3002
```

The terminal prints whether the AI coach and the voice are on. Without keys the page still counts and grades; only the Gemini tips, the Q&A box and the spoken coach are off.

The push-up prototype uses port 3001, so both can run at once in two terminal tabs.

## 2. Optional keys

Copy `.env.example` to `.env` and fill in what you have. `.env` is gitignored.

| Variable | What it enables |
|---|---|
| `GEMINI_API_KEY` | Coach tips every few reps and the grounded Q&A. Free tier is enough for a demo. |
| `ELEVENLABS_API_KEY` | The spoken coach. |
| `ELEVENLABS_VOICES` | The voices offered in the header when the key cannot list them: `Name:voiceId,Name:calmId+shoutingId`. |
| `ELEVENLABS_VOICE_ID` | Fallback single voice when nothing else is configured. |

Restart `npm run ui` after editing `.env`.

## 3. Set up the camera

- 2 to 3 metres away, at roughly hip height. A chair or a box under the laptop works.
- **Side-on** gives depth and lean. **Facing the camera** gives depth, knee tracking and balance. Both count reps.
- Feet must be in frame. From a desk-height camera the app still counts but switches the depth and knee gauges off.
- Stand tall for a second at the start so the app learns your standing height.

## 4. Run a set

1. Pick **Bodyweight squat (to parallel)** or **Half squat** in the type menu. They count the same; only the depth judgement differs.
2. Optionally pick a voice in the header. The first time you pick one it synthesises about 50 lines in the background; give it half a minute before a demo.
3. Click **Start camera** and allow camera access once.
4. Squat. The skeleton colours itself per segment: thighs and shins by depth, torso by lean (side) or balance (front), the knee line by knee tracking (front). Green, amber, red.
5. The rep counter card shows reps, good-form reps, the workout clock and seconds per rep with a slowing or steady trend. The gauges below show the live signals with their green and amber limits.
6. The history card lists each rep with its numbers and faults, and attempts that did not count.
7. **Stop** asks to confirm, then shows the workout summary.

## 5. Replay a video instead

**Upload video** accepts any clip the browser can play (H.264 mp4 is safest). It loops until you pause or stop, so the count keeps going; pause to read the history.

## 6. The Tutorial button

Opens a guide with two example sets run through this app's overlay and voice, the set-up and rep steps, and the list of faults the coach watches for. Useful as a first thing to show a judge.

## 7. The coach

- **Gemini tips** appear in the AI coach card every five reps or after two bad reps in a row, and the chosen voice reads them aloud in that coach's persona.
- **Ask a question** in the box: answers come only from WHO, CDC, NHS and NIH pages, with citations. Questions and answers are shared with any phone client.
- **Spoken lines** during the set: the count after each rep, the rep's form cue, a motivational line every third clean rep, a start line and a sign-off at the summary.

## 8. The tempo forecast

Below the counter, the **Tempo forecast** card watches the lowering phase of each rep against a programme target (default: 0.6 to 1.5 s). After three counted reps it forecasts, at every rep, whether one of the next two reps will leave the range. By default it runs in **shadow mode**: forecasts are stored, nothing is spoken. Tick **cue me** to let a forecast above the threshold speak a cue (with the current model no forecast reaches it). Open **Why this?** for the evidence behind the latest forecast. After **Stop**, the summary shows **What we anticipated** from the stored records, and the **Evidence** button opens the evaluation: baselines, calibration, the decision frontier, the dataset card. For a replay demo tick **pause at forecast** before uploading a raw clip: it plays once and pauses at each forecast before the next reps are revealed. Details: [HRT.md](HRT.md).

## 9. From a phone

The terminal prints the Mac's address and a control code. A phone client on the same Wi-Fi can read the live state and frames from `/events` and send pause, resume and stop to `/control` with the code. The push-up prototype ships an iPhone app for its state shape; the squat state carries the same fields plus the squat gauges, so a squat screen is a small change to that app.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| "Loading pose model…" never changes | `models/pose_landmarker_full.task` is missing: run `npm run setup`. Or another server holds port 3002: stop it. |
| "Camera error" | The browser was denied camera access. Allow it for localhost in the browser's site settings. |
| Reps not counting | Feet not in frame, or standing at the frame edge. Step back; watch the hip travel gauge rise past 22%. |
| "Step back: hips and knees must be in view" | The hips are below the frame or hidden. Move the camera lower or step back. |
| No voice | No `ELEVENLABS_API_KEY`, or the browser blocked audio until the first click. Click any button once. |
| Voice menu only shows "Coach" | The key cannot list voices. Add `ELEVENLABS_VOICES` to `.env` or create a key with the Voices read permission. |

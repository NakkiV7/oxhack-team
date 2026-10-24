# Tutorial: run it yourself

Three parts. Do part 1, then add 2 and 3 only if you want them.

1. [Mac only](#1-mac-only): count reps in the browser.
2. [iPhone display](#2-iphone-display-optional): Simulator or a real iPhone.
3. [AI coach](#3-ai-coach-optional): needs a Gemini API key.

## 1. Mac only

**You need:** a Mac or any computer with Node 20.17+ (`node -v`), a modern browser, a webcam or a side-on video of push-ups.

```bash
cd prototype/pushup
npm install
npm run setup
npm run ui
```

`npm run setup` downloads `models/pose_landmarker_full.task` (about 9 MB, gitignored). If the page cannot load the model, run it again.

Open <http://localhost:3001> (allow camera access for your browser in macOS Privacy settings if asked).

1. **Camera placement:** to your **side**, 2 to 3 m away, hip height, whole body in frame, good light. Front-on does not work.
2. **Choose a variation** (easiest first): Wall, Incline (hands on a bench), Knee, Standard.
3. Click **Start camera**. Get into the start position (arms extended) until the message says you are in position.
4. Do reps. A rep counts only if your elbow bends below the variation's depth threshold and comes back up. The page shows reps, good-form count, live advice, elbow angle, body-line (straightness) and a per-rep history.
5. **No camera?** Click **Upload video** to analyse a recorded side-view clip. It loops and keeps counting until you press **Pause** (then **Resume**) or **Stop**. If the browser says it cannot play the file, convert it to .mp4 (H.264); some iPhone .mov files do not play in Chrome.
6. **Timer and pace:** the ⏱ clock is your total workout time and stops while paused. The history shows how long each rep took, tinted yellow if it was more than 15% slower than your average so far and green if more than 15% faster (needs 2 earlier reps). **s/rep** is the average; after 6 reps it shows **▲ slowing** (last 3 reps more than 15% slower, a sign of tiring), **▼ faster** or **steady**.
7. **Stop** asks "End this workout?" first. After you end it, a **Workout summary** (total time, reps, good form, average / fastest / slowest rep, most common issue) appears over the video. **Start again**, Esc, or starting the camera / uploading a video hides it and begins a fresh workout. **Reset reps** clears the count, history and timer.

What the messages mean:

| Message | Meaning |
|---|---|
| Not low enough | Elbow did not reach the depth threshold; the rep is not counted |
| Hips sagging | Hip is below the shoulder-to-ankle line; squeeze core and glutes |
| Hips too high | Hip is above the line; lower it |
| Keep your body in one straight line | Wall push-ups: body should stay straight (sag/pike not judged) |

Run the tests any time: `npm test` (rep counting, cues, and the Q&A safety filters; no network needed).

## 2. iPhone display (optional)

The Mac stays the camera. The iPhone shows the count, the live video with the body-line drawing, gauges and the history, and speaks reps. The Mac and the iPhone (or Simulator) must be on the **same network**; only the one-time install needs a cable.

Start the server first (`npm run ui`). It prints lines like `iPhone: enter 192.168.1.23 in the pushup-ios app`. Use the address on your Wi-Fi (ignore `169.254.x.x`).

### Option A: iOS Simulator (no iPhone needed)

1. Install Xcode (iOS 17+ simulator). Open `ios/pushup-ios.xcodeproj`.
2. Pick any iPhone simulator and press Run.
3. In the app enter `127.0.0.1` (or the printed address) and tap **Connect**.
4. On the Mac page click **Start camera**. The simulator shows the live data.

### Option B: a real iPhone

One-time setup:

1. iPhone running iOS 17 or newer. Turn on **Developer Mode**: Settings, Privacy and Security, Developer Mode (the phone restarts).
2. Connect the phone with a cable (or use Xcode wireless debugging) and tap Trust.
3. In Xcode open `ios/pushup-ios.xcodeproj`, select the target `pushup-ios`, **Signing and Capabilities**: choose **your own Team** (a free Apple ID works; builds expire after 7 days) and change the **Bundle Identifier** to something unique, for example `com.yourname.pushupios`.
4. Select your iPhone as the destination and Run.
5. First launch: on the phone open Settings, General, VPN and Device Management, trust your developer certificate, then launch the app again.

Every session after that no cable is needed:

1. Mac and iPhone on the same Wi-Fi. `npm run ui` running.
2. In the app enter the Mac address (for example `192.168.1.23`, add `:3002` if you set `PORT`) and tap **Connect**. Allow the **Local Network** prompt.
3. On the Mac page click **Start camera**.

**Pause and stop from the phone:** the Mac page shows a **Phone code** at the top (also printed by `npm run ui`). In the app settings type it under **Control code** (once). While a workout runs, **Pause / Resume** (uploaded video only) and a red **Stop** appear under the video. Stop asks "End this workout?" first. The Mac page must stay open. The phone also shows the clock, average rep time, tinted rep times and the workout summary.

Place the iPhone on the floor in front of you. The status dot is green when live, orange when connected but the Mac camera is off, red when disconnected (it reconnects by itself). The app keeps the screen awake; the speaker icon toggles voice.

Troubleshooting:

| Problem | Fix |
|---|---|
| Stuck on "Connecting" | Same Wi-Fi? Use the Wi-Fi IP, not `169.254.x.x`. Some guest/hotel/university Wi-Fi blocks device-to-device traffic: use a personal hotspot or home Wi-Fi |
| Local Network prompt missed | iPhone Settings, Privacy and Security, Local Network, enable the app |
| Port busy | `PORT=3002 npm run ui`, and enter `192.168.x.x:3002` |
| Build fails on signing | Step 3 above: your own team and a unique bundle ID |
| Page works on the Mac but the phone shows nothing | Click **Start camera** on the Mac; the phone only mirrors a running session |

## 3. AI coach (optional)

1. Get a Gemini API key from Google AI Studio.
2. `cp .env.example .env` and put the key after `GEMINI_API_KEY=`. `.env` is gitignored: never commit it.
3. Restart `npm run ui`. The log says `AI coach: on (...)`.

What you get:

- A short pep talk or tip every 5 reps, or when two reps in a row have bad form (never more than once per 20 s). It shows in the **AI coach** panel on the Mac page and in the purple bubble on the iPhone.
- A question box (max 256 characters) on the Mac page and on the iPhone Coach page (tap the bubble). Answers (max 1024 characters) come only from fetched excerpts of WHO, CDC, NHS, MedlinePlus/NIH, NHLBI and US HHS pages, with clickable `[n]` citations and a References list. It is general information, not medical advice. It refuses off-topic questions, prompt-injection attempts and requests for keys or settings. How: [ALGORITHM.md](ALGORITHM.md#ask-the-coach-guardrails).

If the model is busy you may see `gemini: ... 503` in the server log; it falls back to a lighter model and the coach simply skips a turn if both fail. Set `GEMINI_MODEL` in `.env` to change the main model.

Without a key everything else works; the coach panel says it is off.

## Stopping and cleaning up

Press Ctrl+C in the terminal running `npm run ui`. Nothing is stored on disk except the downloaded model.

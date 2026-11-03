# Algorithms, techniques and licences

How Squat Coach turns camera frames into rep counts, form grades and spoken coaching. Logic lives in [squat.mjs](../squat.mjs) (pure, tested in node), the page in [index.html](../index.html), the server in [server.mjs](../server.mjs). The Python reference implementation and evaluation harness live in [`squat/`](../../../squat/README.md) at the repository root.

## Pipeline

```
camera / video frame
  -> MediaPipe Pose Landmarker (33 landmarks, normalized x/y/z + visibility)
  -> measure()      best-seen leg, hip travel, depth, lean, knee width, balance, view ratio
  -> RepCounter     smoothing + baseline + standing/down/up state machine + per-rep grades
  -> feedback       live message, coloured skeleton, gauges, history
  -> voice          spoken count, cue, motivation (ElevenLabs via the local server, cached)
  -> coach          every 5 reps or 2 bad reps in a row: server asks Gemini for a short tip, in the chosen voice's persona
  -> stream         state (~10 Hz) + JPEG frames (~8 Hz) to phone clients over SSE
```

All inference runs locally in the browser (WASM, GPU delegate with CPU fallback). No frames leave the machine.

## 1. Pose estimation

- Model: MediaPipe **Pose Landmarker (full, float16)** from `@mediapipe/tasks-vision`, running mode `VIDEO`, `numPoses: 1`.
- Output: 33 landmarks with `x`, `y` (0 to 1 of the image), `z`, and `visibility` (0 to 1).
- Landmarks used (left/right): shoulder 11/12, hip 23/24, knee 25/26, ankle 27/28.
- `x` is multiplied by the image's width/height before any geometry, so angles are measured in square units.
- No training was done. The pretrained model is used as is.

## 2. View and leg selection

`measure()` picks the **best-seen leg** by the lowest visibility among hip, knee and ankle on each side, because a side-on camera hides one leg. A leg counts as *seen* when knee and ankle visibility are at least 0.5; MediaPipe extrapolates joints just outside the frame, so a joint can be seen without being inside the picture.

The **view** is the shoulder width divided by torso height, smoothed with an exponential moving average (factor 0.9), with two thresholds: above 0.5 is *front*, below 0.35 is *side*, and in between the previous answer is kept. Without this hysteresis the view flickered mid-rep and fired front-only cues on side footage.

## 3. Signals

| Signal | Definition | Used for |
|---|---|---|
| Hip travel | `1 - (ankle.y - hip.y) / standing leg length` when the foot is seen; otherwise `(hip.y - standing hip.y) / leg length` | Rep counting. Measured as hip height above the ankle so a panning camera cancels out. |
| Knee angle | 2D hip-knee-ankle angle of each seen leg | Gate only: a straight leg is collinear from any viewpoint, so this confirms standing and bending without needing depth from the camera. |
| Depth | `(hip.y - knee.y) / standing thigh length` | Form grade. 0 means the hip crease is level with the knee (parallel); negative is above. |
| Lean | torso angle from vertical | Form grade, side view only. |
| Knees | knee width / ankle width | Form grade, front view only, and only while the knee angle is under 140°. |
| Balance | hip-line tilt minus shoulder-line tilt | Form grade, front view only. Perspective tilts both lines the same way, so the difference isolates real weight shift. |

All signals pass through an exponential moving average with factor 0.5 before the state machine, matching the push-up prototype.

Depth and knee width are only judged when the knees and ankles are actually inside the frame (`y < 1.05`). From a desk-height laptop camera the app still counts, but those two gauges show "not judged" rather than guess.

## 4. Baseline

The standing reference (hip y, hip height above ankle, thigh length) is taken on the first good frame and then re-estimated with factor 0.1 per frame whenever the legs are straight (knee angle over 160°) or the person has hardly moved for 3 seconds. This absorbs stepping closer or further from the camera and a bad first frame. A rep that is still open after 15 seconds resets the state and the baseline. These rules came from a webcam session where the count stalled after a tester moved closer.

## 5. Rep state machine

`standing -> down -> up -> standing`

1. **Gate:** if the best-seen hip or knee visibility is under 0.5, or the hip is below the frame (`y > 1.1`), the frame is skipped. After one second of lost tracking an open rep is abandoned. A hallucinated hip below the frame, from someone leaning into the camera, is therefore never a rep.
2. **standing -> down** when hip travel exceeds 0.15 **and** every seen leg's knee angle is under 150°. The second condition rejects walking toward the camera (hips drop in the image, legs stay straight) and a single-leg lift (one leg stays straight).
3. **down -> up** when travel has come back 0.04 below the rep's maximum, after at least 0.1 of travel.
4. **up -> standing** when travel is under 0.08, **or** the legs are straight and travel is under 30% of the rep's maximum (which tolerates baseline drift during the rep).
5. **Scoring:**
   - Discarded entirely: travel over 0.9 of leg length (only a camera cut produces this), torso lean over 80° in side view, or lean over 60° with shallow depth (a hinge or a kettlebell pick-up), or lean over 100° anywhere.
   - Listed but not counted: maximum travel under 0.22, or duration under 0.5 s or over 15 s. A wobble under 0.11 is ignored.
   - Counted: metric grades from each metric's worst frame in the rep; `good` means no metric is amber or red. Tempo faults (descent under 0.45 s; ascent over 2.2 s or 1.6 times the median of earlier ascents) are listed but do not make a rep "bad".

## 6. Thresholds

| Metric | Green | Amber | Red | Cue |
|---|---|---|---|---|
| Depth, standard | ≥ -0.10 | ≥ -0.35 | below | Deeper: hips to knee height |
| Depth, half squat | ≥ -0.35 | ≥ -0.60 | below | same |
| Lean (side) | ≤ 40° | ≤ 55° | above | Chest up |
| Knees (front) | ≥ 0.85 | ≥ 0.70 | below | Knees out |
| Balance (front) | ≤ 12° | ≤ 18° | above | Even weight on both feet |

Depth limits per variation are in `VARIATIONS`; the rest in `METRICS`. Counting never depends on the variation.

## 7. Spoken coach

The page keeps a speech queue: one line plays at a time and is never cut off; a more urgent line waits its turn; the same line is not repeated within 8 s; low-priority lines older than 4 s are dropped. Rep counts have the highest priority, then form cues, then motivation.

The server's `GET /say?text=&voice=` synthesises a line through ElevenLabs once per voice and caches the mp3 under `voice_cache/`. The fixed lines (numbers 1 to 30, the cues, the motivational lines) are prewarmed when a voice is chosen, so a live set never waits on the API. A voice can carry two ids (`Name:calmId+shoutingId`): the calm one speaks counts, praise, Gemini tips and the sign-off; the shouting one speaks form cues, the start line and push-style motivation.

The chosen voice's name sets the Gemini coach's persona in the server prompt. The prompt tells the model to stay in character and never claim to be a real person.

## 8. Streaming to a phone and security

Identical to the push-up prototype: the page posts a state snapshot to `/state` about ten times a second and a 480 px JPEG to `/frame`; the server fans them out on `/events`. Only `GET /events`, `GET /state`, `POST /ask` and `POST /control` (with the control code) are served to other devices on the Wi-Fi; everything else is loopback only. See the push-up [ALGORITHM.md, section 7](../../pushup/docs/ALGORITHM.md#7-streaming-to-the-iphone) for the details and the trust model. The squat server adds `GET /voices` and `GET /say`, both loopback only.

## 9. Tiger Data stream

Every analysed frame and every rep is queued on the page and posted to the local server once a second; the server writes them to two TimescaleDB hypertables and the page reads the per-second and per-minute continuous aggregates back for its Tiger card. Schema, policies, verification and the reason for a time-series store are in [TIGER.md](TIGER.md).

## 10. Validation

The counting rules were tuned in the Python reference against 16 Creative Commons clips (front, side, three-quarter and low angles; bodyweight, goblet, racked and overhead squats) and a 2 minute 41 second webcam session with three testers. Every clean set counts exactly; the only misses are on footage that cuts away mid-rep. On identical landmark input `squat.mjs` agrees with the Python counts on all 17 clips. In the browser with the real MediaPipe, a single pass of a 6-rep side clip counted 6 of 6. See [TEST_PLAN.md](TEST_PLAN.md).

## Known limitations

- 2D only: back rounding and bar path are not checked.
- Front-view thresholds were tuned on fewer clips than side-view ones.
- Loose clothing, poor light or a very close camera reduce landmark accuracy, especially at the feet.
- Not medical advice or a certified coaching tool.

## Licences

| Component | Licence |
|---|---|
| This prototype's code | Same as the repository (not yet chosen; add a `LICENSE` before publishing). |
| `@mediapipe/tasks-vision` 1.1.1 and the pose model | Apache-2.0 (verify on the [model card](https://ai.google.dev/edge/mediapipe/solutions/vision/pose_landmarker) before redistributing). |
| `assets/squat_side.mp4`, test fixture | Footage: Cavemantraining, CC BY-SA 4.0, via Wikimedia Commons; overlay and voice added by this app. |
| `assets/squat_front.mp4` | Footage: Gareth Myles (GM-FITNESS), CC BY, via YouTube; overlay and voice added by this app. |

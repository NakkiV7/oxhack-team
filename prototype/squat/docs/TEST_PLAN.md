# Test plan

What is checked automatically, what was checked by hand, and how to re-check after changing anything.

## Automated

`npm test` runs 66 node checks with no network and no model download:

- `test/ask.test.mjs`: the coach Q&A guardrails (shared with the push-up prototype).
- `test/tiger-stream.test.mjs`: the Tiger batch validation, the ingest against a fake pool (frames, reps, forecasts, outcomes), the strict-TLS pool guard and the migration files (see [TIGER.md](TIGER.md)).
- `test/coach.test.mjs`: the coaching journey's domain rules (capabilities, programme validation and fallback, comparison, node contracts and idempotent rewards, the coach-retry-verify state machine, report facts, week boundaries, goal validation, Gemini output validation with a fake provider, keyed store writes); see [COACH.md](COACH.md).
- `test/path.test.mjs`: the training path (criteria, ability bands, distinct valid paths for five survey profiles, placement with a camera check, validation rejections, levels, attributes, the version diff, Gemini bounds and fallback, the daily practice key, progress carry-over on save, deterministic map layout and node states); see [COACH.md](COACH.md).
- `test/hrt.test.mjs`: the tempo forecaster (target boundaries, past-only features, two-rep horizons and exclusions, shadow and coaching actions, cooldown, outcome linkage, immutability, parity with the offline definition); see [HRT.md](HRT.md).
- `test/squat.test.mjs`:
  - angle and grade helpers;
  - a synthetic side-on figure whose hip drops along a sine profile: three full squats count three and are clean; a shallow dip is listed but not counted; a tiny wobble is ignored; a rep under half a second does not count; bending at the hips with the torso folded is a hinge, not a squat; hallucinated hips below the frame are rejected; standing closer to the camera re-baselines instead of counting; the half-squat variation grades a shallow rep good while the standard one does not;
  - **one real clip**: `test/fixtures/kb_racked_squat_01.json` holds the MediaPipe landmarks of a five-rep kettlebell racked squat (Cavemantraining, CC BY-SA 4.0). It must count exactly 5, all good form.

## Parity with the Python reference

`squat.mjs` is a line-for-line port of [`squat/squat.py`](../../../squat/squat.py). The Python side has the evaluation harness (`squat/eval.py`) and was tuned on 16 Creative Commons clips plus a webcam session. On identical landmark input the two implementations agree on all 17 clips:

| Clip | Reps |
|---|---|
| kb_side (beach, side, deep) | 6 |
| kb_racked_squat (low angle) | 5 |
| squat_frontal_raise (gym, side) | 6 |
| demo_front (barbell, three-quarter) | 2 |
| goblet_squat_kb (three-quarter) | 2 |
| overhead_kb_squat_single_arm (front) | 16 |
| half_squat_home_cdc (320×240 webcam-style, half squats) | 6 |
| team webcam session, 2:41, three testers | 21 |
| nine other clips with cuts, jumps, pistols, an animation and a tutorial | as the reference |

To rerun the comparison after a change: dump landmarks for the clips with the Python wrapper (see the snippet in the repository history under "parity"), run a node script that feeds each clip's frames to `RepCounter` with `aspect = width / height` and `t = frame / fps`, and compare counts with `squat/eval.py` on the same folder. Any difference means the port drifted from the reference.

## Browser checks done by hand

- Single pass of the 50 s side clip through **Upload video**: 6 of 6 counted, all good form, cues and tempo trend shown.
- A 15 s clip on loop: counting continues across loops; one rep per loop is typically lost at the jump back to the start, which is a property of looping, not of the counter.
- Spoken coach during a replayed set: "1, 2, 3", a motivational line, "4, 5, 6", a second line, each played to the end before the next; all lines served from the cache after the first synthesis.
- Tutorial dialog renders both videos and steps in light and dark themes; videos pause when the dialog closes.
- Theme switch persists across reloads.
- Coaching journey, 25 October: the offline driver `coach-replay.mjs` ran the six-rep side clip through the real routes (baseline of three reps, a Gemini `maintain_target` cue because the baseline median 1.37 s already met the 1.5 s target, explicit retry, three retry reps, computed result "similar", the attempt and a first-completion milestone saved in one transaction, a Gemini explanation citing the computed facts); `coach-demo-seed.mjs` seeded six labelled synthetic sets for the demo account and its weekly review flagged them; the journey page rendered the tree, a session report and the weekly review in the browser. Not checked by hand: the loop with a live camera on this machine.
- Tempo forecast, held-out replay of the raw six-rep side clip with *pause at forecast*: the clip played once, paused at the forecasts after reps 3 and 4 with the status line naming the rep, resumed on the Pause button, ended the set itself at the end of the clip; "What we anticipated" read both forecasts back from Tiger with the observed outcome (rep 5 outside the range) and lead times of 16.4 s and 8.5 s; the Evidence dialog drew the stored timeline with the onset marker. Shadow mode throughout; with the frozen threshold no cue was due.
- Tiger Data card with the team's service configured: the replayed side clip streamed 1,266 frames and 6 reps, the card's counters and sparkline updated every two seconds from the database, End workout wrote the end mark, Compress now converted the closed chunk. Same pass on the push-up page (6,083 frames, 24 reps). Details and numbers in [TIGER.md](TIGER.md).
- Training path, 25 October, in the app's browser pane: a new account ran the whole survey with real Gemini (one generation), got a validated four-step path starting at glute bridges for "not sure", and saved it as version 1. Logged practice gave +10 XP and "1 of 3 days"; a second log the same day returned `logged: false` and the button reads *Logged today*. Adjusting the starting point to "comfortable" with focus "improve" produced a preview starting at squats; the diff listed the start change, the new optional step and glute bridges kept in history; saving made version 2 with XP intact. The legacy account's adjust flow showed its old answers mapped onto the new options. Checked at 1440×900, 1100×820 (step panel as a bottom sheet), 704 wide and 375×812 (vertical map, floating action only once the quest button scrolls away): no overlap or clipping after the fixes in this pass (map scale cap, labels with a halo and above upper side branches, toast width, phone top bar). Keyboard: arrows, Home, End and Enter on the map. Reports: chart, before/after line, moments in time order, weekly tiles and quests.
- Camera path, 25 October: the app's browser pane blocks real webcams, so the raw six-rep side clip was fed to the page as its camera stream (the page's own `getUserMedia` call, 640×480 at 30 fps). The full loop ran from **Start camera**: baseline of three, a cue (Gemini proposed "keep this tempo" for a baseline outside the band, the validator refused it, the deterministic cue was used), **Start retry**, three retry reps, "About the same" with the retry inside tolerance, a first-completion milestone saved, a Gemini explanation. The programme page then showed Squats verified, Split squats unlocked as the new quest, the milestone toast, and Tempo and Consistency computed. Interruptions: a camera that ends mid-baseline pauses and resumes at the same count; mid-retry, the same camera resumes the retry and a different one ends the attempt as unable to assess. Found and fixed: no resume path existed, a disconnected camera was not noticed, a rep begun before **Start retry** counted as a retry rep, and an unable attempt showed the step's earlier milestone.
- Reduced motion, 25 October, in headless Chrome with `prefers-reduced-motion: reduce` emulated over DevTools: no animation on nodes or links, the map fully drawn 250 ms after load, dashed and solid links visible. Without the setting the same page is still fading in at 250 ms.
- Accessibility tree, 25 October, from Chrome's own computed tree: hidden tabs are absent; every map step is a button named with its state, capability and role, with a pressed state; the phone step sheet is a modal dialog with focus on Close and the page behind it inert; the closed sheet is out of the tree; the survey is a modal dialog named after its question with toggle buttons. Fixed in this pass: heading levels in the step panel, unnamed "Go" buttons, the XP bar's role, survey step names on phones, and "None yet" showing beside a real achievement.

Not yet checked by hand: a person squatting in front of a real webcam (needs Chrome, not the app's browser pane), a phone client against the squat state, and VoiceOver reading the page aloud.

## How to tune a threshold

1. Change it in `squat/squat.py` first and run `squat/eval.py CLIP_DIR` on the reference clips; every clean set must still count exactly.
2. Mirror the change in `squat.mjs` (`VARIATIONS`, `METRICS` or the constants at the top).
3. `npm test`; the real-clip fixture must still count 5.
4. Rerun the parity comparison above.
5. Update the References dialog text in `index.html` and the thresholds table in [ALGORITHM.md](ALGORITHM.md).

## Known gaps

- Front-view thresholds (knees, balance) were tuned on fewer clips than side-view ones.
- No labelled push-up or squat form-error dataset with real video was available; form grades rest on angle rules checked against clips, not on a trained classifier.

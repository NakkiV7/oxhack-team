# Demo click path

Three windows: Chrome tab A at http://localhost:3002 (squat page), Chrome tab B at http://localhost:3002/coach?user=nakki (programme page), and the paper at http://localhost:3002/docs/hrt-paper/main.pdf. About twelve minutes end to end; the ninety-second version is Part 0 steps 4 and 5, then Part 1.

## Before judges arrive

1. `cd prototype/squat && npm run ui` (Tiger, Gemini and the voice all read from `.env`; the terminal must say `Tiger Data: on` and `Tiger Data: schema ready`).
2. Tab B: Programme should show Squats as the current step and Glute bridges as *not required*. If not: **Adjust my path** → Starting point → *I can squat, but want help with control* → **Back to review** → **Build a new version** (about 15 s) → **Save as version N**.
3. Tab B: Research → search one general question (for example "does tempo-controlled lowering change squat strength outcomes") or **Analyse** a PDF you have. One saved source is enough.
4. Tab B: Weekly review → **Review this week so far** (about 10 s). Leave it generated; do not regenerate in front of judges.
5. Tab A: pick the voice (Arnold or Goggins) once so the lines prewarm. Camera side-on at hip height, two to three metres, feet in frame.
6. Have the raw held-out clip handy for Part 3 (a raw recording with an audio track, not the tutorial video). Loop on `pause at forecast` is set at that moment, not before.

## Part 0. Build a training path (about 2 minutes, tab B)

1. Open http://localhost:3002/coach?user=judge3 (any id not used before). The empty state shows an example path and **Build my training path**.
2. Walk the survey: *Squat path* → *I'm not sure* → *Continue with my answers* (or the camera check if the camera is set up) → tick *A clear wall* and *Something stable to hold* → *20 min*, *3 per week* → *Improve a skill I have*, *Encouraging*, leave out one movement. Say: "concrete statements, not a fitness score; leaving something out needs no reason."
3. On the review, click **Edit** on one answer and show it comes straight back. Click **Build my path**. Say while it loads: "Gemini picks from the catalogue only; the app checks every link, target and capability before we see it."
4. The preview draws the path. Read the start reason. Point at the provenance badge. Click **Start my path**.
5. The map: the current step glows, camera steps are hexagons with a camera badge, practice steps are circles, the optional branch is violet and gates nothing. Click a locked step: the panel says what comes before it and offers **Go to …**, not a camera. Click the current step and **Log practice**: +10 XP, the ring fills a third. Click it again: *Logged today*.
6. Point at the level ("a game score, not fitness") and the three attributes reading *Not assessed yet*. Open *How is this calculated?* on Tempo.
7. **Adjust my path** → change the starting point → **Build a new version**. Show *What changes*, *Progress carried over* and *Kept in your history*, then close without saving.

## Part 1. Coach, retry, verify (live camera, about 3 minutes)

1. Tab B, Programme (user nakki): click the Squats hexagon. The step panel shows the camera badge, *Why this step?*, and *Completion* with the contract (target 1.5 s lowering, tolerance, three counted reps).
2. Click **Assess with camera** in the panel. Tab A opens with the *Coach · retry · verify* card reading *Setting up*.
3. Click **Start camera**. Say: "three reps at my natural pace; nothing is judged yet." Do three squats. The card counts *Baseline: n of 3*.
4. After the third rep the card says *Preparing one cue*, then shows the cue and speaks it. Read it aloud if the room is loud. Say: "Gemini chose from five allowed actions and could only use numbers from these three reps; the target is now frozen."
5. Click **Start retry**. Do three squats following the cue.
6. The card shows the result: *Closer to the target*, *About the same*, *Further from the target* or *Unable to assess*, with both medians and the tolerance. Say the result as it is. "About the same" is a valid result. If a milestone is earned the pill says so; if not, the card says why.
7. Wait for the explanation to appear (Gemini, 5 to 25 s; keep talking). Say: "the explanation cannot change the result; it cites the computed facts."
8. Click **Stop** → **End workout**. The summary shows "What we anticipated" from the forecaster (it ran in shadow mode throughout).

If the camera warns about framing, step back until the warning clears; the loop will not start a baseline on poor tracking. If the cue is marked *(deterministic cue)*, say so: Gemini's answer failed validation and the fallback named the target instead.

## Part 2. Tiger (about 1 minute, tab A)

1. Point at the Tiger card: frames stored, rows per second, compression, rollup query time, the sparkline. Say: "every analysed frame is a row in a hypertable; the line is read back from a continuous aggregate."
2. Click **Compress now**. Say what happened (closed chunks converted; the percentage is real storage).

## Part 3. HRT forecasting evidence (replay, about 3 minutes, tab A)

1. Tick **pause at forecast**. Make sure **cue me** is off (shadow mode).
2. Click **Upload video** and pick the raw held-out clip. Say: "held-out recording; the counter has not seen the rest of the clip."
3. The video pauses at the first forecast (after rep 3). Expand **Why this?** and read the bounds, the recent lowering times, the trend and the probability labelled preliminary.
4. Click **Pause/Resume** to reveal the next reps. The clip plays once and ends the set itself; the summary shows the stored outcome and lead time, or "horizon incomplete" if the clip ended first.
5. Click **Evidence**. Walk down: status line (development only, test not run), the baseline table, the bootstrap intervals that include zero, the frontier with the budget line, the dataset card, the reproducibility ids. Say the negative result plainly: eight sustained departures in 1,141 reps, the model equals the constant, no cue threshold fits the budget, so the deployed policy is silent.

## Part 4. Reports and the weekly review (about 2 minutes, tab B)

1. Reports: click the set you just did. Show the stat tiles, the lowering-time chart with the target band, the coaching attempt as a before/after line, the biometrics box saying none were recorded, and the moments. Click **Write the summary** once; show the fact chips under it. *All calculated facts* at the bottom lists every id.
2. Weekly review: open the review generated earlier. Show the headline, the stat tiles with week-on-week changes, *What stood out*, and next week's quests.
3. Click **Why this?** on one quest; the answer cites fact ids.
4. Edit a target, untick one quest, click **Accept selected quests**. Profile tab shows them as accepted. Say: "nothing in the programme changed until I accepted; the accepted goals feed the next programme generation."

## Part 5. Research (about 1 minute, tab B)

Research tab: click the saved source. Show the access label (full text, abstract or metadata), the extracted question, design, population, findings, limitations and quoted passages with page numbers. Say the line at the bottom: a study finding never proves an individual outcome and never changes a pass criterion.

## Part 6. The paper (about 1 minute)

Open main.pdf. Table 1 (baselines under the budget), Figure 2 (frontier with the budget line), Section 3's paragraph on how the specification was revised and why, the held-out paragraph that says "not evaluated". Every number is a macro generated from the same artifact the Evidence dialog reads.

## Switching to the demo account

Tab B user menu → *demo (sample history)*. Its six sets are labelled synthetic in every report and never enter the forecaster's evaluation. Use it only to show the weekly workflow if the real account has too little history.

# Spottr offline MVP checkpoint

This records the earlier build 18 checkpoint. The later production-foundation update expands the library to 32 entries and 13 camera styles and adds optional website accounts and StoreKit infrastructure. See [current priorities](production-next-steps-2026-11-05.md) and [App Store preparation](app-store-launch-2026-11-05.md).

## Implemented in this change

- Nine camera exercise choices. Squats and push-ups plus half, supported and wide squats, wall, incline, knee and close-grip push-ups. The camera checks the selected movement's depth and body geometry; it does not automatically verify hand width, support stability or stance width.
- Partial occlusions preserve a witnessed movement within the existing bounded continuity window. Missing frames do not erase completed reps. Completely unseen depth is not counted. Long gaps require a new visible top position.
- Switching manual/camera input preserves completed reps, active time and completed sets, including while paused. Work that includes manual counts is recorded as self-report, and no camera timing is claimed for that mixed set.
- Optional English spoken rep counting with on-device recognition only. It accepts the next number once, leaves the camera off, and suppresses coach speech while listening. Missing local recognition or permissions leaves manual entry available.
- Five-step onboarding with goals, optional weight management, weekly rhythm, comfortable movements and coach preferences. Existing profiles reopen onboarding once. Real workout history is not erased.
- A vertical skill path with self-reported starting placements, earned steps, one current challenge and at most two upcoming locks. More advanced content remains hidden; the library still allows choosing any exercise.
- Option-based local Coach and summaries calculated from recorded training. No generated consumer coach, pathway, report or paid runtime requests. Duplicate Progress navigation is consolidated under Insights.
- Abstract colour/waveform coach designs. Faceless stickman exercise art highlights relevant joints. Celebrity portraits removed from the app's assets; optional existing audio retained.
- Watch workout, controls and vitals pages, navigated with the Crown/vertical paging. Fresh heart rate, active energy and motion values; missing/stale values stay unavailable.
- Pose processor reused across capture restarts instead of reloading on each set; monotonic model timestamps preserve camera/video reuse.

## Audio status

**Build 22 candidate update:** renewed restricted authoring access succeeded. Maya and Leo now have 144 natural bundled recordings across three styles, using 3,658 credits within the approved 10,000-credit cap. [Current audio evidence](evidence/natural-coach-voices-2026-11-05.md). The paragraph below records the earlier build 19 checkpoint.

Original Maya and Leo coaches currently use the iPhone's installed speech voices with three styles and a rotating phrase bank. They are not ElevenLabs recordings. Existing authoring credentials returned HTTP 400/401 and the restricted key is expired. No new synthesis, key creation, purchase or upgrade was performed. Existing Arnold and Goggins-inspired bundled recordings remain available. Identity/authenticity/endorsement is not claimed.

Renewed authoring access is needed to generate the new bundled human-like recordings. Once generated they must be reviewed for pronunciation, correct instruction, peak loudness and licensing, then imported into the same offline playback interface. No API key belongs in the app.

## Phone and Watch acceptance

Software tests are not a claim of physical counting accuracy. Test each selected variation with a real iPhone before broad testing. Prior build 17 is preserved separately.

1. Complete onboarding from the upgraded build. Select comfortable wall push-ups and half squats and check the starting labels. Confirm no invented workouts or XP appear.
2. With camera off, enter four reps. Enable camera, do two controlled reps, turn camera off, then pause/resume. Count, elapsed active work and ended sets must stay intact.
3. Perform five reps of each of the nine camera movements, filmed side-on. Include slow reps, shallow rejected reps, bottom holds, bright/dim rooms and varied clothing. Compare against a human reference count.
4. Briefly leave view after an observed bottom, return to the top and check one count. Leave before any bottom observation and check that no rep is invented. Leave for more than two seconds and re-establish position.
5. Let a visibility cue finish. Mute, pause, background and report discomfort in separate trials. No stale cue should restart or talk over the stop instruction.
6. Enable spoken counting in manual mode. Say the next number once, repeat it and then say the following number. Check no duplicate count. Disable mic and enable camera without changing totals. Confirm audio never leaves the phone.
7. Start a real Watch workout with Health permissions. Page between reps, controls and vitals. Pause/resume from Watch, disconnect the phone and check stale metrics disappear. Review the saved Health workout and iPhone report.
8. In airplane mode, exercise setup, manual recording, camera tracking, local coach, path progress, summaries and saved reports must remain usable. On-device speech availability varies with installed system assets.
9. Larger accessibility text, VoiceOver, reduced motion, denied camera/microphone/Health access and unreadable history must leave a usable route and preserve evidence.

## Quick wins to prioritise next

1. Adjustable camera framing overlay and a short framing countdown before a set, with a clear tracking confidence status.
2. Optional rest completion haptic on Watch and phone, plus a short pre-set countdown.
3. Rep correction after camera dropout, explicitly saved as a corrected/self-reported count with the original observations retained.
4. Favourites and a repeat-last-workout button using the last actual targets rather than rebuilding setup.
5. Local reminders with chosen training days and quiet hours.
6. Export a concise progress PDF or CSV that a patient can choose to share with a trainer or GP.
7. Optional dated weight entries and a rolling trend, distinct from exercise energy. Never estimate weight loss from rep counts.
8. Listen to the new build 22 Maya/Leo recordings on physical phones, check all three styles and audio routes, and add an offline voice preview. Recording authoring, bundling, level checks and phrase rotation are implemented.
9. Accessibility presets for larger controls, reduced animation and audio-only instructions.
10. A tester feedback screen that exports device/build, chosen exercise, observed vs corrected counts and an optional user-selected video. No silent health/video uploads.

## Larger features after measurement

- Dataset and benchmark by movement, camera angle, occlusion, lighting, body proportions, mobility, aids and clothing. Report undercount/overcount and time-to-recovery separately. Keep a held-out physical acceptance set.
- Reliable movement-specific range and tempo reports with clear confidence and missing-observation coverage, followed by glute bridge, calf raise, lunge and hold models once validated.
- User-approved personal HR baselines and recovery trends from Watch. Avoid diagnosis or blanket safe/unsafe heart-rate thresholds.
- Workout persistence and resume after process termination, with transactional checkpoints and explicit capture restart.
- StoreKit subscription/paywall and restore purchases after the free testing experience is stable. Put paid value in reviewed programmes and richer history rather than adding provider costs to every workout.
- Clinician-authored programmes, consented patient sharing, governance and prospective evaluation before making treatment or recovery efficacy claims.
- Android and other watches after phone/Watch acceptance. No paid backend is required for the present local experience.

## Validation evidence

See the final implementation receipt for the commands, actual test counts, known failures and physical-device limitations. Build scratch is in `/Volumes/Spottr Development`, hosted by the Extreme SSD development disk image. Archived releases and build 17 were not moved or replaced.

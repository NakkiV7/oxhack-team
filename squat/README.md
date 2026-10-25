# Standalone squat and push-up demo

Imported from **@NakkiV7's `nakki-squat-model`**, exact commit [`42043df31dc0f4059a1d939c74611b7065ebd451`](https://github.com/NakkiV7/oxhack-team/commit/42043df31dc0f4059a1d939c74611b7065ebd451). This Python/OpenCV demo shares a rendering shell, exercise-module interface and experimental cue channel. It is separate from the native Spottr app, its validated session contracts and its voice policy. Local integration fixes below preserve the contributor's exercise thresholds.

The exercise modules use a pretrained MediaPipe pose model plus geometry/state-machine rules; this is not a newly trained exercise model. Accuracy, supported camera angles, clinical assessment, physiology and coaching quality have not been established. The push-up module was ported from the browser prototype, but cross-language count/cue parity has not been measured. [Squat issue #4](https://github.com/NakkiV7/oxhack-team/issues/4) remains a physical-validation task.

## Setup, explicit and optional

Run from the repository root:

```sh
cd squat
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
mkdir -p models
```

The contributor's dependency ranges are retained in the scoped `requirements.txt`; they are **not a tested lockfile**. No dependency installation or real inference was performed for this integration. Neither root nor `squat/` virtual environment was present at the checkpoint.

The default model is **Full, float16, version 1**, from this exact official Google object:

- URL: https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_full/float16/1/pose_landmarker_full.task
- Observed size: **9,398,198 bytes**.
- Observed SHA-256: **`5134a3aad27a58b93da0088d431f366da362b44e3ccfbe3462b3827a839011b1`**.

This is our observed content pin, not an upstream-signed checksum or an inference result. One bounded download was made during integration and retained only in ignored `models/`. Fresh setup can fetch and verify that same object, from `squat/`:

```sh
set -e
curl --fail --location --max-filesize 15728640 \
  https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_full/float16/1/pose_landmarker_full.task \
  --output models/pose_landmarker_full.part
printf '%s  %s\n' \
  5134a3aad27a58b93da0088d431f366da362b44e3ccfbe3462b3827a839011b1 \
  models/pose_landmarker_full.part | shasum -a 256 -c -
mv models/pose_landmarker_full.part models/pose_landmarker_full.task
```

The native app separately pins **Lite**; this setup does not replace its resource or change native inference.

## Run locally

From `squat/`, after installing dependencies:

```sh
.venv/bin/python app.py --exercise squat --voice off
.venv/bin/python app.py --exercise pushup --voice off
.venv/bin/python main.py --exercise squat --source /path/to/your-consented-clip.mp4 --headless --log replay.json
```

`app.py` runs title → optional example → countdown → set → results. Enter skips the example; Space requests it. No example video/audio was imported: the teammate branch's bundled media provenance was not established here. Missing examples are reported and skipped. If you supply an owned/consented example privately, use `assets/example_side.mp4` or `assets/example_pushup.mp4`; a same-name `.m4a` is optional. Assets remain ignored; adding footage does not establish its license or consent.

During a set, **Q finishes early and saves completed reps to the results log**; Space also finishes once there is a completed rep. Q on other screens, Escape or window close quits. R on results starts a fresh set; a file input rewinds and each set gets a fresh video-mode pose engine. The target ends this standalone demo's set automatically; this differs from native Spottr's explicit set controls. Use `--source /path/to/clip.mp4` only as a replay, not as proof of performed live exercise.

`main.py --record raw.mp4` explicitly records camera frames. `eval.py CLIP_DIR --exercise squat --plots out/` prints counts/traces; it does not compare them against independent labels or calculate count accuracy. Keep recordings and outputs private until their consent/attribution is resolved.

## Voice is off by default

An ambient API key does not enable audio or paid synthesis. `--voice say` explicitly uses macOS local speech. `--voice elevenlabs` explicitly enables the optional provider adapter, using `ELEVENLABS_API_KEY` and optional `ELEVENLABS_VOICE_ID` from private `squat/.env` or the environment. Never commit keys or assume a shared voice grants imitation rights.

Construction does not prewarm any speech. A first requested uncached cue synthesizes on demand; subsequent matching backend/voice/model/text requests use disk cache. The first uncached synthesis blocks the demo loop, with a 30-second provider-request timeout. No paid request, speech playback or voice-access verification ran during integration. Audio overlap, completion tracking, cancellation and route behavior remain unaccepted: each playback starts an `afplay` process, and the prototype scheduler is not the native priority/expiry/interruption policy. `--voice off` also keeps the optional example audio silent.

`demo.py` can render an annotated replay with a synthetic speech track; it is an explicit separate command, defaults to local macOS speech and does not establish live cue timing.

## Persistence boundary

`app.py` writes a local `sessions/*.json` diagnostic log; `main.py --log` writes to the requested path. These contain rep metrics/durations and cue times, not a native `SessionRecord`, owner-bound workout or Tiger ingestion payload. They do not carry complete exercise/source/replay identity, observed completion timestamps, session UUID, consent or owner binding. **There is no Tiger upload or native adapter in this demo.** Do not relabel these logs as real user workouts, training labels or skill/XP evidence.

## Offline acceptance and remaining validation

From the repository root, with only Python's standard library:

```sh
python3 -B -W error::ResourceWarning -m unittest discover -s squat/tests -v
```

Thirteen behavior checks passed after observed REDs: safe default with an ambient key; lazy provider synthesis/cache reuse; fresh pose-engine timestamps between sets; Q partial-save; graceful absent example; replay rewind; voice-specific cache identity; mute covering example audio; rejection of duplicate/regressing timestamps before the landmarker; monotonic elapsed capture time in both entry points; and countdown/example timing independent of wall-clock jumps. Tests import the real App/Voice/Pose modules and tracker entry point with fake camera/model/rendering/audio/network boundaries; they do not extract the classes from an AST. All imported Python files also passed compilation-only syntax checks. No physical camera, real model inference, audible playback or provider API calls were exercised.

Before changing native thresholds, use independently labeled, consented full/partial/occlusion/tracking-loss/side-change clips, report observed errors and test native pause/source/generation/timestamp guards. The live capture loops, countdown and example scheduling use monotonic elapsed time; wall-clock date is retained only for session filenames. The Pose wrapper skips nonincreasing timestamps without a detection call, retiming the frame or creating counts. File replay retains its frame-index timestamps. The standalone tracker still skips analyzer updates when no pose is returned and has no native-equivalent tracking-loss/freshness policy. Retain that limitation instead of claiming occlusion acceptance. The native confidence/duration/freshness guards and saved timing provenance remain unchanged.

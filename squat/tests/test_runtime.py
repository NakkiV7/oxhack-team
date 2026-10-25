import importlib.util
import io
import json
import os
from pathlib import Path
import statistics
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch


ROOT = Path(__file__).resolve().parents[1]


def load(name):
    spec = importlib.util.spec_from_file_location("demo_" + name, ROOT / (name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class Image:
    shape = (100, 100, 3)

    def __setitem__(self, key, value):
        pass


class Runtime(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.voice = Mock()
        self.cv = SimpleNamespace(
            FONT_HERSHEY_DUPLEX=0, FONT_HERSHEY_SIMPLEX=0, WND_PROP_VISIBLE=0,
            CAP_PROP_FPS=0, getTextSize=lambda *a: ((10, 10), 0),
            imshow=lambda *a: None, waitKey=lambda *a: 32,
            getWindowProperty=lambda *a: 1, destroyAllWindows=lambda: None,
            resize=lambda *a: Image(), circle=lambda *a: None,
        )
        self.np = SimpleNamespace(full=lambda *a: Image(), uint8=0,
                                  hstack=lambda *a: Image(), mean=statistics.mean)
        self.exercise = SimpleNamespace(NAME="Squat", EXAMPLE="missing.mp4", HINT="Fixture", LINES=[])
        modules = {
            "cv2": self.cv, "numpy": self.np, "squat": self.exercise,
            "common": SimpleNamespace(GREEN=0), "main": SimpleNamespace(draw=lambda *a: None),
            "coach": load("coach"),
            "panel": SimpleNamespace(BG=0, COLOUR={0: 0}, DIM=0, FG=0, W=10,
                                     panel=lambda *a: Image(), text=lambda *a: None),
            "pose": SimpleNamespace(MODELS={"full": Path("synthetic.task")}, Pose=Mock()),
            "voice": SimpleNamespace(STANDARD_LINES=[], Voice=self.voice, load_env=lambda: None),
        }
        imports = patch.dict(sys.modules, modules)
        imports.start()
        self.addCleanup(imports.stop)
        self.app = load("app")
        self.app.HERE = Path(self.folder.name)

    def args(self, **overrides):
        values = dict(exercise="squat", model="full", voice="off", out=None,
                      headless=False, source="0", target=8)
        return SimpleNamespace(**(values | overrides))

    def test_ambient_key_does_not_enable_paid_voice_on_default_launch(self):
        with patch.dict(os.environ, {"ELEVENLABS_API_KEY": "synthetic-not-a-key"}), \
                patch.object(sys, "argv", ["app.py"]), patch.object(self.app.App, "run"):
            self.app.main()
        self.voice.assert_not_called()

    def test_repeating_a_set_never_reverses_a_video_pose_engine_clock(self):
        processed = []

        class Pose:
            def __init__(self, model):
                self.last = -1

            def __call__(self, image, timestamp):
                if timestamp <= self.last:
                    raise ValueError("VIDEO timestamps must increase")
                self.last = timestamp
                processed.append(timestamp)

            def close(self):
                pass

        self.app.Pose = Pose
        self.exercise.Analyzer = lambda: SimpleNamespace(reps=[object()])
        self.cv.VideoCapture = lambda _: SimpleNamespace(isOpened=lambda: True, get=lambda _: 30,
                                                        read=lambda: (True, Image()))
        demo = self.app.App(self.args())
        failure = None
        with patch.object(demo, "show", return_value=32), \
                patch.object(self.app.time, "time", side_effect=[0, 2, 100, 101]), \
                patch.object(self.app.time, "monotonic", side_effect=[0, 2, 100, 101]):
            try:
                demo.live()
                demo.live()
            except ValueError as error:
                failure = error
        self.assertIsNone(failure)
        self.assertEqual(processed, [2000, 1000])

    def test_live_app_capture_uses_elapsed_monotonic_time_when_wall_clock_regresses(self):
        seen = []
        pose = Mock(side_effect=lambda image, timestamp: seen.append(timestamp))
        self.app.Pose = lambda _: pose
        self.exercise.Analyzer = lambda: SimpleNamespace(reps=[])
        self.cv.VideoCapture = lambda _: SimpleNamespace(isOpened=lambda: True, get=lambda _: 30,
                                                        read=lambda: (True, Image()))
        demo = self.app.App(self.args())
        with patch.object(demo, "show", return_value=ord("q")), \
                patch.object(self.app.time, "time", side_effect=[100, 90]), \
                patch.object(self.app.time, "monotonic", side_effect=[50, 50.125]):
            demo.live()
        self.assertEqual(seen, [125])

    def test_live_tracker_capture_uses_elapsed_monotonic_time_when_wall_clock_regresses(self):
        tracker = load("main")
        seen = []
        tracker.Pose = lambda _: Mock(side_effect=lambda image, timestamp: seen.append(timestamp))
        self.exercise.Analyzer = lambda: SimpleNamespace(reps=[], dips=0)
        capture = SimpleNamespace(isOpened=lambda: True, get=lambda _: 30,
            read=Mock(side_effect=[(True, Image()), (False, None)]), release=lambda: None)
        self.cv.VideoCapture = lambda _: capture
        with patch.object(sys, "argv", ["main.py", "--headless"]), patch("sys.stdout", io.StringIO()), \
                patch.object(tracker.time, "time", side_effect=[100, 90]), \
                patch.object(tracker.time, "monotonic", side_effect=[50, 50.125]):
            tracker.main()
        self.assertEqual(seen, [125])

    def test_countdown_uses_elapsed_time_despite_wall_clock_jumps(self):
        demo = self.app.App(self.args())
        demo.is_live = False
        with patch.object(demo, "camera"), patch.object(demo, "show") as shown, \
                patch.object(self.app.time, "time", side_effect=[100, 102, 100, 102, 100, 102]), \
                patch.object(self.app.time, "monotonic", side_effect=[0, 0, 1, 10, 10, 11, 20, 20, 21]):
            demo.countdown()
        self.assertEqual(shown.call_count, 3)

    def test_example_playback_never_waits_for_a_wall_clock_rollback(self):
        assets = self.app.HERE / "assets"
        assets.mkdir()
        (assets / "missing.mp4").write_bytes(b"synthetic")
        self.cv.VideoCapture = lambda _: SimpleNamespace(get=lambda _: 30,
            read=Mock(side_effect=[(True, Image()), (False, None)]), release=lambda: None)
        demo = self.app.App(self.args())
        with patch.object(demo, "show", return_value=-1) as shown, \
                patch.object(self.app.time, "time", side_effect=[100, 90]), \
                patch.object(self.app.time, "monotonic", side_effect=[50, 50.5]):
            demo.example()
        self.assertEqual(shown.call_args.args[1], 1)

    def test_q_finishes_a_partial_set_and_saves_before_quitting_results(self):
        class Analyzer:
            def __init__(self):
                self.reps, self.dips = [], 0

            def update(self, landmarks, time, height):
                self.reps.append(SimpleNamespace(n=1, grade=0, faults=[], t_down=0.5,
                                                 t_up=0.7, worst={}, drop=0.3))
                return SimpleNamespace(events=[])

        class Pose:
            def __init__(self, model):
                pass

            def __call__(self, image, timestamp):
                return object()

            def close(self):
                pass

        self.app.Pose = Pose
        self.exercise.Analyzer = Analyzer
        capture = SimpleNamespace(isOpened=lambda: True, get=lambda _: 30,
                                  read=lambda: (True, Image()), release=Mock())
        self.cv.VideoCapture = lambda _: capture
        self.cv.waitKey = Mock(side_effect=[13, ord("q"), 27])
        demo = self.app.App(self.args())
        with patch.object(demo, "countdown"):
            demo.run()
        logs = list((self.app.HERE / "sessions").glob("*.json"))
        self.assertEqual(len(logs), 1)
        saved = json.loads(logs[0].read_text())
        self.assertEqual([r["n"] for r in saved["reps"]], [1])
        capture.release.assert_called_once()

    def test_missing_example_explains_the_skip_without_opening_media(self):
        capture = self.cv.VideoCapture = Mock(return_value=SimpleNamespace(
            get=lambda _: 30, read=lambda: (False, None), release=lambda: None))
        output = io.StringIO()
        with patch("sys.stdout", output):
            self.app.App(self.args()).example()
        self.assertIn("example", output.getvalue().lower())
        self.assertIn("skip", output.getvalue().lower())
        capture.assert_not_called()

    def test_voice_off_also_keeps_an_example_audio_track_silent(self):
        assets = self.app.HERE / "assets"
        assets.mkdir()
        (assets / "missing.mp4").write_bytes(b"synthetic")
        (assets / "missing.m4a").write_bytes(b"synthetic")
        self.cv.VideoCapture = lambda _: SimpleNamespace(get=lambda _: 30,
            read=lambda: (False, None), release=lambda: None)
        demo = self.app.App(self.args())
        with patch.object(self.app.subprocess, "Popen") as playback:
            demo.example()
        playback.assert_not_called()

    def test_repeating_a_file_set_starts_from_its_first_frame(self):
        seen = []

        class Capture:
            index = 0

            def isOpened(self):
                return True

            def get(self, property):
                return 30

            def set(self, property, value):
                self.index = int(value)

            def read(self):
                image = Image()
                image.number = self.index
                self.index += 1
                return True, image

        class Pose:
            def __init__(self, model):
                pass

            def __call__(self, image, timestamp):
                seen.append(image.number)

            def close(self):
                pass

        self.app.Pose = Pose
        self.cv.CAP_PROP_POS_FRAMES = 1
        self.cv.VideoCapture = lambda _: Capture()
        self.exercise.Analyzer = lambda: SimpleNamespace(reps=[object()])
        demo = self.app.App(self.args(source="synthetic.mp4"))
        with patch.object(demo, "show", return_value=32):
            demo.live()
            demo.live()
        self.assertEqual(seen, [0, 0])


class VoiceBehavior(unittest.TestCase):
    def test_explicit_provider_voice_is_lazy_and_caches_only_requested_cues(self):
        with patch.dict(sys.modules, {"certifi": SimpleNamespace(where=lambda: "unused")}):
            voice = load("voice")
        calls = []

        def synth(text, backend, path):
            calls.append((text, backend))
            path.write_bytes(b"synthetic audio")

        with tempfile.TemporaryDirectory() as folder, patch.object(voice, "CACHE", Path(folder)), \
                patch.object(voice, "load_env"), patch.object(voice, "synth", synth), \
                patch.object(voice.subprocess, "Popen"), patch("builtins.print"):
            speaker = voice.Voice("elevenlabs", ["Go", "Stop"])
            self.assertEqual(calls, [])
            speaker("Go")
            speaker("Go")
            self.assertEqual(calls, [("Go", "elevenlabs")])
            self.assertEqual(len(list(Path(folder).iterdir())), 1)

    def test_selecting_a_different_provider_voice_never_replays_the_old_voice(self):
        with patch.dict(sys.modules, {"certifi": SimpleNamespace(where=lambda: "unused")}):
            voice = load("voice")

        def synth(text, backend, path):
            path.write_bytes(os.environ["ELEVENLABS_VOICE_ID"].encode())

        with tempfile.TemporaryDirectory() as folder, patch.object(voice, "CACHE", Path(folder)), \
                patch.object(voice, "load_env"), patch.object(voice, "synth", synth):
            with patch.dict(os.environ, {"ELEVENLABS_VOICE_ID": "synthetic-voice-a"}):
                first = voice.Voice("elevenlabs").path("Go").read_bytes()
            with patch.dict(os.environ, {"ELEVENLABS_VOICE_ID": "synthetic-voice-b"}):
                second = voice.Voice("elevenlabs").path("Go").read_bytes()
        self.assertEqual(first, b"synthetic-voice-a")
        self.assertEqual(second, b"synthetic-voice-b")


class PoseBehavior(unittest.TestCase):
    def test_duplicate_and_regressing_frames_never_reach_the_landmarker(self):
        seen = []
        landmarker = SimpleNamespace(detect_for_video=lambda image, timestamp:
            (seen.append(timestamp), SimpleNamespace(pose_landmarks=[]))[1], close=lambda: None)
        vision = SimpleNamespace(PoseLandmarkerOptions=SimpleNamespace,
            RunningMode=SimpleNamespace(VIDEO=0),
            PoseLandmarker=SimpleNamespace(create_from_options=lambda _: landmarker))
        modules = {
            "cv2": SimpleNamespace(cvtColor=lambda image, _: image, COLOR_BGR2RGB=0),
            "numpy": SimpleNamespace(ndarray=Image, ascontiguousarray=lambda image: image),
            "mediapipe": SimpleNamespace(Image=lambda **kw: object(),
                                         ImageFormat=SimpleNamespace(SRGB=0)),
            "mediapipe.tasks.python": SimpleNamespace(BaseOptions=SimpleNamespace, vision=vision),
        }
        with patch.dict(sys.modules, modules):
            pose = load("pose").Pose(Path("synthetic.task"))
        for timestamp in [0, 10, 10, 5, 11]:
            self.assertIsNone(pose(Image(), timestamp))
        self.assertEqual(seen, [0, 10, 11])
        pose.close()


if __name__ == "__main__":
    unittest.main()

import http.client
import json
import threading
import unittest
import queue
import companion
import subprocess
import socket
import sys
import time
import ssl
import tempfile
from pathlib import Path
import shutil
import os
from unittest.mock import patch
from datetime import datetime, timezone

from companion import make_server


JPEG = b"\xff\xd8test-fixture-only\xff\xd9"


class FakeCapture:
    def __init__(self):
        self.callback = None
        self.first_frame = JPEG

    def start(self, callback):
        self.callback = callback
        if self.first_frame:
            callback(self.first_frame)

    def stop(self):
        self.callback = None


class FakePipe:
    def __init__(self, chunks):
        self.chunks = iter(chunks)

    def read(self, size):
        return next(self.chunks, b"")

    def close(self):
        pass


class FakeProcess:
    def __init__(self, chunks):
        self.stdout = FakePipe(chunks)
        self.terminated = False

    def poll(self):
        return 0 if self.terminated else None

    def terminate(self):
        self.terminated = True

    def wait(self, timeout):
        return 0


class CaptureDriverTests(unittest.TestCase):
    def test_stopping_a_blocked_pipe_reader_does_not_emit_a_thread_exception(self):
        entered, closed = threading.Event(), threading.Event()
        failures = queue.Queue()

        class ClosingPipe:
            def read(self, size):
                entered.set()
                closed.wait(2)
                raise ValueError("I/O operation on closed file")

            def close(self):
                closed.set()

        process = FakeProcess([])
        process.stdout = ClosingPipe()
        capture = companion.FFmpegCapture(process_factory=lambda *args, **kwargs: process)
        original_thread, readers = threading.Thread, []

        def launch_reader(*args, **kwargs):
            thread = original_thread(*args, **kwargs)
            readers.append(thread)
            return thread

        with patch("companion.threading.Thread", side_effect=launch_reader), \
                patch("threading.excepthook", lambda args: failures.put(args.exc_type)):
            capture.start(lambda frame: self.fail("Stopped reader cannot publish a frame"))
            self.assertTrue(entered.wait(1))
            capture.stop()
            readers[0].join(1)
            self.assertFalse(readers[0].is_alive())
        self.assertTrue(failures.empty(), "Closing the capture pipe leaked a reader exception")

    def test_cli_requires_both_tls_files_when_tls_is_requested(self):
        result = subprocess.run([sys.executable, companion.__file__, "--tls-cert", "missing.pem"],
                                capture_output=True, text=True, timeout=3)
        self.assertEqual(result.returncode, 2)
        self.assertIn("TLS requires both certificate and key", result.stderr)

    def test_incomplete_tls_configuration_cannot_fall_back_to_plain_http(self):
        for options in ({"tls_cert": "missing.pem"}, {"tls_key": "missing.key"}):
            with self.subTest(options=options), self.assertRaises(ValueError):
                make_server(port=0, **options)

    @unittest.skipUnless(shutil.which("openssl"), "TLS check requires existing openssl")
    def test_tls_endpoint_uses_a_verifiable_certificate_without_global_trust_changes(self):
        with tempfile.TemporaryDirectory() as directory:
            cert = Path(directory) / "cert.pem"
            key = Path(directory) / "key.pem"
            subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
                            "-keyout", str(key), "-out", str(cert), "-days", "1",
                            "-subj", "/CN=localhost", "-addext", "subjectAltName=IP:127.0.0.1"],
                           check=True, capture_output=True)
            server = make_server(host="127.0.0.1", port=0, token="test-token",
                                 capture=FakeCapture(), tls_cert=str(cert), tls_key=str(key))
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            connection = http.client.HTTPSConnection(*server.server_address,
                                                     context=ssl.create_default_context(cafile=str(cert)), timeout=2)
            try:
                connection.request("GET", "/health")
                response = connection.getresponse()
                self.assertEqual(response.status, 200)
                self.assertEqual(json.loads(response.read())["camera"], "stopped")
            finally:
                connection.close()
                server.shutdown()
                server.server_close()
                thread.join(2)

    def test_capture_mode_rejects_invalid_sizes_rates_and_filter_expressions(self):
        for options in ({"input_size": "640x480,other"}, {"input_size": "9999x9999"},
                        {"output_size": "640x0"}, {"output_size": "640:360"},
                        {"input_fps": 0}, {"input_fps": 61}, {"output_fps": -1},
                        {"output_fps": True}, {"input_format": "unsupported"}):
            with self.subTest(options=options), self.assertRaises(ValueError):
                companion.FFmpegCapture(**options)

    def test_explicit_elgato_mode_captures_mjpeg_and_emits_small_low_rate_frames(self):
        launches = []
        process = FakeProcess([JPEG])

        def launch(argv, **kwargs):
            launches.append(argv)
            return process

        capture = companion.FFmpegCapture(process_factory=launch,
                                          input_format="mjpeg", input_size="1920x1080",
                                          input_fps=30, output_size="640x360", output_fps=10)
        frames = queue.Queue()
        capture.start(frames.put)
        self.assertEqual(frames.get(timeout=1), JPEG)
        capture.stop()
        argv = launches[0]
        before_input = argv[:argv.index("-i")]
        self.assertIn("mjpeg", before_input)
        self.assertIn("1920x1080", before_input)
        self.assertIn("30", before_input)
        self.assertEqual(argv[argv.index("-vf") + 1], "fps=10,scale=640:360")
        self.assertIn("-threads", argv)

    def test_cli_starts_health_without_opening_camera_and_accepts_termination(self):
        with socket.socket() as reservation:
            reservation.bind(("127.0.0.1", 0))
            port = reservation.getsockname()[1]
        process = subprocess.Popen([sys.executable, companion.__file__, "--port", str(port),
                                    "--input-format", "mjpeg", "--input-size", "1920x1080",
                                    "--input-fps", "30", "--output-size", "640x360", "--output-fps", "10"],
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        health = None
        try:
            deadline = time.monotonic() + 3
            while time.monotonic() < deadline and process.poll() is None:
                connection = http.client.HTTPConnection("127.0.0.1", port, timeout=0.2)
                try:
                    connection.request("GET", "/health")
                    health = json.loads(connection.getresponse().read())
                    break
                except OSError:
                    threading.Event().wait(0.01)
                finally:
                    connection.close()
            self.assertIsNotNone(health)
            self.assertEqual(health["camera"], "stopped")
            self.assertFalse(health["frame_available"])
        finally:
            process.terminate()
            stdout, stderr = process.communicate(timeout=3)
        self.assertEqual(process.returncode, 0, stderr.decode())
        self.assertNotIn(b"Traceback", stderr)

    def test_stop_reaps_a_driver_that_ignores_termination(self):
        class StubbornProcess(FakeProcess):
            killed = False

            def wait(self, timeout):
                if not self.killed:
                    raise subprocess.TimeoutExpired("ffmpeg", timeout)
                return 0

            def kill(self):
                self.killed = True

        process = StubbornProcess([])
        capture = companion.FFmpegCapture(process_factory=lambda *args, **kwargs: process)
        capture.start(lambda frame: None)
        capture.stop()
        self.assertTrue(process.killed)

    def test_oversized_incomplete_frame_is_discarded(self):
        process = FakeProcess([b"\xff\xd8" + b"x" * (4 * 1024 * 1024), JPEG])
        capture = companion.FFmpegCapture(process_factory=lambda *args, **kwargs: process)
        frames = queue.Queue()
        capture.start(frames.put)
        self.assertEqual(frames.get(timeout=1), JPEG)
        capture.stop()

    def test_external_bind_requires_private_token(self):
        with self.assertRaises(ValueError):
            make_server(host="0.0.0.0", port=0)

    def test_ffmpeg_capture_only_launches_on_explicit_start_and_delimits_real_pipe_bytes(self):
        self.assertTrue(hasattr(companion, "FFmpegCapture"))
        process = FakeProcess([b"ignored" + JPEG[:3], JPEG[3:] + JPEG + b"\xff\xd8partial"])
        launches = []

        def launch(argv, **kwargs):
            launches.append((argv, kwargs))
            return process

        capture = companion.FFmpegCapture(device="/dev/video2", process_factory=launch)
        self.assertEqual(launches, [])
        frames = queue.Queue()
        capture.start(frames.put)
        self.assertEqual(frames.get(timeout=1), JPEG)
        self.assertEqual(frames.get(timeout=1), JPEG)
        with self.assertRaises(queue.Empty):
            frames.get(timeout=0.02)
        capture.stop()
        self.assertTrue(process.terminated)
        self.assertIsInstance(launches[0][0], list)
        self.assertIn("/dev/video2", launches[0][0])
        self.assertFalse(launches[0][1].get("shell", False))
        with self.assertRaises(ValueError):
            companion.FFmpegCapture(device="/dev/video0; touch BAD")


@unittest.skipUnless(socket.has_ipv6 and shutil.which("openssl"), "IPv6 TLS needs existing IPv6 and openssl")
class IPv6CompanionTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.cert = Path(self.directory.name) / "cert.pem"
        self.key = Path(self.directory.name) / "key.pem"
        subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
                        "-keyout", str(self.key), "-out", str(self.cert), "-days", "1",
                        "-subj", "/CN=localhost", "-addext", "subjectAltName=IP:::1"],
                       check=True, capture_output=True)

    def make(self, **options):
        args = dict(host="::1", port=0, token="fixture-private-token", capture=FakeCapture(),
                    tls_cert=str(self.cert), tls_key=str(self.key), allowed_network="::1/128")
        args.update(options)
        return make_server(**args)

    def test_exact_ipv6_tls_listener_starts_idle_and_private_routes_require_auth(self):
        server = self.make()
        self.assertEqual(server.address_family, socket.AF_INET6)
        self.assertEqual(server.socket.getsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY), 1)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        context = ssl.create_default_context(cafile=str(self.cert))
        try:
            for route, expected in (("/health", 200), ("/frame.jpg", 401)):
                connection = http.client.HTTPSConnection("::1", server.server_address[1], context=context, timeout=2)
                try:
                    connection.request("GET", route)
                    response = connection.getresponse()
                    self.assertEqual(response.status, expected)
                    body = response.read()
                    if route == "/health":
                        body = json.loads(body)
                        self.assertEqual(body["camera"], "stopped")
                        self.assertFalse(body["frame_available"])
                finally:
                    connection.close()
        finally:
            server.shutdown(); server.server_close(); thread.join(2)

    def test_ipv6_requires_exact_bind_tls_token_and_a_matching_narrow_network(self):
        for options in ({"host": "::"}, {"host": "ff02::1"}, {"host": "::ffff:127.0.0.1"},
                        {"tls_cert": None, "tls_key": None}, {"token": ""},
                        {"allowed_network": None}, {"allowed_network": "::/0"},
                        {"allowed_network": "2001:db8::/64"}, {"allowed_network": "127.0.0.0/8"},
                        {"allowed_network": "not-a-network"}):
            with self.subTest(options=options), self.assertRaises(ValueError):
                server = self.make(**options)
                server.server_close()

    def test_outside_peer_is_closed_before_tls_or_http_processing(self):
        server = self.make()
        listener = server.socket
        accepted = []

        class Peer:
            closed = False
            def close(self): self.closed = True

        peer = Peer()

        class Listener:
            def accept(self):
                accepted.append(True)
                return peer, ("2001:db8::2", 12345, 0, 0)

        try:
            server.socket = Listener()
            with self.assertRaises(OSError):
                server.get_request()
            self.assertEqual(accepted, [True])
            self.assertTrue(peer.closed)
        finally:
            server.socket = listener
            server.server_close()

    def test_cli_rejects_broad_ipv6_network_before_binding_or_loading_tls(self):
        result = subprocess.run([sys.executable, companion.__file__, "--host", "::1",
                                 "--allowed-network", "::/0", "--tls-cert", "missing.pem",
                                 "--tls-key", "missing.key"],
                                env={**os.environ, "SPOTTR_PI_TOKEN": "fixture-private-token"},
                                capture_output=True, text=True, timeout=3)
        self.assertEqual(result.returncode, 2)
        self.assertIn("IPv6 requires an exact bind and matching /64 or narrower peer network", result.stderr)


class CompanionHTTPTests(unittest.TestCase):
    def setUp(self):
        self.capture = FakeCapture()
        self.now = 100.0
        self.server = make_server(host="127.0.0.1", port=0, token="test-private-token",
                                  capture=self.capture, clock=lambda: self.now,
                                  start_timeout=0.02)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(2)

    def request(self, method, path, *, token="test-private-token", body=None):
        connection = http.client.HTTPConnection(*self.server.server_address, timeout=2)
        headers = {"Authorization": f"Bearer {token}"} if token else {}
        payload = body if isinstance(body, bytes) else json.dumps(body) if body is not None else None
        connection.request(method, path, body=payload, headers=headers)
        response = connection.getresponse()
        result = (response.status, dict(response.getheaders()), response.read())
        connection.close()
        return result

    def test_health_is_public_and_server_start_never_opens_camera(self):
        status, headers, body = self.request("GET", "/health", token=None)
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body), {
            "service": "spottr-pi-camera", "role": "capture-forwarding",
            "camera": "stopped", "frame_available": False,
        })
        self.assertEqual(headers["Cache-Control"], "no-store")
        self.assertNotIn("test-private-token", body.decode())

    def test_private_images_and_controls_require_header_authentication(self):
        for method, path in [("GET", "/frame.jpg"), ("GET", "/stream.mjpg"),
                             ("POST", "/camera/start"), ("POST", "/camera/stop")]:
            for token in (None, "wrong"):
                with self.subTest(method=method, path=path, token=token):
                    status, headers, _ = self.request(method, path, token=token)
                    self.assertEqual(status, 401)
                    self.assertEqual(headers["WWW-Authenticate"], "Bearer")
        status, _, _ = self.request("GET", "/frame.jpg?token=test-private-token", token=None)
        self.assertEqual(status, 401)

    def test_non_ascii_authentication_is_rejected_cleanly(self):
        self.assertEqual(self.request("GET", "/frame.jpg", token="é")[0], 401)

    def test_camera_images_are_unavailable_before_explicit_start(self):
        for path in ("/frame.jpg", "/stream.mjpg"):
            with self.subTest(path=path):
                status, headers, body = self.request("GET", path)
                self.assertEqual(status, 503)
                self.assertEqual(json.loads(body)["error"], "camera_unavailable")
                self.assertEqual(headers["Cache-Control"], "no-store")
        self.assertEqual(self.request("GET", "/unknown")[0], 404)

    def test_explicit_capture_returns_fresh_identified_jpeg_and_stop_discards_it(self):
        before = datetime.now(timezone.utc)
        status, _, body = self.request("POST", "/camera/start", body={})
        self.assertEqual(status, 200)
        capture_id = json.loads(body)["capture_id"]
        status, headers, body = self.request("GET", "/frame.jpg")
        self.assertEqual(status, 200)
        self.assertEqual(body, JPEG)
        self.assertEqual(headers["Content-Type"], "image/jpeg")
        self.assertTrue(headers["X-Frame-ID"].startswith(capture_id + ":"))
        self.assertEqual(float(headers["X-Frame-Age-Ms"]), 0)
        self.assertGreaterEqual(datetime.fromisoformat(headers["X-Captured-At"]), before)
        status, _, _ = self.request("POST", "/camera/stop", body={"capture_id": capture_id})
        self.assertEqual(status, 200)
        self.assertEqual(self.request("GET", "/frame.jpg")[0], 503)

    def test_frame_expires_after_two_seconds_without_new_capture(self):
        self.request("POST", "/camera/start", body={})
        self.now += 2.001
        for path in ("/frame.jpg", "/stream.mjpg"):
            self.assertEqual(self.request("GET", path)[0], 503)
        status, _, body = self.request("GET", "/health", token=None)
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body)["camera"], "started")
        self.assertFalse(json.loads(body)["frame_available"])
        self.capture.callback(JPEG)
        self.assertEqual(self.request("GET", "/frame.jpg")[0], 200)

    def test_start_without_camera_or_driver_returns_unavailable_and_no_frame(self):
        self.capture.first_frame = None
        status, _, body = self.request("POST", "/camera/start", body={})
        self.assertEqual(status, 503)
        self.assertEqual(json.loads(body)["error"], "camera_unavailable")
        self.assertEqual(self.request("GET", "/frame.jpg")[0], 503)
        self.assertEqual(json.loads(self.request("GET", "/health")[2])["camera"], "stopped")

    def test_driver_failure_returns_generic_unavailable_without_private_error_details(self):
        def fail(callback):
            raise FileNotFoundError("private-device-location")

        self.capture.start = fail
        status, _, body = self.request("POST", "/camera/start", body={})
        self.assertEqual(status, 503)
        self.assertEqual(json.loads(body), {"error": "camera_unavailable"})
        self.assertIsNone(self.capture.callback)

    def test_server_close_stops_capture(self):
        self.request("POST", "/camera/start", body={})
        self.server.shutdown()
        self.server.server_close()
        self.assertIsNone(self.capture.callback)

    def test_invalid_or_oversized_controls_are_rejected_without_starting_capture(self):
        for body, expected in [(b"{", 400), ([], 400), ({"capture_id": 7}, 400),
                               ({"unexpected": "value"}, 400), (b"x" * 4097, 413)]:
            with self.subTest(body_type=type(body), expected=expected):
                self.assertEqual(self.request("POST", "/camera/start", body=body)[0], expected)
                self.assertIsNone(self.capture.callback)

    def test_stale_controls_and_old_frames_cannot_affect_a_new_capture(self):
        capture_id = json.loads(self.request("POST", "/camera/start", body={})[2])["capture_id"]
        old_callback = self.capture.callback
        for path in ("/camera/start", "/camera/stop"):
            self.assertEqual(self.request("POST", path, body={"capture_id": "old"})[0], 409)
        self.assertEqual(self.request("POST", "/camera/start", body={})[0], 409)
        self.assertEqual(self.request("POST", "/camera/stop", body={})[0], 409)
        renewed = self.request("POST", "/camera/start", body={"capture_id": capture_id})
        self.assertEqual(json.loads(renewed[2])["capture_id"], capture_id)
        self.request("POST", "/camera/stop", body={"capture_id": capture_id})
        new_id = json.loads(self.request("POST", "/camera/start", body={})[2])["capture_id"]
        self.assertNotEqual(new_id, capture_id)
        old_callback(b"\xff\xd8obsolete\xff\xd9")
        self.assertEqual(self.request("GET", "/frame.jpg")[2], JPEG)
        self.assertEqual(self.request("POST", "/camera/stop", body={"capture_id": capture_id})[0], 409)

    def test_capture_lease_expires_and_matching_start_renews_it(self):
        result = self.request("POST", "/camera/start", body={})
        self.assertEqual(json.loads(result[2]).get("lease_seconds"), 60)
        capture_id = json.loads(result[2])["capture_id"]
        self.now += 59
        self.capture.callback(JPEG)
        self.assertEqual(self.request("POST", "/camera/start", body={"capture_id": capture_id})[0], 200)
        self.now += 59
        self.capture.callback(JPEG)
        self.assertEqual(self.request("GET", "/frame.jpg")[0], 200)
        self.now += 2
        self.assertEqual(self.request("GET", "/frame.jpg")[0], 503)
        self.assertEqual(json.loads(self.request("GET", "/health")[2])["camera"], "stopped")
        self.assertEqual(self.request("POST", "/camera/start", body={"capture_id": capture_id})[0], 409)
        self.assertIsNone(self.capture.callback)

    def test_mjpeg_stream_has_identified_parts_and_ends_when_capture_stops(self):
        capture_id = json.loads(self.request("POST", "/camera/start", body={})[2])["capture_id"]
        connection = http.client.HTTPConnection(*self.server.server_address, timeout=2)
        connection.request("GET", "/stream.mjpg", headers={"Authorization": "Bearer test-private-token"})
        response = connection.getresponse()
        try:
            self.assertEqual(response.status, 200)
            self.assertEqual(response.getheader("Content-Type"), "multipart/x-mixed-replace; boundary=frame")
            first_headers, first_body = self.read_part(response)
            self.assertEqual(first_body, JPEG)
            self.capture.callback(JPEG + b"second")
            second_headers, second_body = self.read_part(response)
            self.assertNotEqual(first_headers["X-Frame-ID"], second_headers["X-Frame-ID"])
            self.assertIn("X-Captured-At", second_headers)
            self.assertEqual(second_body, JPEG + b"second")
            self.request("POST", "/camera/stop", body={"capture_id": capture_id})
            self.assertEqual(response.read(), b"--frame--\r\n")
        finally:
            connection.close()

    def read_part(self, response):
        self.assertEqual(response.readline(), b"--frame\r\n")
        headers = {}
        while True:
            line = response.readline()
            if line == b"\r\n":
                break
            key, value = line.decode().strip().split(": ", 1)
            headers[key] = value
        body = response.read(int(headers["Content-Length"]))
        self.assertEqual(response.read(2), b"\r\n")
        return headers, body


if __name__ == "__main__":
    unittest.main()

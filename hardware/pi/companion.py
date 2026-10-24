from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from dataclasses import dataclass
from datetime import datetime, timezone
import argparse
import json
import hmac
import os
import re
import signal
import ssl
import subprocess
import threading
import time
import uuid


class FFmpegCapture:
    def __init__(self, *, device="/dev/video0", process_factory=subprocess.Popen,
                 input_format=None, input_size="640x480", input_fps=10,
                 output_size=None, output_fps=None):
        if not re.fullmatch(r"/dev/video[0-9]+", device):
            raise ValueError("device must be /dev/video followed by a number")
        for size in (input_size, output_size):
            if size is None:
                continue
            if not isinstance(size, str) or not re.fullmatch(r"[0-9]{2,4}x[0-9]{2,4}", size):
                raise ValueError("capture sizes must be WIDTHxHEIGHT")
            width, height = map(int, size.split("x"))
            if not (16 <= width <= 3840 and 16 <= height <= 2160):
                raise ValueError("capture size must be between 16x16 and 3840x2160")
        for rate in (input_fps, output_fps):
            if rate is not None and (type(rate) is not int or not 1 <= rate <= 60):
                raise ValueError("capture frame rates must be integers from 1 to 60")
        if input_format not in (None, "mjpeg", "h264", "nv12", "yuyv422"):
            raise ValueError("unsupported camera input format")
        self.device = device
        self.process_factory = process_factory
        self.process = None
        self.input_format = input_format
        self.input_size = input_size
        self.input_fps = input_fps
        self.output_size = output_size
        self.output_fps = output_fps

    def start(self, callback):
        argv = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-nostdin",
                "-f", "v4l2", "-framerate", str(self.input_fps),
                "-video_size", self.input_size, "-threads", "1"]
        if self.input_format:
            argv.extend(["-input_format", self.input_format])
        argv.extend(["-i", self.device, "-an"])
        filters = []
        if self.output_fps:
            filters.append(f"fps={self.output_fps}")
        if self.output_size:
            filters.append("scale=" + self.output_size.replace("x", ":"))
        if filters:
            argv.extend(["-vf", ",".join(filters)])
        argv.extend(["-threads", "1", "-c:v", "mjpeg", "-q:v", "5",
                     "-f", "image2pipe", "pipe:1"])
        self.process = self.process_factory(argv, stdin=subprocess.DEVNULL,
                                            stdout=subprocess.PIPE,
                                            stderr=subprocess.DEVNULL, bufsize=0)
        threading.Thread(target=self.read_frames, args=(self.process.stdout, callback),
                         daemon=True).start()

    def read_frames(self, pipe, callback):
        buffer = b""
        while chunk := pipe.read(65536):
            buffer += chunk
            if len(buffer) > 4 * 1024 * 1024:
                buffer = buffer[-1:]
                continue
            while True:
                start = buffer.find(b"\xff\xd8")
                if start < 0:
                    buffer = buffer[-1:]
                    break
                buffer = buffer[start:]
                end = buffer.find(b"\xff\xd9", 2)
                if end < 0:
                    break
                callback(buffer[:end + 2])
                buffer = buffer[end + 2:]

    def stop(self):
        process = self.process
        self.process = None
        if process is None:
            return
        if process.poll() is None:
            process.terminate()
        try:
            process.wait(timeout=1)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=1)
        process.stdout.close()


@dataclass(frozen=True)
class Frame:
    jpeg: bytes
    frame_id: str
    captured_at: str
    monotonic: float


class ControlConflict(Exception):
    pass


class Camera:
    def __init__(self, *, capture, clock, start_timeout):
        self.capture = capture
        self.clock = clock
        self.start_timeout = start_timeout
        self.lock = threading.Condition(threading.RLock())
        self.frame = None
        self.capture_id = None
        self.sequence = 0
        self.deadline = 0.0
        self.timer = None
        self.lease_seconds = 60

    def publish(self, jpeg, capture_id):
        with self.lock:
            if capture_id != self.capture_id:
                return
            self.sequence += 1
            self.frame = Frame(jpeg, f"{capture_id}:{self.sequence}",
                               datetime.now(timezone.utc).isoformat(), self.clock())
            self.lock.notify_all()

    def start(self, expected_id):
        with self.lock:
            self.expire()
            if expected_id != self.capture_id:
                raise ControlConflict()
            if self.capture_id:
                self.renew()
                return self.capture_id
            capture_id = uuid.uuid4().hex
            self.capture_id = capture_id
            try:
                self.capture.start(lambda jpeg: self.publish(jpeg, capture_id))
            except OSError:
                self.stop()
                return None
            self.lock.wait_for(lambda: self.frame is not None, self.start_timeout)
            if self.snapshot() is None:
                self.stop()
                return None
            self.renew()
            return self.capture_id

    def renew(self):
        if self.timer:
            self.timer.cancel()
        self.deadline = self.clock() + self.lease_seconds
        self.timer = threading.Timer(self.lease_seconds, self.expire)
        self.timer.daemon = True
        self.timer.start()

    def expire(self):
        with self.lock:
            if self.capture_id and self.deadline and self.clock() >= self.deadline:
                self.stop()

    def stop(self):
        with self.lock:
            self.capture_id = None
            self.frame = None
            self.deadline = 0.0
            if self.timer:
                self.timer.cancel()
                self.timer = None
            self.capture.stop()
            self.lock.notify_all()

    def stop_matching(self, expected_id):
        with self.lock:
            self.expire()
            if expected_id != self.capture_id:
                raise ControlConflict()
            self.stop()

    def snapshot(self):
        with self.lock:
            self.expire()
            if self.frame and self.clock() - self.frame.monotonic > 2.0:
                return None
            return self.frame


def make_server(*, host="127.0.0.1", port=8765, token="", capture=None,
                clock=None, start_timeout=2.0, tls_cert=None, tls_key=None):
    if host not in ("127.0.0.1", "localhost") and not token:
        raise ValueError("external binding requires SPOTTR_PI_TOKEN")
    if bool(tls_cert) != bool(tls_key):
        raise ValueError("TLS requires both certificate and key")
    context = None
    if tls_cert:
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(tls_cert, tls_key)
    camera = Camera(capture=capture or FFmpegCapture(), clock=clock or time.monotonic,
                    start_timeout=start_timeout)

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, format, *args):
            pass

        def do_GET(self):
            if self.path != "/health" and not self.authorized():
                return
            if self.path in ("/frame.jpg", "/stream.mjpg"):
                frame = camera.snapshot()
                if frame is None:
                    return self.json_response(503, {"error": "camera_unavailable"})
                if self.path == "/stream.mjpg":
                    return self.stream(frame)
                self.send_response(200)
                self.send_header("Content-Type", "image/jpeg")
                self.send_header("Content-Length", str(len(frame.jpeg)))
                self.send_header("Cache-Control", "no-store")
                self.send_header("X-Frame-ID", frame.frame_id)
                self.send_header("X-Captured-At", frame.captured_at)
                self.send_header("X-Frame-Age-Ms", str((camera.clock() - frame.monotonic) * 1000))
                self.end_headers()
                return self.wfile.write(frame.jpeg)
            if self.path != "/health":
                return self.json_response(404, {"error": "not_found"})
            frame = camera.snapshot()
            self.json_response(200, {
                "service": "spottr-pi-camera", "role": "capture-forwarding",
                "camera": "started" if camera.capture_id else "stopped",
                "frame_available": frame is not None,
            })

        def stream(self, frame):
            self.send_response(200)
            self.send_header("Content-Type", "multipart/x-mixed-replace; boundary=frame")
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            capture_id = frame.frame_id.split(":", 1)[0]
            previous_id = None
            try:
                while frame and frame.frame_id.startswith(capture_id + ":"):
                    if frame.frame_id != previous_id:
                        headers = (f"--frame\r\nContent-Type: image/jpeg\r\n"
                                   f"Content-Length: {len(frame.jpeg)}\r\n"
                                   f"X-Frame-ID: {frame.frame_id}\r\n"
                                   f"X-Captured-At: {frame.captured_at}\r\n"
                                   f"X-Frame-Age-Ms: {(camera.clock() - frame.monotonic) * 1000}\r\n\r\n")
                        self.wfile.write(headers.encode() + frame.jpeg + b"\r\n")
                        previous_id = frame.frame_id
                    with camera.lock:
                        camera.lock.wait(timeout=0.1)
                        frame = camera.snapshot()
                self.wfile.write(b"--frame--\r\n")
            except (BrokenPipeError, ConnectionResetError):
                pass

        def json_response(self, status, value):
            body = json.dumps(value).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def authorized(self):
            value = self.headers.get("Authorization", "")
            if token and hmac.compare_digest(value.encode(), f"Bearer {token}".encode()):
                return True
            self.send_response(401)
            self.send_header("WWW-Authenticate", "Bearer")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return False

        def do_POST(self):
            if not self.authorized():
                return
            try:
                length = int(self.headers.get("Content-Length", "0"))
                if length > 4096:
                    return self.json_response(413, {"error": "body_too_large"})
                if length < 0 or self.headers.get("Transfer-Encoding"):
                    raise ValueError()
                body = json.loads(self.rfile.read(length)) if length else {}
                if not isinstance(body, dict) or set(body) - {"capture_id"}:
                    raise ValueError()
                if "capture_id" in body and not isinstance(body["capture_id"], str):
                    raise ValueError()
            except (ValueError, UnicodeDecodeError):
                return self.json_response(400, {"error": "invalid_control"})
            try:
                self.control(body.get("capture_id"))
            except ControlConflict:
                self.json_response(409, {"error": "capture_conflict"})

        def control(self, expected_id):
            if self.path == "/camera/start":
                capture_id = camera.start(expected_id)
                if capture_id is None:
                    return self.json_response(503, {"error": "camera_unavailable"})
                return self.json_response(200, {"capture_id": capture_id,
                                                "lease_seconds": camera.lease_seconds})
            if self.path == "/camera/stop":
                camera.stop_matching(expected_id)
                return self.json_response(200, {"camera": "stopped"})
            self.json_response(404, {"error": "not_found"})

    class Server(ThreadingHTTPServer):
        def server_close(self):
            camera.stop()
            super().server_close()

    server = Server((host, port), Handler)
    if context:
        server.socket = context.wrap_socket(server.socket, server_side=True)
    return server


def main():
    parser = argparse.ArgumentParser(description="Spottr Pi capture-forwarding; camera opens only after POST /camera/start")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--device", default="/dev/video0")
    parser.add_argument("--input-format", choices=("mjpeg", "h264", "nv12", "yuyv422"))
    parser.add_argument("--input-size", default="640x480")
    parser.add_argument("--input-fps", type=int, default=10)
    parser.add_argument("--output-size")
    parser.add_argument("--output-fps", type=int)
    parser.add_argument("--tls-cert")
    parser.add_argument("--tls-key")
    args = parser.parse_args()
    try:
        server = make_server(host=args.host, port=args.port,
                             token=os.environ.get("SPOTTR_PI_TOKEN", ""),
                             tls_cert=args.tls_cert, tls_key=args.tls_key,
                             capture=FFmpegCapture(device=args.device, input_format=args.input_format,
                                                   input_size=args.input_size, input_fps=args.input_fps,
                                                   output_size=args.output_size, output_fps=args.output_fps))
    except ValueError as error:
        parser.error(str(error))

    def interrupt(signum, frame):
        raise KeyboardInterrupt()

    signal.signal(signal.SIGTERM, interrupt)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()

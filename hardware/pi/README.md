# Optional Raspberry Pi side camera

This companion captures and forwards camera JPEGs. The iPhone remains the training-session owner and runs pose inference and rep counting. This is preparation for replacing the Arduino hardware role with a Pi and a side camera; it does not implement onboard inference, Bluetooth, sensors, a display, workout state, or motor control.

Nothing here has been copied to or started on the bootcamp Pi. Its current hostname, OS, camera support and available resources are unverified. Preserve the existing bootcamp/LAVA setup. Do not replace its network profile, autostart services, packages or working camera processes to try this adapter.

## Prerequisites and initial health check

Use Python 3.10+ on Linux. Python dependencies are standard library only. Actual capture additionally needs an existing `ffmpeg` installation with the `v4l2` input and MJPEG encoder, a USB/V4L2 camera accessible to the current user, and support for 640×480 at 10 fps. Check the camera's actual modes before adapting those defaults. CSI/libcamera cameras need a separate driver and are not supported by this adapter.

When the Pi and camera are ready, manually copy only this directory to a separate checkout or folder. Check `python3 --version`, `command -v ffmpeg` and the camera device without installing anything automatically. If a prerequisite is absent, agree the installation or driver change with the owner of the existing Pi workload first.

From the repository root:

```bash
python3 -m unittest discover -s hardware/pi -v
python3 hardware/pi/companion.py
```

The server defaults to `127.0.0.1:8765`. `GET /health` is public and returns only the service role, stopped/started state and whether a fresh frame exists. Starting the process never opens the camera. Without a token, private routes remain inaccessible; health can be checked before a camera is attached. A successful health response does not demonstrate camera readiness.

Set `SPOTTR_PI_TOKEN` privately in the process environment to enable authenticated capture. Use a random token of at least 32 characters, keep it out of the repository, and transfer it to the eventual phone settings privately. The token has no command-line flag. For a Bash shell, hidden entry is:

```bash
read -r -s -p 'Pi access token: ' SPOTTR_PI_TOKEN
export SPOTTR_PI_TOKEN
python3 hardware/pi/companion.py --device /dev/video0
```

For eventual network access, `--host <verified-Pi-interface-address>` binds the chosen interface and refuses to run without a token. This small development server supplies plain HTTP. Protect bearer tokens and camera images with a trusted HTTPS proxy or private encrypted tunnel before phone access. Native phone ingestion, its HTTPS endpoint, pairing UI and ATS/network acceptance are still outstanding. No port forwarding, DNS or service configuration is included here.

## HTTP contract

Every route except exact `GET /health` requires `Authorization: Bearer <token>`. Query-string tokens are never accepted. Responses use `Cache-Control: no-store`; images are kept only in memory. There is no image upload, recording, on-disk image archive or synthetic fallback.

| Route | Behavior |
| --- | --- |
| `GET /health` | Public, no token, device path, capture ID or image content in its response. HTTP 200 indicates the adapter responds. |
| `POST /camera/start` with `{}` | Explicitly opens the configured device and waits up to 2 seconds for a complete JPEG. Returns 200 with `capture_id` and `lease_seconds: 60`, or 503 `camera_unavailable` for a missing driver, unsupported mode, camera or first frame. |
| `POST /camera/start` with `{"capture_id":"current ID"}` | Renews the current capture lease for 60 seconds. Renew before it expires, for example every 30 seconds while the user explicitly keeps capture active. This acknowledges lease renewal; check frame freshness separately. |
| `POST /camera/stop` with `{"capture_id":"current ID"}` | Closes capture and discards its frame. Stops are idempotent with `{}` when already stopped. |
| `GET /frame.jpg` | Returns the latest fresh JPEG or 503 `camera_unavailable`. |
| `GET /stream.mjpg` | Authenticated multipart MJPEG preview with the same frame metadata on each part. Sends a frame once per ID; ends on capture stop, replacement, expiry, or stale imagery. A stale stream must be reopened after fresh capture resumes. |

A start/renew/stop referring to an old capture ID returns 409 `capture_conflict`. An active capture cannot be replaced or stopped by a start/stop that omits its ID. After lease expiry, restart explicitly with `{}` and use the new returned ID. Late frames from an older capture are discarded. Control JSON accepts only an optional string `capture_id`, with a 4 KiB body limit. Unknown routes return 404; invalid controls return 400; oversized bodies return 413; missing/wrong authorization returns 401.

Private JPEG responses and every MJPEG part include:

- `X-Frame-ID`: unique capture ID plus a monotonically increasing sequence. Clients must deduplicate by ID.
- `X-Captured-At`: Pi UTC timestamp when the complete JPEG reaches this adapter. This is a host receipt estimate, not a sensor exposure timestamp; it cannot prove sensor-to-phone latency or clock synchronization.
- `X-Frame-Age-Ms`: age since receipt using the Pi's monotonic clock. Imagery older than 2 seconds is rejected. Network delay after this header is produced is additional; clients must apply their own receive deadline and reject duplicates/stale frames before inference.

FFmpeg runs only after authenticated explicit start, using a fixed argv list without a shell. The device path must match `/dev/video<digits>`. The bounded JPEG parser accepts complete JPEG marker-delimited frames from that process. Raw driver errors and access headers are not printed. A driver that stops emitting frames becomes unavailable after the freshness window; an expired lease stops capture even without another request. Ctrl-C, SIGTERM and server close also stop and reap the capture process.

An ordinary browser `<img>` URL cannot attach a bearer header. Use a client that sends the header, or an authenticated fetch client for the MJPEG parts. Do not work around that by putting the token in a preview URL.

## Acceptance still needed with the real camera

The tests exercise real localhost HTTP and an injected capture/process boundary. Their test byte fixtures are never available in the runnable server. They establish HTTP behavior, authentication, framing, expiry and lifecycle handling; they do not establish Pi capture, resolution support, image orientation, exposure, clock quality, latency, side-view pose accuracy or iPhone ingestion.

Once the actual camera is connected, explicitly start it and verify a real JPEG, preview, timestamps, stop, missing-camera response and lease expiry. Measure end-to-end delay and dropped frames, confirm the iPhone rejects stale/duplicate side frames, and validate the side-view exercise tracking before counting reps from this source. Keep the phone's own session and inference as the authority throughout that integration.
